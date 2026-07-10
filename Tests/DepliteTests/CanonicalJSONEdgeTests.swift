import XCTest
import CryptoKit
@testable import Deplite

final class CanonicalJSONEdgeTests: XCTestCase {
    func testNumberTokensRoundTripVerbatim() throws {
        // Go signs numeric tokens as emitted; routing them through Double would corrupt them.
        let input = #"{"big":9007199254740993,"neg":-0.0,"sci":1e6,"trail":1.50}"#
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(CanonicalJSON.encode(node), input)
    }

    func testSurrogatePairEscapeDecodesToScalar() throws {
        let node = try CanonicalJSON.parse("{\"s\":\"\\ud83d\\ude00\"}")
        XCTAssertEqual(CanonicalJSON.encode(node), "{\"s\":\"😀\"}")
    }

    func testForwardSlashEscapeNormalizes() throws {
        let node = try CanonicalJSON.parse("{\"s\":\"a\\/b\"}")
        XCTAssertEqual(CanonicalJSON.encode(node), "{\"s\":\"a/b\"}")
    }

    func testControlCharacterEscapesReEmitAsLowercaseHex() throws {
        let node = try CanonicalJSON.parse("{\"s\":\"\\u0001\\u001F\"}")
        XCTAssertEqual(CanonicalJSON.encode(node), "{\"s\":\"\\u0001\\u001f\"}")
    }

    func testLoneHighSurrogateEscapeFails() {
        XCTAssertThrowsError(try CanonicalJSON.parse("{\"s\":\"\\ud83d\"}"))
    }

    func testInvalidEscapeFails() {
        XCTAssertThrowsError(try CanonicalJSON.parse("{\"s\":\"\\q\"}"))
    }

    func testUnterminatedStringFails() {
        XCTAssertThrowsError(try CanonicalJSON.parse("{\"s\":\"abc"))
    }

    func testTrailingGarbageFails() {
        XCTAssertThrowsError(try CanonicalJSON.parse("{} x"))
    }

    func testEmptyBodyHashConstantMatchesSHA256OfEmptyData() {
        let computed = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(CanonicalMessage.emptyBodySHA256Hex, computed)
    }
}
