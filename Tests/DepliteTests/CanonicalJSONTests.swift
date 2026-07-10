import XCTest
@testable import Deplite

final class CanonicalJSONTests: XCTestCase {
    func testSortKeys() throws {
        let input = #"{"b": 1, "a": 2}"#
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(CanonicalJSON.encode(node), #"{"a":2,"b":1}"#)
    }

    func testNestedAndArrays() throws {
        let input = #"{"z":[3,2,1],"a":{"y":"v","x":null}}"#
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(CanonicalJSON.encode(node), #"{"a":{"x":null,"y":"v"},"z":[3,2,1]}"#)
    }

    func testWhitespaceStripped() throws {
        let input = "{  \"a\" : 1 ,  \"b\" :  [ 1 , 2 ]  }"
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(CanonicalJSON.encode(node), #"{"a":1,"b":[1,2]}"#)
    }

    func testEscapes() throws {
        let input = "{\"s\":\"a\\\"b\\\\c\\n\\t\\u0007\"}"
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(CanonicalJSON.encode(node), "{\"s\":\"a\\\"b\\\\c\\n\\t\\u0007\"}")
    }

    func testLiterals() throws {
        let input = #"{"t":true,"f":false,"n":null,"x":1.5}"#
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(CanonicalJSON.encode(node), #"{"f":false,"n":null,"t":true,"x":1.5}"#)
    }

    func testEscapesHTMLSensitiveCharactersLikeGoEncodingJSONDefaultMode() {
        XCTAssertEqual(CanonicalJSON.encode(.string("a&b")), "\"a\\u0026b\"")
        XCTAssertEqual(CanonicalJSON.encode(.string("<tag>")), "\"\\u003ctag\\u003e\"")
        XCTAssertEqual(
            CanonicalJSON.encode(.string("https://s3.example.com/x?a=1&b=2")),
            "\"https://s3.example.com/x?a=1\\u0026b=2\""
        )
    }

    func testEscapesLineSeparators() {
        XCTAssertEqual(CanonicalJSON.encode(.string("a\u{2028}b")), "\"a\\u2028b\"")
        XCTAssertEqual(CanonicalJSON.encode(.string("a\u{2029}b")), "\"a\\u2029b\"")
    }

    func testEscapesHTMLSensitiveCharactersInObjectKeysToo() {
        let node = CanonicalNode.object([("a&b", .number("1"))])
        XCTAssertEqual(CanonicalJSON.encode(node), "{\"a\\u0026b\":1}")
    }

    func testEmitsGoShortFormsForBackspaceAndFormFeed() {
        // Go encoding/json emits the short forms here, not the \u0008 / \u000c long forms.
        XCTAssertEqual(CanonicalJSON.encode(.string("\u{08}\u{0C}")), "\"\\b\\f\"")
    }

    func testCanonicalizesManifestLikePayloadWithPresignedDownloadUrl() throws {
        // Locks in the critical case: the & in the presigned URL must escape so the
        // SDK canonical bytes match the server ed25519 signature input.
        let input = #"{"slug":"my-app","desired":{"download_url":"https://s3.example.com/o?a=1&b=2&c=3","sequence":11,"size":5000000000},"issued_at":1700000000}"#
        let node = try CanonicalJSON.parse(input)
        XCTAssertEqual(
            CanonicalJSON.encode(node),
            "{\"desired\":{\"download_url\":\"https://s3.example.com/o?a=1\\u0026b=2\\u0026c=3\","
                + "\"sequence\":11,\"size\":5000000000},\"issued_at\":1700000000,\"slug\":\"my-app\"}"
        )
    }
}
