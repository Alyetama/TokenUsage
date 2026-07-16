import SwiftUI

/// The full-window dashboard. Shows every tool with its models listed inline
/// (no expanding needed), sorted by usage.
struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sortedAgents) { agg in
                        AgentSectionView(agg: agg, grandTotal: store.totalCounts.total)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 470, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Agents with usage first (largest first), then installed-but-empty ones.
    private var sortedAgents: [AgentAggregate] {
        store.aggregates.sorted { a, b in
            if a.hasUsage != b.hasUsage { return a.hasUsage }
            return a.counts.total > b.counts.total
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Token Usage", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.title3.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                Spacer()
                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isScanning ? 360 : 0))
                        .animation(store.isScanning
                                   ? .linear(duration: 1).repeatForever(autoreverses: false)
                                   : .default, value: store.isScanning)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh now")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.tokens(store.totalCounts.total))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("tokens").font(.title3).foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 20) {
                stat("≈ " + Fmt.cost(store.totalCost), "estimated cost", "dollarsign.circle")
                stat("\(store.totalSessions)", "sessions", "bubble.left.and.bubble.right")
                stat(store.lastUpdated == nil ? "—" : Fmt.relative(store.lastUpdated),
                     "updated", "clock")
            }

            Text(Fmt.breakdown(store.totalCounts))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Picker("Range", selection: $store.range) {
                ForEach(TimeRange.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
        }
        .padding(18)
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).monospacedDigit()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// One tool as a card, with its models listed underneath.
struct AgentSectionView: View {
    let agg: AgentAggregate
    let grandTotal: Int

    private var maxModel: Int { agg.models.map(\.counts.total).max() ?? 0 }
    private var share: Double {
        grandTotal > 0 ? Double(agg.counts.total) / Double(grandTotal) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(agg.kind.displayName).font(.headline)
                    Text(agg.kind.vendor).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.tokens(agg.counts.total))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    if agg.hasUsage {
                        Text("≈ \(Fmt.cost(agg.cost)) · \(agg.sessionCount) sess · \(Int((share * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if agg.hasUsage {
                Text(Fmt.breakdown(agg.counts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                VStack(spacing: 9) {
                    ForEach(agg.models) { model in
                        modelRow(model)
                    }
                }
            } else if let note = agg.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !agg.installed {
                Text("Not installed").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(agg.hasUsage ? agg.kind.tint.opacity(0.25) : Color.primary.opacity(0.06))
        )
        .opacity(agg.installed ? 1 : 0.55)
    }

    private var badge: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(agg.kind.tint.gradient)
            .frame(width: 36, height: 36)
            .overlay(
                Text(agg.kind.monogram)
                    .font(.system(size: agg.kind.monogram.count > 1 ? 13 : 17,
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .opacity(agg.hasUsage ? 1 : 0.55)
    }

    private func modelRow(_ model: ModelAggregate) -> some View {
        let frac = maxModel > 0 ? Double(model.counts.total) / Double(maxModel) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Fmt.tokens(model.counts.total))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                Text("≈ " + Fmt.cost(model.cost))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(agg.kind.tint.opacity(0.7))
                        .frame(width: max(2, geo.size.width * frac))
                }
            }
            .frame(height: 4)
        }
    }
}
