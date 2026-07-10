import XCTest
@testable import Deplite

final class DepliteAgentEmbeddedTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    private func makeAgent() throws -> (DepliteAgent, Ed25519Key) {
        let key = Ed25519Key.generate()
        let identity = AgentIdentity(
            agentId: "agent-1",
            organizationId: "org-1",
            baseURL: URL(string: "https://api.test.example/v1")!,
            serverPublicKeyPEM: key.publicKeyPEM()
        )
        let agent = try DepliteAgent(identity: identity, privateKey: key.rawSeed, session: MockURLProtocol.session())
        return (agent, key)
    }

    func testHeartbeatSendsSignedHeaders() async throws {
        MockURLProtocol.enqueue(.init(status: 200))
        let (agent, _) = try makeAgent()
        try await agent.heartbeat()
        let req = MockURLProtocol.captured.first!
        XCTAssertEqual(req.url.absoluteString, "https://api.test.example/v1/agent/heartbeat")
        XCTAssertEqual(req.headers["x-agent-id"], "agent-1")
        XCTAssertNotNil(req.headers["x-timestamp"])
        XCTAssertNotNil(req.headers["x-nonce"])
        XCTAssertNotNil(req.headers["x-signature"])
    }

    func testWorkflowsReportParsesCount() async throws {
        MockURLProtocol.enqueue(.json(200, ["count": 3]))
        let (agent, _) = try makeAgent()
        let n = try await agent.workflows.report([WorkflowReport(name: "wf1")])
        XCTAssertEqual(n, 3)
    }

    func testUpdateIdentityBody() async throws {
        MockURLProtocol.enqueue(.init(status: 200))
        let (agent, _) = try makeAgent()
        try await agent.updateIdentity(hostname: "h", os: "macos")
        let req = MockURLProtocol.captured.first!
        XCTAssertEqual(req.method, "PATCH")
        let json = try JSONSerialization.jsonObject(with: req.body) as! [String: Any]
        XCTAssertEqual(json["hostname"] as? String, "h")
        XCTAssertEqual(json["os"] as? String, "macos")
        XCTAssertNil(json["agentVersion"])
    }

    func testAppendLogsEmptyReturnsZeroWithoutNetwork() async throws {
        let (agent, _) = try makeAgent()
        let n = try await agent.jobs.appendLogs(jobId: "j", items: [])
        XCTAssertEqual(n, 0)
        XCTAssertTrue(MockURLProtocol.captured.isEmpty)
    }

    func testEventsStreamParsesSSE() async throws {
        let raw = "event: ping\ndata: \n\nevent: revoke\ndata: \n\n"
        MockURLProtocol.enqueue(.sse(raw))
        let (agent, _) = try makeAgent()
        var collected: [String] = []
        let stream = agent.events()
        do {
            for try await ev in stream {
                switch ev {
                case .ping: collected.append("ping")
                case .revoke: collected.append("revoke")
                case .deploy: collected.append("deploy")
                case .cancel: collected.append("cancel")
                case .syncWorkflows: collected.append("sync")
                case .unknown(let n, _): collected.append("u:\(n)")
                }
                if collected.count == 2 { break }
            }
        } catch is DepliteError {
            // sseClosed is expected when stream ends
        }
        XCTAssertEqual(collected, ["ping", "revoke"])
    }

    private func signManifest(_ payload: String, key: Ed25519Key) throws -> String {
        let node = try CanonicalJSON.parse(payload)
        return try key.sign(Data(CanonicalJSON.encode(node).utf8)).base64EncodedString()
    }

    func testDeployDesiredVerifiesAndMapsSignedManifests() async throws {
        let (agent, key) = try makeAgent()
        // `&` in the presigned URL exercises the Go-compatible canonical escaping;
        // `future_field` proves unknown fields survive raw-payload verification.
        let payload = #"""
        {"application_id":"app-1","slug":"my-app","channel":"stable","update_workflow":"ota.yml","current":{"release_id":"r-1","version":"1.0.0","sequence":10},"desired":{"release_id":"r-2","version":"1.1.0","sequence":11,"channel":"stable","workflow_name":"ota.yml","checksum_sha256":"deadbeef","size":1234,"download_url":"https://s3.example.com/o?a=1&b=2","download_expires_in":3600},"min_version":"1.0.0","min_sequence":5,"forced":false,"issued_at":1700000000,"nonce":"n-1","future_field":"x"}
        """#
        let signature = try signManifest(payload, key: key)
        let body = #"{"apps":[{"payload":\#(payload),"signature":"\#(signature)"}]}"#
        MockURLProtocol.enqueue(.init(status: 200, body: Data(body.utf8)))

        let apps = try await agent.deploy.desired()
        let req = MockURLProtocol.captured.first!
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url.absoluteString, "https://api.test.example/v1/agent/deploy/desired")
        XCTAssertNotNil(req.headers["x-signature"])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].applicationId, "app-1")
        XCTAssertEqual(apps[0].current?.sequence, 10)
        XCTAssertEqual(apps[0].desired?.workflowName, "ota.yml")
        XCTAssertEqual(apps[0].desired?.downloadUrl, "https://s3.example.com/o?a=1&b=2")
        XCTAssertEqual(apps[0].minSequence, 5)
    }

    func testDeployDesiredRejectsTamperedManifest() async throws {
        let (agent, key) = try makeAgent()
        let payload = #"{"application_id":"app-1","slug":"my-app","current":null,"desired":null,"min_version":null,"min_sequence":0,"forced":false,"issued_at":1,"nonce":"n"}"#
        let signature = try signManifest(payload, key: key)
        let tampered = payload.replacingOccurrences(of: "\"my-app\"", with: "\"evil\"")
        let body = #"{"apps":[{"payload":\#(tampered),"signature":"\#(signature)"}]}"#
        MockURLProtocol.enqueue(.init(status: 200, body: Data(body.utf8)))

        do {
            _ = try await agent.deploy.desired()
            XCTFail("expected verification error")
        } catch let DepliteError.verification(reason) {
            XCTAssertTrue(reason.contains("evil"), reason)
        }
    }

    func testDeployDesiredRejectsEmptySignature() async throws {
        let (agent, _) = try makeAgent()
        let body = #"{"apps":[{"payload":{"application_id":"app-1","slug":"my-app"},"signature":""}]}"#
        MockURLProtocol.enqueue(.init(status: 200, body: Data(body.utf8)))

        do {
            _ = try await agent.deploy.desired()
            XCTFail("expected verification error")
        } catch let DepliteError.verification(reason) {
            XCTAssertTrue(reason.contains("my-app"), reason)
        }
    }

    func testDeployReportSendsCamelCaseBodyAndOmitsAbsentOptionals() async throws {
        MockURLProtocol.enqueue(.json(200, ["ok": true]))
        let (agent, _) = try makeAgent()
        try await agent.deploy.report(DeviceReportInput(
            applicationId: "app-1",
            currentVersion: "1.0.0",
            state: .idle
        ))
        let req = MockURLProtocol.captured.first!
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.absoluteString, "https://api.test.example/v1/agent/deploy/report")
        XCTAssertNotNil(req.headers["x-signature"])
        let json = try JSONSerialization.jsonObject(with: req.body) as! [String: Any]
        XCTAssertEqual(json["applicationId"] as? String, "app-1")
        XCTAssertEqual(json["currentVersion"] as? String, "1.0.0")
        XCTAssertEqual(json["state"] as? String, "idle")
        XCTAssertEqual(json.count, 3)
    }
}
