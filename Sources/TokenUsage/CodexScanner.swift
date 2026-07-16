import Foundation

/// Reads OpenAI Codex usage from `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// Each session emits `event_msg` lines of `payload.type == "token_count"` whose
/// `info.total_token_usage` is the running cumulative total. We take the last such
/// event per file as the session's total, which avoids any double counting from
/// repeated per-turn deltas.
final class CodexScanner: AgentScanner {
    let kind: AgentKind = .codex

    /// Parse state carried across a file's lines (and across incremental scans).
    private struct State {
        var model = "unknown"
        var latestTotal: TokenCounts?
        var latestDate = Date.distantPast
    }

    // Lines worth JSON-parsing mention one of these; everything else (prompts,
    // tool output, reasoning items) is skipped at the byte level.
    private static let needles = ["token_count", "session_meta", "turn_context"]
        .map { Data($0.utf8) }

    private let cache = JSONLScanCache<State>(
        initial: { State() },
        lineFilter: { line in
            CodexScanner.needles.contains { line.range(of: $0) != nil }
        },
        reduce: { state, obj, _ in
            guard let payload = obj.dict("payload") else { return }
            switch obj.str("type") {
            case "session_meta", "turn_context":
                if let m = payload.str("model") { state.model = m }
            case "event_msg":
                guard payload.str("type") == "token_count",
                      let info = payload.dict("info"),
                      let total = info.dict("total_token_usage") else { return }
                let cached = total.int("cached_input_tokens")
                state.latestTotal = TokenCounts(
                    input: max(0, total.int("input_tokens") - cached),
                    output: total.int("output_tokens"),
                    cacheRead: cached,
                    cacheWrite: 0,
                    reasoning: total.int("reasoning_output_tokens")
                )
                if let ts = obj.str("timestamp").flatMap(DateParse.iso) {
                    state.latestDate = ts
                }
            default:
                break
            }
        },
        finalize: { state, url in
            guard let counts = state.latestTotal, counts.total > 0 else { return [] }
            let session = url.deletingPathExtension().lastPathComponent
            let date = state.latestDate == .distantPast
                ? (CodexScanner.fileDate(url) ?? .distantPast) : state.latestDate
            return [UsageRecord(kind: .codex, date: date, model: state.model,
                                sessionId: session, counts: counts, realCost: nil)]
        }
    )

    private var root: URL { home.appendingPathComponent(".codex/sessions") }

    func scan() -> ScanResult {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ScanResult(kind: kind, installed: false, records: [], note: nil)
        }
        let files = ScanHelp.files(under: root) {
            $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl")
        }
        cache.prune(keeping: Set(files.map(\.path)))
        let records = ScanHelp.parallelMap(files) { self.cache.records(for: $0) }
            .flatMap { $0 }
        return ScanResult(kind: kind, installed: true, records: records, note: nil)
    }

    private static func fileDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
