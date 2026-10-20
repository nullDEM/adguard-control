import Foundation

enum Formatting {
    static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func milliseconds(seconds: Double) -> String {
        String(format: "%.0f ms", seconds * 1000)
    }

    // Tworzenie formatterów jest kosztowne, a daty parsujemy dla każdego wiersza query loga – współdzielimy instancje.
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parsuje daty ISO 8601 z i bez ułamków sekund.
    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return isoWithFraction.date(from: text) ?? isoPlain.date(from: text)
    }

    static func shortDateTime(_ text: String?) -> String {
        guard let date = parseDate(text) else { return text ?? "—" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    static func time(_ text: String?) -> String {
        guard let date = parseDate(text) else { return text ?? "—" }
        return date.formatted(date: .omitted, time: .standard)
    }

    static func duration(milliseconds: Int64) -> String {
        let seconds = Int(milliseconds / 1000)
        if seconds >= 3600 { return "\(seconds / 3600) h \((seconds % 3600) / 60) min" }
        if seconds >= 60 { return "\(seconds / 60) min \(seconds % 60) s" }
        return "\(seconds) s"
    }

    /// Dzień minionych milisekund → „HH:mm”.
    static func dayTime(milliseconds: Double) -> String {
        let minutes = Int(milliseconds / 60000)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
