import Foundation

/// Creates a formatter per operation, so parsing never mutates a shared formatter.
enum DefaultDateFormatter {
    static func make() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }

    static func decode(_ decoder: any Swift.Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let normalized = value.replacingOccurrences(of: "T", with: " ")
        let formatter = make()
        for format in [
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ",
            "yyyy-MM-dd HH:mm:ssZZZZZ"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) { return date }
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid WebSocket date")
    }
}
