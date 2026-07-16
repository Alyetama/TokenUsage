import SwiftUI

extension Color {
    /// Creates a color from a 0xRRGGBB integer literal.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

enum Fmt {
    /// Compact token count: 950 → "950", 12_300 → "12.3K", 4_500_000 → "4.5M".
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch abs(n) {
        case 1_000_000_000...:
            return trim(v / 1_000_000_000) + "B"
        case 1_000_000...:
            return trim(v / 1_000_000) + "M"
        case 1_000...:
            return trim(v / 1_000) + "K"
        default:
            return "\(n)"
        }
    }

    /// Full grouped integer: 1234567 → "1,234,567".
    static func grouped(_ n: Int) -> String {
        Self.groupedFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func cost(_ usd: Double) -> String {
        if usd <= 0 { return "$0.00" }
        if usd < 0.01 { return "<$0.01" }
        if usd < 100 { return String(format: "$%.2f", usd) }
        return "$" + (groupedFormatter.string(from: NSNumber(value: Int(usd.rounded()))) ?? "\(Int(usd))")
    }

    /// One-line token-type split: "in 1.2M · out 300K · cache r 8M · cache w 2M".
    static func breakdown(_ c: TokenCounts) -> String {
        var parts = [
            "in \(tokens(c.input))",
            "out \(tokens(c.output))",
            "cache r \(tokens(c.cacheRead))",
            "cache w \(tokens(c.cacheWrite))",
        ]
        if c.reasoning > 0 { parts.append("reasoning \(tokens(c.reasoning))") }
        return parts.joined(separator: " · ")
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func trim(_ v: Double) -> String {
        // One decimal place, but drop a trailing ".0".
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

enum DateParse {
    /// Parses an ISO-8601 timestamp, tolerating the presence or absence of
    /// fractional seconds (both appear across the agent logs).
    static func iso(_ s: String) -> Date? {
        if let d = isoFractional.date(from: s) { return d }
        return isoPlain.date(from: s)
    }

    /// Interprets an integer epoch that may be in seconds, milliseconds, or
    /// microseconds and returns a `Date`.
    static func epoch(_ value: Int64) -> Date {
        let v = Double(value)
        if value > 1_000_000_000_000_000 {      // microseconds
            return Date(timeIntervalSince1970: v / 1_000_000)
        } else if value > 1_000_000_000_000 {   // milliseconds
            return Date(timeIntervalSince1970: v / 1_000)
        } else {                                // seconds
            return Date(timeIntervalSince1970: v)
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
