import Foundation

/// Reads Moonshot Kimi usage from
/// `~/.kimi-code/sessions/**/agents/**/wire.jsonl`. Per-turn usage lands on
/// `usage.record` lines scoped to `"turn"`.
final class KimiScanner: AgentScanner {
    let kind: AgentKind = .kimi

    private static let needle = Data("usage.record".utf8)

    private let cache = JSONLScanCache<[UsageRecord]>(
        initial: { [] },
        lineFilter: { $0.range(of: KimiScanner.needle) != nil },
        reduce: { records, obj, url in
            guard obj.str("type") == "usage.record",
                  obj.str("usageScope") == "turn",
                  let usage = obj.dict("usage") else { return }
            let counts = TokenCounts(
                input: usage.int("inputOther"),
                output: usage.int("output"),
                cacheRead: usage.int("inputCacheRead"),
                cacheWrite: usage.int("inputCacheCreation"),
                reasoning: 0
            )
            guard counts.total > 0 else { return }
            let model = obj.str("model") ?? "kimi"
            let date = DateParse.epoch(Int64(obj.int("time")))
            records.append(UsageRecord(kind: .kimi, date: date, model: model,
                                       sessionId: KimiScanner.sessionId(from: url),
                                       counts: counts, realCost: nil))
        },
        finalize: { records, _ in records }
    )

    private var root: URL { home.appendingPathComponent(".kimi-code/sessions") }

    func scan() -> ScanResult {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ScanResult(kind: kind, installed: false, records: [], note: nil)
        }
        let files = ScanHelp.files(under: root) { $0 == "wire.jsonl" }
        cache.prune(keeping: Set(files.map(\.path)))
        let records = ScanHelp.parallelMap(files) { self.cache.records(for: $0) }
            .flatMap { $0 }
        return ScanResult(kind: kind, installed: true, records: records, note: nil)
    }

    /// .../sessions/<wd>/<session_xxx>/agents/main/wire.jsonl → the session id
    /// is the second path component above "agents".
    private static func sessionId(from url: URL) -> String {
        let parts = url.pathComponents
        if let agentsIdx = parts.firstIndex(of: "agents"), agentsIdx > 0 {
            return parts[agentsIdx - 1]
        }
        return url.deletingLastPathComponent().lastPathComponent
    }
}
