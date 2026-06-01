import XCTest
@testable import Deplite

final class Ed25519KeyTests: XCTestCase {
    func testSignVerifyRoundTrip() throws {
        let key = Ed25519Key.generate()
        let msg = Data("hello world".utf8)
        let sig = try key.sign(msg)
        XCTAssertTrue(Ed25519Key.verify(pem: key.publicKeyPEM(), message: msg, signature: sig))
    }

    func testTamperFailsVerify() throws {
        let key = Ed25519Key.generate()
        let msg = Data("hello".utf8)
        var sig = try key.sign(msg)
        sig[0] ^= 0xff
        XCTAssertFalse(Ed25519Key.verify(pem: key.publicKeyPEM(), message: msg, signature: sig))
    }

    func testRawSeedRoundTrip() throws {
        let key = Ed25519Key.generate()
        let restored = try Ed25519Key.fromRawSeed(key.rawSeed)
        XCTAssertEqual(key.rawPublicKey, restored.rawPublicKey)
        let msg = Data("xyz".utf8)
        let sig = try restored.sign(msg)
        XCTAssertTrue(Ed25519Key.verify(pem: key.publicKeyPEM(), message: msg, signature: sig))
    }

    func testPEMRoundTrip() throws {
        let key = Ed25519Key.generate()
        let pem = key.publicKeyPEM()
        let raw = Ed25519Key.rawPublicKeyFromPEM(pem)
        XCTAssertEqual(raw, key.rawPublicKey)
    }

    func testInvalidPrivateKey() {
        XCTAssertThrowsError(try Ed25519Key.fromRawSeed(Data([1, 2, 3])))
    }
}
