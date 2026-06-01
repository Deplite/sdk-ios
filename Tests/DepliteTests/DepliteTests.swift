import XCTest
@testable import Deplite

final class DepliteExternalTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    private func makeDeplite() -> Deplite {
        Deplite(
            apiToken: "dep_test",
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
        XCTAssertEqual(req.headers["Authorization"], "Bearer dep_test")
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
}
