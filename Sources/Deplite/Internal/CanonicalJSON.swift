import Foundation

/// JSON tree that preserves numeric tokens verbatim.
internal indirect enum CanonicalNode {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([CanonicalNode])
    case object([(String, CanonicalNode)])
}

internal enum CanonicalJSON {
    static func parse(_ input: String) throws -> CanonicalNode {
        var parser = Parser(scalars: Array(input.unicodeScalars))
        parser.skipWhitespace()
        let node = try parser.parseValue()
        parser.skipWhitespace()
        if !parser.isAtEnd {
            throw ParseError.trailing
        }
        return node
    }

    static func encode(_ node: CanonicalNode) -> String {
        var out = ""
        write(&out, node)
        return out
    }

    /// Re-emit as standard JSON (numbers kept verbatim) for `JSONDecoder` consumption.
    static func toJSONData(_ node: CanonicalNode) -> Data {
        var out = ""
        write(&out, node)
        return Data(out.utf8)
    }

    /// Rename known snake_case keys at the top level of an object node.
    static func translateDeployKeys(_ node: CanonicalNode) -> CanonicalNode {
        guard case .object(let pairs) = node else { return node }
        let mapped: [(String, CanonicalNode)] = pairs.map { (k, v) in
            let nk: String
            switch k {
            case "job_id": nk = "jobId"
            case "workflow_name": nk = "workflowName"
            case "issued_at": nk = "issuedAt"
            case "force_reason": nk = "forceReason"
            default: nk = k
            }
            return (nk, v)
        }
        return .object(mapped)
    }

    private static func write(_ out: inout String, _ node: CanonicalNode) {
        switch node {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let s): out += s
        case .string(let s): writeString(&out, s)
        case .array(let items):
            out += "["
            for (i, v) in items.enumerated() {
                if i > 0 { out += "," }
                write(&out, v)
            }
            out += "]"
        case .object(let entries):
            out += "{"
            let sorted = entries.sorted { $0.0 < $1.0 }
            for (i, kv) in sorted.enumerated() {
                if i > 0 { out += "," }
                writeString(&out, kv.0)
                out += ":"
                write(&out, kv.1)
            }
            out += "}"
        }
    }

    private static func writeString(_ out: inout String, _ s: String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    enum ParseError: Error {
        case unexpectedEnd
        case unexpected(Unicode.Scalar)
        case invalidNumber
        case invalidEscape
        case trailing
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index: Int = 0

        var isAtEnd: Bool { index >= scalars.count }
        var peek: Unicode.Scalar? { isAtEnd ? nil : scalars[index] }

        mutating func skipWhitespace() {
            while index < scalars.count {
                let c = scalars[index]
                if c == " " || c == "\n" || c == "\r" || c == "\t" { index += 1 } else { break }
            }
        }

        mutating func parseValue() throws -> CanonicalNode {
            skipWhitespace()
            guard let c = peek else { throw ParseError.unexpectedEnd }
            switch c {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t", "f": return .bool(try parseBool())
            case "n": try expect("null"); return .null
            case "-", "0"..."9": return .number(try parseNumber())
            default: throw ParseError.unexpected(c)
            }
        }

        mutating func parseObject() throws -> CanonicalNode {
            index += 1
            var pairs: [(String, CanonicalNode)] = []
            skipWhitespace()
            if peek == "}" { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                guard peek == ":" else { throw ParseError.unexpected(peek ?? "?") }
                index += 1
                let value = try parseValue()
                pairs.append((key, value))
                skipWhitespace()
                if peek == "," { index += 1; continue }
                if peek == "}" { index += 1; return .object(pairs) }
                throw ParseError.unexpected(peek ?? "?")
            }
        }

        mutating func parseArray() throws -> CanonicalNode {
            index += 1
            var items: [CanonicalNode] = []
            skipWhitespace()
            if peek == "]" { index += 1; return .array(items) }
            while true {
                let v = try parseValue()
                items.append(v)
                skipWhitespace()
                if peek == "," { index += 1; continue }
                if peek == "]" { index += 1; return .array(items) }
                throw ParseError.unexpected(peek ?? "?")
            }
        }

        mutating func parseString() throws -> String {
            guard peek == "\"" else { throw ParseError.unexpected(peek ?? "?") }
            index += 1
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]
                if c == "\"" { index += 1; return String(out) }
                if c == "\\" {
                    index += 1
                    guard index < scalars.count else { throw ParseError.unexpectedEnd }
                    let esc = scalars[index]
                    index += 1
                    switch esc {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "b": out.append(Unicode.Scalar(0x08)!)
                    case "f": out.append(Unicode.Scalar(0x0C)!)
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u":
                        guard index + 4 <= scalars.count else { throw ParseError.unexpectedEnd }
                        let hex = String(String.UnicodeScalarView(scalars[index..<index+4]))
                        index += 4
                        guard let code = UInt32(hex, radix: 16) else { throw ParseError.invalidEscape }
                        if (0xD800...0xDBFF).contains(code) {
                            guard index + 6 <= scalars.count,
                                  scalars[index] == "\\", scalars[index+1] == "u" else {
                                throw ParseError.invalidEscape
                            }
                            let lowHex = String(String.UnicodeScalarView(scalars[index+2..<index+6]))
                            index += 6
                            guard let low = UInt32(lowHex, radix: 16), (0xDC00...0xDFFF).contains(low) else {
                                throw ParseError.invalidEscape
                            }
                            let combined = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            guard let s = Unicode.Scalar(combined) else { throw ParseError.invalidEscape }
                            out.append(s)
                        } else {
                            guard let s = Unicode.Scalar(code) else { throw ParseError.invalidEscape }
                            out.append(s)
                        }
                    default: throw ParseError.invalidEscape
                    }
                } else {
                    out.append(c)
                    index += 1
                }
            }
            throw ParseError.unexpectedEnd
        }

        mutating func parseBool() throws -> Bool {
            if peek == "t" { try expect("true"); return true }
            try expect("false"); return false
        }

        mutating func parseNumber() throws -> String {
            let start = index
            if scalars[index] == "-" { index += 1 }
            while index < scalars.count {
                let c = scalars[index]
                let v = c.value
                if (v >= 0x30 && v <= 0x39) || c == "." || c == "e" || c == "E" || c == "+" || c == "-" {
                    index += 1
                } else { break }
            }
            if start == index { throw ParseError.invalidNumber }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }

        mutating func expect(_ literal: String) throws {
            for ch in literal.unicodeScalars {
                guard index < scalars.count, scalars[index] == ch else {
                    throw ParseError.unexpected(peek ?? "?")
                }
                index += 1
            }
        }
    }
}
