import Foundation

enum Check {
    static let locales = ["en", "es", "de"]
    static let currencies = ["EUR", "GBP", "USD", "CHF", "AED", "VES"]
    static let products = [
        "flex_desk",
        "fix_desk",
        "private_office",
        "exclusive_bereich",
        "day_pass",
        "meeting_room",
        "event_space",
        "virtual_office",
        "membership",
    ]
    static let sorts = ["random", "price-asc", "date-desc", "date-asc"]
    static let maxSpaces = 200

    static func locale(_ value: String) throws -> String {
        try oneOf("locale", value, locales)
    }

    static func currency(_ value: String?) throws -> String? {
        guard let value else { return nil }
        return try oneOf("currency", value.uppercased(), currencies)
    }

    static func product(_ value: String?) throws -> String? {
        guard let value else { return nil }
        return try oneOf("product", value, products)
    }

    static func sort(_ value: String) throws -> String {
        try oneOf("sort", value, sorts)
    }

    static func text(_ name: String, _ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CoworkingViewError("\(name) must be a non-empty string, got '\(value)'.")
        }
        return trimmed
    }

    static func limit(_ value: Int) throws -> Int {
        if value < 1 {
            throw CoworkingViewError("limit must be a positive integer, got \(value).")
        }
        if value > maxSpaces {
            throw CoworkingViewError(
                "limit=\(value) exceeds the maximum of \(maxSpaces). The catalogue may be "
                    + "searched and linked to, not bulk-copied: its content belongs to the operators "
                    + "and the API's catalogue notice forbids systematic extraction. Narrow the "
                    + "search (city, zone, operator, product, price) instead."
            )
        }
        return value
    }

    static func count(_ name: String, _ value: Int?) throws -> Int? {
        guard let value else { return nil }
        if value < 0 {
            throw CoworkingViewError("\(name) must be a non-negative integer, got \(value).")
        }
        return value
    }

    static func price(_ name: String, _ value: Double?) throws -> Double? {
        guard let value else { return nil }
        if value.isNaN || value.isInfinite || value < 0 {
            throw CoworkingViewError("\(name) must be a non-negative number, got \(value).")
        }
        return value
    }

    static func priceRange(minPrice: Double?, maxPrice: Double?) throws {
        if let minPrice, let maxPrice, minPrice > maxPrice {
            throw CoworkingViewError(
                "min_price (\(decimal(minPrice))) is greater than max_price (\(decimal(maxPrice)))."
            )
        }
    }

    static func slug(_ value: String) throws -> String {
        let scalars = Array(value)
        let ok = !scalars.isEmpty && isSlugCharacter(scalars[0], first: true) && scalars.dropFirst().allSatisfy {
            isSlugCharacter($0, first: false)
        }
        if !ok {
            throw CoworkingViewError(
                "slug='\(value)' is not a valid slug; slugs are letters, digits, '.', '_' "
                    + "and '-', starting with a letter or digit (e.g. 'sankt-oberholz-rosenthaler-berlin')."
            )
        }
        return value
    }

    static func decimal(_ value: Double) -> String {
        if value.rounded() == value, !value.isInfinite, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    static func timeout(_ value: TimeInterval) throws -> TimeInterval {
        if value.isNaN || value.isInfinite || value <= 0 {
            throw CoworkingViewError("timeout must be a positive number of seconds, got \(value).")
        }
        return value
    }

    private static func oneOf(_ name: String, _ value: String, _ valid: [String]) throws -> String {
        if valid.contains(value) { return value }
        let choices = valid.map { "'\($0)'" }.joined(separator: ", ")
        throw CoworkingViewError("\(name)='\(value)' is not supported; use one of \(choices).")
    }

    private static func isSlugCharacter(_ character: Character, first: Bool) -> Bool {
        guard character.isASCII else { return false }
        if character.isLetter || character.isNumber { return true }
        if first { return false }
        return character == "." || character == "_" || character == "-"
    }
}
