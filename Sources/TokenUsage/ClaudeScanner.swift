import Foundation

/// Reads Claude Code usage from `~/.claude/projects/**/*.jsonl`. Each `assistant`
/// entry carries `message.usage` and `message.model`.
final class ClaudeScanner: AgentScanner {
    let kind: AgentKind = .claude

    // Any usage-bearing line contains the literal `assistant`; lines without it
    // (user turns, tool results, summaries) are skipped before JSON parsing.
    private static let needle = Data("assistant".utf8)

    private let cache = JSONLScanCache<[UsageRecord]>(
        initial: { [] },
        lineFilter: { $0.range(of: ClaudeScanner.needle) != nil },
        reduce: { records, obj, url in
            guard obj.str("type") == "assistant",
                  let message = obj.dict("message"),
                  let usage = message.dict("usage") else { return }

            let counts = TokenCounts(
                input: usage.int("input_tokens"),
                output: usage.int("output_tokens"),
                cacheRead: usage.int("cache_read_input_tokens"),
                cacheWrite: usage.int("cache_creation_input_tokens"),
                reasoning: 0
            )
            guard counts.total > 0 else { return }

            let date = obj.str("timestamp").flatMap(DateParse.iso) ?? Date.distantPast
            let model = message.str("model") ?? "unknown"
            let session = obj.str("sessionId") ?? url.deletingPathExtension().lastPathComponent
            records.append(UsageRecord(kind: .claude, date: date, model: model,
                                       sessionId: session, counts: counts, realCost: nil,
                                       dedupID: message.str("id")))
        },
        finalize: { records, _ in records }
    )

    private var root: URL { home.appendingPathComponent(".claude/projects") }

    func scan() -> ScanResult {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ScanResult(kind: kind, installed: false, records: [], note: nil)
        }

        let files = ScanHelp.files(under: root) { $0.hasSuffix(".jsonl") }
        cache.prune(keeping: Set(files.map(\.path)))
        let perFile = ScanHelp.parallelMap(files) { self.cache.records(for: $0) }

        // Deduplicate assistant messages by their id across the whole scan —
        // resumed sessions copy the same message into more than one file.
        var seen = Set<String>()
        var records: [UsageRecord] = []
        for recs in perFile {
            for rec in recs {
                if let key = rec.dedupID {
                    if seen.insert(key).inserted { records.append(rec) }
                } else {
                    records.append(rec)
                }
            }
        }
        return ScanResult(kind: kind, installed: true, records: records, note: nil)
    }
}
