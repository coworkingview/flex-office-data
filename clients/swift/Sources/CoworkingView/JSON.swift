import Foundation

/// JSON value that keeps number tokens as the API wrote them (`214`, not `214.0`).
enum JSON {
    enum Value {
        case object([String: Value])
        case array([Value])
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        var object: [String: Value]? {
            if case let .object(fields) = self { return fields }
            return nil
        }

        var array: [Value]? {
            if case let .array(items) = self { return items }
            return nil
        }

        var isNull: Bool {
            if case .null = self { return true }
            return false
        }
    }

    struct ParseError: Error {}

    static func parse(_ data: Data) throws -> Value {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError()
        }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> Value {
        var parser = Parser(Array(text))
        try parser.skip()
        let value = try parser.parseValue()
        try parser.skip()
        guard parser.eof else { throw ParseError() }
        return value
    }

    private struct Parser {
        let characters: [Character]
        var index: Int = 0

        init(_ characters: [Character]) {
            self.characters = characters
        }

        var eof: Bool { index >= characters.count }

        mutating func peek() -> Character? {
            eof ? nil : characters[index]
        }

        mutating func advance() -> Character? {
            guard !eof else { return nil }
            let character = characters[index]
            index += 1
            return character
        }

        mutating func skip() throws {
            while let character = peek(), character == " " || character == "\n" || character == "\r" || character == "\t" {
                index += 1
            }
        }

        mutating func expect(_ character: Character) throws {
            guard advance() == character else { throw ParseError() }
        }

        mutating func parseValue() throws -> Value {
            guard let character = peek() else { throw ParseError() }
            switch character {
            case "{":
                return try parseObject()
            case "[":
                return try parseArray()
            case "\"":
                return .string(try parseString())
            case "t":
                try expectLiteral("true")
                return .bool(true)
            case "f":
                try expectLiteral("false")
                return .bool(false)
            case "n":
                try expectLiteral("null")
                return .null
            default:
                return .number(try parseNumber())
            }
        }

        mutating func parseObject() throws -> Value {
            try expect("{")
            try skip()
            var fields: [String: Value] = [:]
            if peek() == "}" {
                index += 1
                return .object(fields)
            }
            while true {
                guard peek() == "\"" else { throw ParseError() }
                let key = try parseString()
                try skip()
                try expect(":")
                try skip()
                fields[key] = try parseValue()
                try skip()
                if peek() == "," {
                    index += 1
                    try skip()
                    continue
                }
                try expect("}")
                return .object(fields)
            }
        }

        mutating func parseArray() throws -> Value {
            try expect("[")
            try skip()
            var items: [Value] = []
            if peek() == "]" {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try parseValue())
                try skip()
                if peek() == "," {
                    index += 1
                    try skip()
                    continue
                }
                try expect("]")
                return .array(items)
            }
        }

        mutating func parseString() throws -> String {
            try expect("\"")
            var result = ""
            while let character = advance() {
                if character == "\"" { return result }
                if character == "\\" {
                    guard let escaped = advance() else { throw ParseError() }
                    switch escaped {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append("\u{0008}")
                    case "f": result.append("\u{000c}")
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u": result.append(try parseUnicodeEscape())
                    default: throw ParseError()
                    }
                } else {
                    result.append(character)
                }
            }
            throw ParseError()
        }

        mutating func parseUnicodeEscape() throws -> Character {
            let unit = try parseHex4()
            if (0xD800...0xDBFF).contains(unit), peek() == "\\" {
                let saved = index
                index += 1
                if peek() == "u" {
                    index += 1
                    let low = try parseHex4()
                    if (0xDC00...0xDFFF).contains(low) {
                        let scalar = UInt32(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
                        if let unicode = UnicodeScalar(scalar) {
                            return Character(unicode)
                        }
                    }
                }
                index = saved
            }
            guard let unicode = UnicodeScalar(unit) else { throw ParseError() }
            return Character(unicode)
        }

        mutating func parseHex4() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let character = advance() else { throw ParseError() }
                guard let digit = character.hexDigitValue else { throw ParseError() }
                value = value << 4 | UInt32(digit)
            }
            return value
        }

        mutating func parseNumber() throws -> String {
            let start = index
            if peek() == "-" { index += 1 }
            guard let first = peek(), first.isNumber else { throw ParseError() }
            if first == "0" {
                index += 1
            } else {
                while let character = peek(), character.isNumber { index += 1 }
            }
            if peek() == "." {
                index += 1
                guard let character = peek(), character.isNumber else { throw ParseError() }
                while let character = peek(), character.isNumber { index += 1 }
            }
            if peek() == "e" || peek() == "E" {
                index += 1
                if peek() == "+" || peek() == "-" { index += 1 }
                guard let character = peek(), character.isNumber else { throw ParseError() }
                while let character = peek(), character.isNumber { index += 1 }
            }
            guard index > start else { throw ParseError() }
            return String(characters[start..<index])
        }

        mutating func expectLiteral(_ literal: String) throws {
            for character in literal {
                guard advance() == character else { throw ParseError() }
            }
        }
    }
}

enum JSONRead {
    static func string(_ value: JSON.Value?) -> String? {
        if case let .string(text) = value { return text }
        return nil
    }

    static func bool(_ value: JSON.Value?) -> Bool? {
        if case let .bool(flag) = value { return flag }
        return nil
    }

    static func numberToken(_ value: JSON.Value?) -> String? {
        if case let .number(token) = value { return token }
        return nil
    }

    static func integer(_ value: JSON.Value?) -> Int? {
        guard let token = numberToken(value), isIntegerToken(token) else { return nil }
        return Int(token)
    }

    static func isIntegerToken(_ token: String) -> Bool {
        var digits = token
        if digits.first == "-" { digits.removeFirst() }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
        return true
    }

    static func double(token: String) -> Double? {
        Double(token)
    }

    static func field(_ object: JSON.Value?, _ key: String) -> JSON.Value? {
        object?.object?[key]
    }

    static func nestedString(_ value: JSON.Value?, _ key: String) -> String? {
        string(field(value, key))
    }
}
