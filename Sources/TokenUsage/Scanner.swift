import Foundation

/// What a scanner returns for one agent.
struct ScanResult {
    let kind: AgentKind
    /// The agent's data directory exists on disk.
    var installed: Bool
    var records: [UsageRecord]
    /// Explains why usage is unavailable when `installed` but `records` is empty.
    var note: String?
}

/// Reads local token usage for a single agent. Implementations run off the main
/// thread and must be safe to call repeatedly (the store polls them).
protocol AgentScanner: AnyObject {
    var kind: AgentKind { get }
    func scan() -> ScanResult
}

extension AgentScanner {
    var home: URL { FileManager.default.homeDirectoryForCurrentUser }
}

/// Incremental, thread-safe cache over JSONL log files.
///
/// The agent logs are append-only, so on rescan only the bytes added since the
/// last scan are read and parsed — an active multi-megabyte session file costs
/// a stat plus its new tail, not a full reparse. A file whose size shrank or
/// whose mtime changed without growing is reparsed from the start.
///
/// `State` accumulates across the lines of one file (a plain `[UsageRecord]`
/// for per-line scanners, or a custom struct for stateful formats like Codex's
/// running totals). `lineFilter` runs on the raw bytes of each line before any
/// JSON parsing, letting scanners cheaply skip the (vast majority of) lines
/// that can't possibly be usage entries.
final class JSONLScanCache<State> {
    private struct Entry {
        var mtime: TimeInterval
        var size: Int
        /// Bytes consumed through the end of the last fully-parsed line.
        var offset: Int
        var state: State
        var records: [UsageRecord]
    }

    private var cache: [String: Entry] = [:]
    private let lock = NSLock()

    private let initial: () -> State
    private let lineFilter: (Data) -> Bool
    private let reduce: (inout State, [String: Any], URL) -> Void
    private let finalize: (State, URL) -> [UsageRecord]

    init(initial: @escaping () -> State,
         lineFilter: @escaping (Data) -> Bool = { _ in true },
         reduce: @escaping (inout State, [String: Any], URL) -> Void,
         finalize: @escaping (State, URL) -> [UsageRecord]) {
        self.initial = initial
        self.lineFilter = lineFilter
        self.reduce = reduce
        self.finalize = finalize
    }

    /// Returns the records for `url`, parsing only what changed since last call.
    /// Safe to call concurrently for distinct files.
    func records(for url: URL) -> [UsageRecord] {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? Int) ?? 0

        lock.lock()
        let cached = cache[url.path]
        lock.unlock()

        if let hit = cached, hit.mtime == mtime, hit.size == size {
            return hit.records
        }

        // Grown file: assume append-only and continue from the stored offset.
        // Anything else (shrunk, or touched without growing): reparse fully.
        var entry: Entry
        if let hit = cached, size > hit.size {
            entry = hit
        } else {
            entry = Entry(mtime: mtime, size: size, offset: 0,
                          state: initial(), records: [])
        }

        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if entry.offset > 0 { try? handle.seek(toOffset: UInt64(entry.offset)) }
            if let data = try? handle.readToEnd(), !data.isEmpty {
                entry.offset += consume(data, into: &entry.state, url: url)
            }
        }

        entry.mtime = mtime
        entry.size = size
        entry.records = finalize(entry.state, url)

        lock.lock()
        cache[url.path] = entry
        lock.unlock()
        return entry.records
    }

    /// Drops cache entries for files that no longer exist.
    func prune(keeping livePaths: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        for key in cache.keys where !livePaths.contains(key) {
            cache.removeValue(forKey: key)
        }
    }

    /// Feeds each complete line of `data` through the filter + JSON parser and
    /// returns the number of bytes consumed. A trailing line with no newline is
    /// consumed only if it already parses as JSON (a writer mid-line otherwise
    /// leaves it for the next scan).
    private func consume(_ data: Data, into state: inout State, url: URL) -> Int {
        var consumed = 0
        var start = data.startIndex
        while start < data.endIndex {
            if let nl = data[start...].firstIndex(of: 0x0A) {
                parseLine(data[start..<nl], into: &state, url: url)
                start = data.index(after: nl)
                consumed = start - data.startIndex
            } else {
                if parseLine(data[start...], into: &state, url: url) {
                    consumed = data.count
                }
                break
            }
        }
        return consumed
    }

    @discardableResult
    private func parseLine(_ raw: Data, into state: inout State, url: URL) -> Bool {
        // Trim surrounding whitespace/CR bytes, require a JSON object.
        var line = raw
        while let first = line.first, first == 0x20 || first == 0x09 || first == 0x0D {
            line = line.dropFirst()
        }
        while let last = line.last, last == 0x20 || last == 0x09 || last == 0x0D {
            line = line.dropLast()
        }
        guard line.first == 0x7B else { return false }  // '{'
        guard lineFilter(line) else { return true }     // valid-looking, just irrelevant
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return false }
        reduce(&state, obj, url)
        return true
    }
}

enum ScanHelp {
    /// Recursively collects files under `root` whose name matches `predicate`.
    static func files(under root: URL, matching predicate: (String) -> Bool) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in en where predicate(url.lastPathComponent) {
            result.append(url)
        }
        return result
    }

    /// Maps `transform` over `items` on all available cores, preserving order.
    static func parallelMap<T, R>(_ items: [T], _ transform: (T) -> R) -> [R] {
        guard items.count > 1 else { return items.map(transform) }
        var results = [R?](repeating: nil, count: items.count)
        results.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: items.count) { i in
                buf[i] = transform(items[i])
            }
        }
        return results.map { $0! }
    }
}

/// Convenience accessors for pulling typed values out of `[String: Any]` JSON.
extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func str(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int {
        // Integral JSON numbers bridge straight to a 64-bit Int. For anything
        // else (a float, or a value that doesn't fit) fall back to NSNumber's
        // 64-bit accessor — `Int(someDouble)` traps on out-of-range input, so it
        // is deliberately avoided here.
        if let n = self[key] as? Int { return n }
        if let n = self[key] as? NSNumber { return Int(n.int64Value) }
        if let s = self[key] as? String { return Int(s) ?? 0 }
        return 0
    }
}
