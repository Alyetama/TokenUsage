import SwiftUI

/// Owns the scanners, runs them off the main thread, and publishes aggregated
/// usage for the currently-selected time range.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var aggregates: [AgentAggregate] = []
    @Published private(set) var totalCounts = TokenCounts()
    @Published private(set) var totalCost = 0.0
    @Published private(set) var totalSessions = 0
    @Published private(set) var isScanning = false
    @Published private(set) var lastUpdated: Date?

    @Published var range: TimeRange = .all {
        didSet { recompute() }
    }

    private var allRecords: [UsageRecord] = []
    private var meta: [AgentKind: (installed: Bool, note: String?)] = [:]

    private let scanners: [AgentScanner] = [
        ClaudeScanner(),
        CodexScanner(),
        AntigravityScanner(),
        KimiScanner(),
        MiniMaxScanner(),
        OpenCodeScanner(),
    ]
    private let queue = DispatchQueue(label: "com.tokenusage.scan", qos: .utility)

    /// Rescans every source. Cheap when nothing changed thanks to per-file /
    /// per-database caching inside the scanners.
    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        // Scanners are only ever used on the scan queue after init; the
        // unsafe-transfer annotation silences the strict-concurrency warning.
        nonisolated(unsafe) let scanners = self.scanners
        queue.async { [weak self] in
            // Scanners are independent; run them across cores.
            let results = ScanHelp.parallelMap(scanners) { $0.scan() }
            DispatchQueue.main.async { self?.apply(results) }
        }
    }

    private func apply(_ results: [ScanResult]) {
        allRecords = results.flatMap(\.records)
        meta = [:]
        for r in results { meta[r.kind] = (r.installed, r.note) }
        isScanning = false
        lastUpdated = Date()
        recompute()
    }

    private func recompute() {
        let now = Date()

        // Last activity is always all-time, independent of the selected range.
        var lastActivity: [AgentKind: Date] = [:]
        for rec in allRecords {
            if let existing = lastActivity[rec.kind] {
                if rec.date > existing { lastActivity[rec.kind] = rec.date }
            } else {
                lastActivity[rec.kind] = rec.date
            }
        }

        // Accumulate at both the agent and the (agent, model) level in one pass.
        var byKind: [AgentKind: Acc] = [:]
        var byModel: [AgentKind: [String: Acc]] = [:]
        for rec in allRecords where range.contains(rec.date, now: now) {
            let c = rec.realCost ?? Pricing.estimatedCost(for: rec.counts, model: rec.model)
            byKind[rec.kind, default: Acc()].add(rec, cost: c)
            byModel[rec.kind, default: [:]][rec.model, default: Acc()].add(rec, cost: c)
        }

        aggregates = AgentKind.ordered.map { kind in
            let m = meta[kind] ?? (installed: false, note: nil)
            let agent = byKind[kind] ?? Acc()
            let models = (byModel[kind] ?? [:])
                .map { model, acc in
                    ModelAggregate(model: model, counts: acc.counts, cost: acc.cost,
                                   sessionCount: acc.sessions.count, lastActivity: acc.last)
                }
                .sorted { $0.counts.total > $1.counts.total }
            return AgentAggregate(
                kind: kind,
                counts: agent.counts,
                cost: agent.cost,
                sessionCount: agent.sessions.count,
                lastActivity: lastActivity[kind],
                models: models,
                installed: m.installed,
                note: m.note
            )
        }
        totalCounts = aggregates.reduce(TokenCounts()) { $0 + $1.counts }
        totalCost = aggregates.reduce(0) { $0 + $1.cost }
        totalSessions = aggregates.reduce(0) { $0 + $1.sessionCount }
    }

    /// The largest single-agent total in the current range, for scaling bars.
    var maxAgentTotal: Int {
        aggregates.map(\.counts.total).max() ?? 0
    }
}

/// A small mutable accumulator used while folding records into aggregates.
private struct Acc {
    var counts = TokenCounts()
    var cost = 0.0
    var sessions = Set<String>()
    var last: Date?

    mutating func add(_ rec: UsageRecord, cost c: Double) {
        counts.add(rec.counts)
        cost += c
        sessions.insert(rec.sessionId)
        if last == nil || rec.date > last! { last = rec.date }
    }
}
