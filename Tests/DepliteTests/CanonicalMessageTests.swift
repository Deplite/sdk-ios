import XCTest
@testable import Deplite

final class CanonicalMessageTests: XCTestCase {
    func testFormat() {
        let msg = CanonicalMessage.build(timestamp: "1700000000", nonce: "abc", method: "POST", path: "/v1/x", body: Data())
        let text = String(data: msg, encoding: .utf8)!
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0], "1700000000")
        XCTAssertEqual(lines[1], "abc")
        XCTAssertEqual(lines[2], "POST")
        XCTAssertEqual(lines[3], "/v1/x")
        XCTAssertEqual(String(lines[4]), CanonicalMessage.emptyBodySHA256Hex)
    }

    func testMethodUppercase() {
        let msg = CanonicalMessage.build(timestamp: "1", nonce: "n", method: "post", path: "/a", body: Data())
        XCTAssertTrue(String(data: msg, encoding: .utf8)!.contains("\nPOST\n"))
    }

    func testBodyHash() {
        let msg = CanonicalMessage.build(timestamp: "1", nonce: "n", method: "POST", path: "/a", body: Data("hello".utf8))
        let last = String(data: msg, encoding: .utf8)!.split(separator: "\n").last!
        XCTAssertEqual(String(last), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
