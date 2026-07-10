import XCTest
@testable import Deplite

final class DepliteExternalTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    private func makeDeplite() -> Deplite {
        Deplite(
            apiToken: "dpl_test",
            baseURL: URL(string: "https://api.test.example/v1")!,
            session: MockURLProtocol.session()
        )
    }

    func testTriggersRun() async throws {
        MockURLProtocol.enqueue(.json(200, [
            "jobId": "job-1",
            "status": "queued",
        ]))
        let dep = makeDeplite()
        let result = try await dep.triggers.run(
            triggerId: "trg",
            params: ["ref": "main"],
            idempotencyKey: "key-1"
        )
        XCTAssertEqual(result.jobId, "job-1")
        XCTAssertEqual(result.status, "queued")
        XCTAssertFalse(result.idempotent)
        XCTAssertFalse(result.timedOut)

        let req = MockURLProtocol.captured.first!
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.absoluteString, "https://api.test.example/v1/triggers/trg/run")
        XCTAssertEqual(req.headers["Authorization"], "Bearer dpl_test")
        XCTAssertEqual(req.headers["Idempotency-Key"], "key-1")
        let bodyJson = try JSONSerialization.jsonObject(with: req.body) as! [String: Any]
        XCTAssertEqual(bodyJson["params"] as? [String: String], ["ref": "main"])
        XCTAssertNil(bodyJson["debug"])
        XCTAssertNil(bodyJson["workflowName"])
    }

    func testUnauthorized() async throws {
        MockURLProtocol.enqueue(.init(status: 401, body: Data("nope".utf8)))
        do {
            let _: TriggerRunResult = try await makeDeplite().triggers.run(triggerId: "x")
            XCTFail("expected throw")
        } catch DepliteError.unauthorized(let code, let body) {
            XCTAssertEqual(code, 401)
            XCTAssertEqual(body, "nope")
        }
    }

    func testServerError() async throws {
        MockURLProtocol.enqueue(.init(status: 500, body: Data("boom".utf8)))
        do {
            let _: TriggerRunResult = try await makeDeplite().triggers.run(triggerId: "x")
            XCTFail("expected throw")
        } catch DepliteError.api(let code, let body) {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(body, "boom")
        }
    }

    func testFilesUploadFlow() async throws {
        // 1. presign
        MockURLProtocol.enqueue(.json(200, [
            "fileId": "file-1",
            "uploadUrl": "https://uploads.test.example/put/abc",
            "uploadHeaders": ["X-Sig": "v"] as [String: String],
            "expiresInSeconds": 60,
        ]))
        // 2. PUT (mock receives empty 200)
        MockURLProtocol.enqueue(.init(status: 200))
        // 3. complete
        MockURLProtocol.enqueue(.json(200, [
            "id": "file-1",
            "filename": "data.bin",
            "status": "ready",
        ]))

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("deplite-test-\(UUID().uuidString).bin")
        try Data("payload".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let meta = try await makeDeplite().files.upload(fileURL: tmp)
        XCTAssertEqual(meta.id, "file-1")
        XCTAssertEqual(MockURLProtocol.captured.count, 3)
        XCTAssertEqual(MockURLProtocol.captured[1].method, "PUT")
        XCTAssertEqual(MockURLProtocol.captured[1].url.absoluteString, "https://uploads.test.example/put/abc")
    }

    func testOnJobEndRejectedInExternal() async {
        do {
            _ = try await makeDeplite().files.presignUpload(cleanupRule: .onJobEnd)
            XCTFail("should throw")
        } catch DepliteError.signing { /* ok */ } catch { XCTFail("wrong error: \(error)") }
    }

    func testTokenInfoDecodesEveryGrantType() async throws {
        MockURLProtocol.enqueue(.init(status: 200, body: Data("""
        {"organizationId":"org-1","name":"ci",
         "scopes":[{"type":"agent","agentIds":["a-1"]},
                   {"type":"trigger","triggerIds":["t-1"]},
                   {"type":"storage","bindingIds":null,"permissions":["read","write"]},
                   {"type":"quantum","foo":1}],
         "rateLimit":{"perMinute":60,"perHour":null,"perDay":null},
         "expiresAt":null}
        """.utf8)))

        let info = try await makeDeplite().token.info()
        XCTAssertEqual(info.organizationId, "org-1")
        XCTAssertEqual(info.name, "ci")
        XCTAssertEqual(info.rateLimit.perMinute, 60)
        XCTAssertNil(info.expiresAt)
        XCTAssertEqual(info.scopes[0], .agent(agentIds: ["a-1"]))
        XCTAssertEqual(info.scopes[1], .trigger(triggerIds: ["t-1"]))
        XCTAssertEqual(info.scopes[2], .storage(bindingIds: nil, permissions: [.read, .write]))
        XCTAssertEqual(info.scopes[3], .unknown(type: "quantum"))

        let req = MockURLProtocol.captured.first!
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url.absoluteString, "https://api.test.example/v1/token")
        XCTAssertEqual(req.headers["Authorization"], "Bearer dpl_test")
    }

    func testAgentsList() async throws {
        MockURLProtocol.enqueue(.init(status: 200, body: Data("""
        [{"id":"a-1","name":"kiosk-1","hostname":null,"os":"linux",
          "agentVersion":"0.1.0","status":"connected",
          "lastSeenAt":"2026-07-09T00:00:00.000Z",
          "enrolledAt":"2026-07-01T00:00:00.000Z"}]
        """.utf8)))

        let agents = try await makeDeplite().agents.list()
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].status, .connected)
        XCTAssertNil(agents[0].hostname)
        XCTAssertEqual(agents[0].registeredAt, "2026-07-01T00:00:00.000Z")
        XCTAssertEqual(MockURLProtocol.captured.first!.url.absoluteString, "https://api.test.example/v1/agents")
    }

    func testWorkflowsList() async throws {
        MockURLProtocol.enqueue(.init(status: 200, body: Data("""
        [{"id":"w-1","agentId":"a-1","name":"deploy","description":null,"version":"1.2.0",
          "paramsSchema":[{"name":"ref","type":"string","required":true}]}]
        """.utf8)))

        let workflows = try await makeDeplite().workflows.list()
        XCTAssertEqual(workflows[0].name, "deploy")
        let param = workflows[0].paramsSchema!.first!
        XCTAssertEqual(param.name, "ref")
        XCTAssertEqual(param.type, .string)
        XCTAssertEqual(param.required, true)
        XCTAssertEqual(MockURLProtocol.captured.first!.url.absoluteString, "https://api.test.example/v1/workflows")
    }

    func testReadRateLimitSurfacesTokenReadScope() async {
        let body = #"{"statusCode":429,"error":"Too Many Requests","scope":"token_read"}"#
        MockURLProtocol.enqueue(.init(status: 429, body: Data(body.utf8)))
        do {
            _ = try await makeDeplite().agents.list()
            XCTFail("expected throw")
        } catch DepliteError.api(let code, let body) {
            XCTAssertEqual(code, 429)
            XCTAssertTrue(body.contains("\"scope\":\"token_read\""))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
