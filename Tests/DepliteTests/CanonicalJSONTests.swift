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
}
