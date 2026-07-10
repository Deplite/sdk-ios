import XCTest
import Deplite

/// Full-flow tests against a local HTTP server using only the public API.
/// The server verifies every ed25519 request signature; any signing mismatch
/// surfaces as a 401 and fails the test.
final class EndToEndTests: XCTestCase {
    private func registeredAgent(on server: TestDepliteServer, session: URLSession) async throws -> DepliteAgent {
        let registration = try await Deplite.register(
            installCode: TestDepliteServer.installCode,
            name: "e2e-device",
            hostname: "e2e-host",
            os: "macos",
            agentVersion: "0.1.0",
            baseURL: server.baseURL,
            session: session
        )
        XCTAssertEqual(registration.identity.agentId, TestDepliteServer.agentId)
        XCTAssertEqual(registration.identity.organizationId, TestDepliteServer.organizationId)
        XCTAssertEqual(registration.identity.serverPublicKeyPEM, server.serverPublicKeyPEM)
        XCTAssertEqual(registration.privateKey.count, 32)
        return try DepliteAgent(identity: registration.identity, privateKey: registration.privateKey, session: session)
    }

    func testRegisterThenSignedCallsVerifyOnServer() async throws {
        let server = try TestDepliteServer()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)

        let agent = try await registeredAgent(on: server, session: session)
        XCTAssertEqual(server.enrollRequestBody["name"] as? String, "e2e-device")
        XCTAssertEqual(server.enrollRequestBody["hostname"] as? String, "e2e-host")
        XCTAssertNotNil(server.enrollRequestBody["publicKey"] as? String)

        try await agent.heartbeat()
        try await agent.updateIdentity(hostname: "e2e-host-2")
        let count = try await agent.workflows.report([WorkflowReport(name: "ota-update", version: "1.0.0")])
        XCTAssertEqual(count, 1)

        let accepted = try await agent.jobs.appendLogs(jobId: "job-e2e-1", items: [
            LogItem(seq: 1, stream: .raw, content: "downloading package"),
            LogItem(seq: 2, stream: .system, content: "package applied", level: .info),
        ])
        XCTAssertEqual(accepted, 2)
        try await agent.jobs.reportResult(jobId: "job-e2e-1", result: .success(exitCode: 0))
        XCTAssertEqual(server.jobResultBody["status"] as? String, "success")
        XCTAssertEqual(server.jobResultBody["exitCode"] as? Int, 0)

        XCTAssertEqual(server.verifiedCalls, [
            "POST /agent/heartbeat",
            "PATCH /agent/identity",
            "POST /agent/workflows/report",
            "POST /agent/jobs/job-e2e-1/logs",
            "POST /agent/jobs/job-e2e-1/result",
        ])
    }

    private static let manifestPayload = #"{"application_id":"app-e2e","channel":"stable","current":{"release_id":"r-1","sequence":10,"version":"1.0.0"},"desired":{"channel":"stable","checksum_sha256":"0f1e2d","download_expires_in":3600,"download_url":"https://cdn.example.com/pkg?sig=a\u0026exp=b","release_id":"r-2","sequence":11,"size":5000000000,"version":"1.1.0","workflow_name":"ota-update"},"forced":false,"issued_at":1751970000,"min_sequence":5,"min_version":"1.0.0","nonce":"mn-1","slug":"kiosk-app","update_workflow":"ota-update"}"#

    func testDeployDesiredAndReportRoundTrip() async throws {
        let server = try TestDepliteServer()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        let agent = try await registeredAgent(on: server, session: session)

        let signature = server.signCanonical(Self.manifestPayload)
        server.desiredResponseBody = #"{"apps":[{"payload":\#(Self.manifestPayload),"signature":"\#(signature)"}]}"#

        let apps = try await agent.deploy.desired()
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].applicationId, "app-e2e")
        XCTAssertEqual(apps[0].slug, "kiosk-app")
        XCTAssertEqual(apps[0].current?.sequence, 10)
        XCTAssertEqual(apps[0].desired?.sequence, 11)
        XCTAssertEqual(apps[0].desired?.size, 5_000_000_000)
        XCTAssertEqual(apps[0].desired?.downloadUrl, "https://cdn.example.com/pkg?sig=a&exp=b")
        XCTAssertEqual(apps[0].desired?.workflowName, "ota-update")

        try await agent.deploy.report(DeviceReportInput(
            applicationId: "app-e2e",
            currentVersion: "1.1.0",
            currentReleaseId: "r-2",
            currentSequence: 11,
            state: .idle
        ))
        XCTAssertEqual(server.deployReportBody["applicationId"] as? String, "app-e2e")
        XCTAssertEqual(server.deployReportBody["currentSequence"] as? Int, 11)
        XCTAssertEqual(server.deployReportBody["state"] as? String, "idle")

        let tampered = Self.manifestPayload.replacingOccurrences(of: "kiosk-app", with: "evil-app")
        server.desiredResponseBody = #"{"apps":[{"payload":\#(tampered),"signature":"\#(signature)"}]}"#
        do {
            _ = try await agent.deploy.desired()
            XCTFail("expected verification error")
        } catch let DepliteError.verification(reason) {
            XCTAssertTrue(reason.contains("evil-app"), reason)
        }
    }

    func testEventStreamDeliversVerifiedDeployAndDropsTampered() async throws {
        let server = try TestDepliteServer()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        let agent = try await registeredAgent(on: server, session: session)

        let payload = #"{"debug":false,"force":false,"issued_at":1751970000,"job_id":"job-e2e-9","nonce":"dn-1","params":{"ref":"main"},"workflow_name":"ota-update"}"#
        let signature = server.signCanonical(payload)
        let tampered = payload.replacingOccurrences(of: "job-e2e-9", with: "job-evil")
        server.sseFrames = [
            "event: ping\ndata: {}\n\n",
            "event: deploy\ndata: {\"payload\":\(tampered),\"signature\":\"\(signature)\"}\n\n",
            "event: deploy\ndata: {\"payload\":\(payload),\"signature\":\"\(signature)\"}\n\n",
            "event: cancel\ndata: {\"job_id\":\"job-e2e-9\",\"reason\":\"superseded by release 1.2.0\",\"superseded\":true}\n\n",
        ]

        var received: [String] = []
        var deploy: DeployPayload?
        do {
            for try await event in agent.events() {
                switch event {
                case .ping:
                    received.append("ping")
                case .deploy(let p, _):
                    received.append("deploy")
                    deploy = p
                case .cancel(let jobId, let reason, let superseded, _):
                    received.append("cancel")
                    XCTAssertEqual(jobId, "job-e2e-9")
                    XCTAssertEqual(reason, "superseded by release 1.2.0")
                    XCTAssertTrue(superseded)
                case .unknown(let name, _):
                    received.append("unknown:\(name)")
                default:
                    received.append("other")
                }
                if received.count == 4 { break }
            }
        } catch {
            // connection close after the last frame is fine; assertions below decide
        }

        XCTAssertEqual(received, ["ping", "unknown:deploy", "deploy", "cancel"])
        XCTAssertEqual(deploy?.jobId, "job-e2e-9")
        XCTAssertEqual(deploy?.workflowName, "ota-update")
        XCTAssertEqual(deploy?.issuedAt, 1751970000)
        XCTAssertEqual(deploy?.params, ["ref": "main"])
    }

    func testRegisterWithWrongInstallCodeIsUnauthorized() async throws {
        let server = try TestDepliteServer()
        defer { server.stop() }
        do {
            _ = try await Deplite.register(
                installCode: "wrong-code",
                name: "e2e-device",
                baseURL: server.baseURL,
                session: URLSession(configuration: .ephemeral)
            )
            XCTFail("expected unauthorized")
        } catch let DepliteError.unauthorized(statusCode, _) {
            XCTAssertEqual(statusCode, 401)
        }
    }

    func testSignatureFromWrongKeyIsRejectedByVerifier() async throws {
        let server = try TestDepliteServer()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        let agent = try await registeredAgent(on: server, session: session)

        let wrongSeed = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let impostor = try DepliteAgent(identity: agent.identity, privateKey: wrongSeed, session: session)
        do {
            try await impostor.heartbeat()
            XCTFail("expected unauthorized")
        } catch let DepliteError.unauthorized(statusCode, _) {
            XCTAssertEqual(statusCode, 401)
        }
        XCTAssertTrue(server.verifiedCalls.isEmpty)
    }

    func testUnreachableServerMapsToTransportError() async throws {
        let server = try TestDepliteServer()
        let baseURL = server.baseURL
        server.stop()
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await Deplite.register(
                installCode: TestDepliteServer.installCode,
                name: "e2e-device",
                baseURL: baseURL,
                session: URLSession(configuration: .ephemeral)
            )
            XCTFail("expected transport error")
        } catch DepliteError.transport {
        }
    }
}
