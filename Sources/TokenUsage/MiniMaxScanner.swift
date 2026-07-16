import Foundation

/// Reads MiniMax (Mavis / MiniMax Code) usage from `~/.minimax/sqlite.db`. The
/// `token_usage` table records per-turn tokens and a real cost.
final class MiniMaxScanner: AgentScanner {
    let kind: AgentKind = .minimax
    private let dbCache = DBResultCache()

    private var dbPath: String {
        home.appendingPathComponent(".minimax/sqlite.db").path
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
            SELECT session_id, model, ts, cost_usd,
                   input_tokens, output_tokens, reasoning_tokens,
                   cache_read_tokens, cache_write_tokens
            FROM token_usage
        """)

        return rows.map { row in
            let counts = TokenCounts(
                input: Int(row["input_tokens"]?.intValue ?? 0),
                output: Int(row["output_tokens"]?.intValue ?? 0),
                cacheRead: Int(row["cache_read_tokens"]?.intValue ?? 0),
                cacheWrite: Int(row["cache_write_tokens"]?.intValue ?? 0),
                reasoning: Int(row["reasoning_tokens"]?.intValue ?? 0)
            )
            let cost = row["cost_usd"]?.doubleValue
            return UsageRecord(
                kind: .minimax,
                date: DateParse.epoch(row["ts"]?.intValue ?? 0),
                model: row["model"]?.stringValue ?? "minimax",
                sessionId: row["session_id"]?.stringValue ?? UUID().uuidString,
                counts: counts,
                realCost: (cost ?? 0) > 0 ? cost : nil
            )
        }
    }
}
