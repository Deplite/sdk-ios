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
}
