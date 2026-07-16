import Foundation
import SQLite3

/// A minimal read-only SQLite reader.
///
/// The coding-agent databases (opencode, MiniMax) are live, WAL-mode files that
/// the agents write to constantly. Rather than fight for a shared lock, we snapshot
/// the database (plus its `-wal`/`-shm` siblings) into a temp file and read the copy.
/// That is fully decoupled from the running agent and always sees committed data.
final class SQLiteDB {
    private var handle: OpaquePointer?
    private let tempDir: URL

    /// Column value as returned by `query`.
    enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null

        var intValue: Int64 {
            switch self {
            case .int(let v): return v
            // `Int64(v)` traps on NaN/±inf or magnitudes past Int64's range, so
            // clamp before converting.
            case .double(let v):
                guard v.isFinite else { return 0 }
                if v >= 9.0e18 { return Int64.max }
                if v <= -9.0e18 { return Int64.min }
                return Int64(v)
            case .text(let s): return Int64(s) ?? 0
            case .null: return 0
            }
        }

        var doubleValue: Double? {
            switch self {
            case .int(let v): return Double(v)
            case .double(let v): return v
            case .text(let s): return Double(s)
            case .null: return nil
            }
        }

        var stringValue: String? {
            switch self {
            case .text(let s): return s
            case .int(let v): return String(v)
            case .double(let v): return String(v)
            case .null: return nil
            }
        }
    }

    /// Opens a read-only snapshot of the database at `path`, or returns `nil` if
    /// the file is missing or cannot be opened.
    init?(snapshotOf path: String) {
        let source = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let fm = FileManager.default
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("tokenusage-\(UUID().uuidString)", isDirectory: true)
        do {
            // Some of these databases (opencode, MiniMax) also hold credential
            // tables, so the snapshot directory is created owner-only (0700) and
            // each copied file is locked to 0600 — the copy is never more
            // readable than it needs to be, and it is deleted in `deinit`.
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let dest = tempDir.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at: source, to: dest)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            // Copy the WAL/SHM sidecars so recent (un-checkpointed) writes are visible.
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: path + suffix)
                if fm.fileExists(atPath: side.path) {
                    let sideDest = tempDir.appendingPathComponent(side.lastPathComponent)
                    try? fm.copyItem(at: side, to: sideDest)
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sideDest.path)
                }
            }
            if sqlite3_open_v2(dest.path, &handle, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
                try? fm.removeItem(at: tempDir)
                return nil
            }
        } catch {
            try? fm.removeItem(at: tempDir)
            return nil
        }
    }

    deinit {
        if handle != nil { sqlite3_close(handle) }
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Runs a query and returns rows keyed by column name.
    func query(_ sql: String) -> [[String: Value]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let columnCount = sqlite3_column_count(stmt)
        var names: [String] = []
        names.reserveCapacity(Int(columnCount))
        for i in 0..<columnCount {
            names.append(String(cString: sqlite3_column_name(stmt, i)))
        }

        var rows: [[String: Value]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Value] = [:]
            for i in 0..<columnCount {
                let value: Value
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    value = .int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    value = .double(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    value = .text(String(cString: sqlite3_column_text(stmt, i)))
                default:
                    value = .null
                }
                row[names[Int(i)]] = value
            }
            rows.append(row)
        }
        return rows
    }
}
