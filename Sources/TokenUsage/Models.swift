import SwiftUI

/// The coding agents whose local token usage TokenUsage can read.
enum AgentKind: String, CaseIterable, Identifiable {
    case claude
    case codex
    case antigravity
    case kimi
    case minimax
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .kimi: return "Kimi"
        case .minimax: return "MiniMax"
        case .opencode: return "opencode"
        }
    }

    /// The vendor behind the agent, shown as a subtitle.
    var vendor: String {
        switch self {
        case .claude: return "Anthropic"
        case .codex: return "OpenAI"
        case .antigravity: return "Google · Gemini"
        case .kimi: return "Moonshot"
        case .minimax: return "MiniMax"
        case .opencode: return "SST"
        }
    }

    /// Short monogram rendered in the colored badge next to each agent.
    var monogram: String {
        switch self {
        case .claude: return "C"
        case .codex: return "Cx"
        case .antigravity: return "Ag"
        case .kimi: return "K"
        case .minimax: return "M"
        case .opencode: return "oc"
        }
    }

    /// Brand-ish accent color for the agent.
    var tint: Color {
        switch self {
        case .claude: return Color(hex: 0xD97757)      // Anthropic terracotta
        case .codex: return Color(hex: 0x10A37F)       // OpenAI green
        case .antigravity: return Color(hex: 0x4285F4) // Google blue
        case .kimi: return Color(hex: 0x6D5EF6)        // Moonshot violet
        case .minimax: return Color(hex: 0xE8452B)     // MiniMax red
        case .opencode: return Color(hex: 0xF6A623)    // opencode amber
        }
    }

    /// Preferred display order in the list.
    static let ordered: [AgentKind] = [.claude, .codex, .antigravity, .kimi, .minimax, .opencode]
}

/// A breakdown of token counts. `reasoning` is a subset of `output` and is kept
/// for display only — it is intentionally excluded from `total`.
struct TokenCounts: Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    mutating func add(_ other: TokenCounts) { self = self + other }
}

/// A single usage data point emitted by a scanner: one turn, message, or session
/// depending on what the underlying store records at.
struct UsageRecord {
    let kind: AgentKind
    let date: Date
    let model: String
    let sessionId: String
    var counts: TokenCounts
    /// Cost reported directly by the source (opencode, MiniMax). `nil` means the
    /// cost must be estimated from the pricing table.
    var realCost: Double?
    /// A stable id used to drop duplicates that appear across files (Claude copies
    /// a message into every session file that resumes from it). `nil` = keep as-is.
    var dedupID: String? = nil
}

/// The time window the user is looking at.
enum TimeRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"
    case all = "All"

    var id: String { rawValue }

    /// The earliest date included in this range, or `nil` for all-time.
    func start(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .day, value: -30, to: now)
        case .all: return nil
        }
    }

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        guard let start = start(now: now) else { return true }
        return date >= start
    }
}

/// Aggregated usage for a single model within one agent.
struct ModelAggregate: Identifiable {
    let model: String
    var counts: TokenCounts
    var cost: Double
    var sessionCount: Int
    var lastActivity: Date?

    var id: String { model }

    /// Strips a leading `provider/` so long ids read cleanly
    /// (`minimax/MiniMax-M3` → `MiniMax-M3`).
    var displayName: String {
        if let slash = model.lastIndex(of: "/") {
            return String(model[model.index(after: slash)...])
        }
        return model
    }
}

/// Aggregated usage for one agent over the selected range, ready to render.
struct AgentAggregate: Identifiable {
    let kind: AgentKind
    var counts: TokenCounts
    var cost: Double
    var sessionCount: Int
    var lastActivity: Date?
    /// Per-model breakdown within this agent, sorted by usage (largest first).
    var models: [ModelAggregate]
    /// Whether the agent's data directory exists on disk at all.
    var installed: Bool
    /// Set when the agent is installed but usage can't be read (e.g. Antigravity).
    var note: String?

    var id: AgentKind { kind }
    var hasUsage: Bool { counts.total > 0 }
}
