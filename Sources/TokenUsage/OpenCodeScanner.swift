import Foundation

/// Reads opencode usage from `~/.local/share/opencode/opencode.db`. The `session`
/// table stores per-session token totals and a real cost.
final class OpenCodeScanner: AgentScanner {
    let kind: AgentKind = .opencode
    private let dbCache = DBResultCache()

    private var dbPath: String {
        home.appendingPathComponent(".local/share/opencode/opencode.db").path
    }

    func scan() -> ScanResult {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return ScanResult(kind: kind, installed: false, records: [], note: nil)
        }
        let records = dbCache.records(dbPath: dbPath) { load() }
        return ScanResult(kind: kind, installed: true, records: records, note: nil)
    }

    private func load() -> [UsageRecord] {
        guard let db = SQLiteDB(snapshotOf: dbPath) else { return [] }
        let rows = db.query("""
            SELECT id, model, cost, time_updated,
                   tokens_input, tokens_output, tokens_reasoning,
                   tokens_cache_read, tokens_cache_write
            FROM session
            WHERE tokens_input > 0 OR tokens_output > 0
                  OR tokens_cache_read > 0 OR tokens_cache_write > 0
        """)

        return rows.map { row in
            let counts = TokenCounts(
                input: Int(row["tokens_input"]?.intValue ?? 0),
                output: Int(row["tokens_output"]?.intValue ?? 0),
                cacheRead: Int(row["tokens_cache_read"]?.intValue ?? 0),
                cacheWrite: Int(row["tokens_cache_write"]?.intValue ?? 0),
                reasoning: Int(row["tokens_reasoning"]?.intValue ?? 0)
            )
            let date = DateParse.epoch(row["time_updated"]?.intValue ?? 0)
            let cost = row["cost"]?.doubleValue ?? 0
            return UsageRecord(
                kind: .opencode,
                date: date,
                model: modelName(from: row["model"]?.stringValue),
                sessionId: row["id"]?.stringValue ?? UUID().uuidString,
                counts: counts,
                // The column exists but is often 0; treat 0 as "estimate instead".
                realCost: cost > 0 ? cost : nil
            )
        }
    }

    /// opencode stores the model as JSON, e.g. `{"id":"gemini-3.1-pro","providerID":"google"}`.
    private func modelName(from raw: String?) -> String {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = obj["id"] as? String else {
            return raw ?? "unknown"
        }
        return id
    }
}

/// Caches SQLite-derived records so a large database is only re-read when its
/// file (or WAL sidecar) actually changes.
final class DBResultCache {
    private var signature: String?
    private var cached: [UsageRecord] = []

    func records(dbPath: String, load: () -> [UsageRecord]) -> [UsageRecord] {
        let sig = Self.signature(for: dbPath)
        if sig == signature { return cached }
        cached = load()
        signature = sig
        return cached
    }

    private static func signature(for path: String) -> String {
        let fm = FileManager.default
        func stamp(_ p: String) -> String {
            guard let a = try? fm.attributesOfItem(atPath: p) else { return "-" }
            let m = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let s = (a[.size] as? Int) ?? 0
            return "\(m):\(s)"
        }
        // Include the WAL file — recent writes live there before checkpointing.
        return stamp(path) + "|" + stamp(path + "-wal")
    }
}
