import XCTest
@testable import Deplite

final class ErrorMappingTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    private func makeDeplite() -> Deplite {
        Deplite(
            apiToken: "dpl_test",
            baseURL: URL(string: "https://api.test.example/v1")!,
            session: MockURLProtocol.session()
        )
    }

    func testForbiddenMapsToUnauthorized() async throws {
        MockURLProtocol.enqueue(.init(status: 403, body: Data("denied".utf8)))
        do {
            _ = try await makeDeplite().agents.list()
            XCTFail("expected throw")
        } catch DepliteError.unauthorized(let code, let body) {
            XCTAssertEqual(code, 403)
            XCTAssertEqual(body, "denied")
        }
    }

    func testMalformedJSONMapsToDecodingErrorWithRawBody() async throws {
        MockURLProtocol.enqueue(.init(status: 200, body: Data("not json".utf8)))
        do {
            _ = try await makeDeplite().token.info()
            XCTFail("expected throw")
        } catch DepliteError.decoding(_, let body) {
            XCTAssertEqual(body, "not json")
        }
    }

    func testEmptyBodyForTypedResponseMapsToDecodingError() async throws {
        MockURLProtocol.enqueue(.init(status: 200))
        do {
            _ = try await makeDeplite().triggers.run(triggerId: "t")
            XCTFail("expected throw")
        } catch DepliteError.decoding(_, let body) {
            XCTAssertEqual(body, "")
        }
    }

    func testEmptyBodySucceedsOnVoidEndpoint() async throws {
        MockURLProtocol.enqueue(.init(status: 204))
        let key = Ed25519Key.generate()
        let identity = AgentIdentity(
            agentId: "agent-1",
            organizationId: "org-1",
            baseURL: URL(string: "https://api.test.example/v1")!,
            serverPublicKeyPEM: key.publicKeyPEM()
        )
        let agent = try DepliteAgent(identity: identity, privateKey: key.rawSeed, session: MockURLProtocol.session())
        try await agent.heartbeat()
    }
}
