import Foundation

/// A headless summary of what the scanners see, used to sanity-check parsing
/// without launching the UI. Triggered by the `TOKENUSAGE_DUMP` env var.
enum DebugDump {
    /// Exercises JSONLScanCache's incremental paths against a synthetic log:
    /// cache hit, appended lines, a trailing line with no newline, a partial
    /// line completed by a later append, and a rewritten (shrunk) file.
    /// Triggered by `TOKENUSAGE_SELFTEST=1`; exits non-zero on failure.
    static func selfTest() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("tokenusage-selftest-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")

        let cache = JSONLScanCache<[UsageRecord]>(
            initial: { [] },
            reduce: { records, obj, _ in
                guard let usage = obj.dict("usage") else { return }
                records.append(UsageRecord(
                    kind: .claude, date: Date(), model: "m", sessionId: "s",
                    counts: TokenCounts(input: usage.int("in")), realCost: nil))
            },
            finalize: { records, _ in records }
        )

        func check(_ name: String, _ expected: Int) {
            let got = cache.records(for: file).reduce(0) { $0 + $1.counts.input }
            print("\(got == expected ? "PASS" : "FAIL")  \(name) (total \(got), expected \(expected))")
            if got != expected { exit(1) }
        }
        func write(_ s: String) { try! Data(s.utf8).write(to: file) }
        func append(_ s: String) {
            let h = try! FileHandle(forWritingTo: file)
            h.seekToEndOfFile()
            h.write(Data(s.utf8))
            try! h.close()
        }

        write("{\"usage\":{\"in\":1}}\n{\"usage\":{\"in\":2}}\n")
        check("initial parse", 3)
        check("unchanged file served from cache", 3)
        append("{\"usage\":{\"in\":4}}\n")
        check("appended line parsed incrementally", 7)
        append("{\"usage\":{\"in\":8}}")
        check("trailing line without newline", 15)
        append("\n{\"usa")
        check("incomplete partial line ignored", 15)
        append("ge\":{\"in\":16}}\n")
        check("partial line completed by later append", 31)
        write("{\"usage\":{\"in\":5}}\n")
        check("rewritten (shrunk) file fully reparsed", 5)
        print("self-test complete")
    }

    static func run() {
        let scanners: [AgentScanner] = [
            ClaudeScanner(), CodexScanner(), AntigravityScanner(),
            KimiScanner(), MiniMaxScanner(), OpenCodeScanner(),
        ]

        var grand = TokenCounts()
        var grandCost = 0.0
        print("agent       inst.  sessions   total tokens      ≈cost   (models ↓ per-model breakdown)")
        print(String(repeating: "─", count: 96))

        func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
        }

        for scanner in scanners {
            let r = scanner.scan()
            var counts = TokenCounts()
            var cost = 0.0
            var sessions = Set<String>()
            var perModel: [String: (TokenCounts, Double)] = [:]
            for rec in r.records {
                let c = rec.realCost ?? Pricing.estimatedCost(for: rec.counts, model: rec.model)
                counts.add(rec.counts)
                cost += c
                sessions.insert(rec.sessionId)
                var m = perModel[rec.model] ?? (TokenCounts(), 0)
                m.0.add(rec.counts); m.1 += c
                perModel[rec.model] = m
            }
            grand.add(counts)
            grandCost += cost

            print(pad(r.kind.displayName, 12)
                  + pad(r.installed ? "yes" : "no", 6)
                  + pad("\(sessions.count) sess", 9)
                  + pad(Fmt.grouped(counts.total) + " tok", 18)
                  + "≈ " + pad(Fmt.cost(cost), 10)
                  + "(\(perModel.count) model\(perModel.count == 1 ? "" : "s"))")
            for (model, m) in perModel.sorted(by: { $0.value.0.total > $1.value.0.total }) {
                print("             ↳ " + pad(model, 42)
                      + pad(Fmt.grouped(m.0.total) + " tok", 18)
                      + "≈ " + Fmt.cost(m.1))
            }
            if let note = r.note { print("             ↳ \(note)") }
        }

        print(String(repeating: "─", count: 96))
        print("TOTAL: \(Fmt.grouped(grand.total)) tokens  (≈ \(Fmt.cost(grandCost)))")

        // TOKENUSAGE_DUMP=2 also times a warm rescan (per-file caches now
        // populated) — the cost the app pays on every refresh after launch.
        if ProcessInfo.processInfo.environment["TOKENUSAGE_DUMP"] == "2" {
            let t0 = Date()
            for scanner in scanners { _ = scanner.scan() }
            print(String(format: "warm rescan: %.3fs", Date().timeIntervalSince(t0)))
        }
    }
}
