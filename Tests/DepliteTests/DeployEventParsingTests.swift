import XCTest
@testable import Deplite

final class DeployEventParsingTests: XCTestCase {
    private func makeEnvelope(payload: String, key: Ed25519Key) throws -> String {
        let node = try CanonicalJSON.parse(payload)
        let canonical = CanonicalJSON.encode(node)
        let sig = try key.sign(Data(canonical.utf8)).base64EncodedString()
        return "{\"payload\":\(payload),\"signature\":\"\(sig)\"}"
    }

    func testValidSignature() throws {
        let key = Ed25519Key.generate()
        let payload = #"{"job_id":"j1","workflow_name":"wf","issued_at":1700000000}"#
        let env = try makeEnvelope(payload: payload, key: key)
        let ev = parseAgentEvent(name: "deploy", data: env, serverPublicKeyPEM: key.publicKeyPEM())
        guard case .deploy(let p, _) = ev else { return XCTFail("expected deploy, got \(ev)") }
        XCTAssertEqual(p.jobId, "j1")
        XCTAssertEqual(p.workflowName, "wf")
        XCTAssertEqual(p.issuedAt, 1700000000)
    }

    func testTamperedSignature() throws {
        let key = Ed25519Key.generate()
        let payload = #"{"job_id":"j1","workflow_name":"wf"}"#
        var env = try makeEnvelope(payload: payload, key: key)
        // Mutate the payload after signing.
        env = env.replacingOccurrences(of: "\"j1\"", with: "\"j2\"")
        let ev = parseAgentEvent(name: "deploy", data: env, serverPublicKeyPEM: key.publicKeyPEM())
        guard case .unknown = ev else { return XCTFail("expected unknown") }
    }

    func testBrokenEnvelope() {
        let ev = parseAgentEvent(name: "deploy", data: "{not json", serverPublicKeyPEM: "")
        guard case .unknown = ev else { return XCTFail("expected unknown") }
    }

    func testKnownEvents() {
        XCTAssertEqual(label(parseAgentEvent(name: "revoke", data: "", serverPublicKeyPEM: "")), "revoke")
        XCTAssertEqual(label(parseAgentEvent(name: "ping", data: "", serverPublicKeyPEM: "")), "ping")
        XCTAssertEqual(label(parseAgentEvent(name: "sync_workflows", data: "", serverPublicKeyPEM: "")), "syncWorkflows")
        XCTAssertEqual(label(parseAgentEvent(name: "workflows-refresh", data: "", serverPublicKeyPEM: "")), "syncWorkflows")
    }

    func testUnknownEvent() {
        let ev = parseAgentEvent(name: "wat", data: "x", serverPublicKeyPEM: "")
        if case .unknown(let n, let d) = ev {
            XCTAssertEqual(n, "wat"); XCTAssertEqual(d, "x")
        } else { XCTFail("expected unknown") }
    }

    private func label(_ ev: AgentEvent) -> String {
        switch ev {
        case .deploy: return "deploy"
        case .revoke: return "revoke"
        case .syncWorkflows: return "syncWorkflows"
        case .ping: return "ping"
        case .unknown: return "unknown"
        }
    }
}
