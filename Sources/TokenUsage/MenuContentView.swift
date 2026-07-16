import SwiftUI

/// The window shown when the menu-bar item is clicked.
struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var dashboard: DashboardWindowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            agentList
            Divider()
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Token Usage", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.headline)
                Spacer()
                Button(action: { dashboard.show() }) {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open dashboard window")
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
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("tokens")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                stat("≈ " + Fmt.cost(store.totalCost), "est. cost", "dollarsign.circle")
                stat("\(store.totalSessions)", "sessions", "bubble.left.and.bubble.right")
            }

            Picker("Range", selection: $store.range) {
                ForEach(TimeRange.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(14)
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Agent list

    private var agentList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.aggregates) { agg in
                    AgentRowView(agg: agg, maxTotal: store.maxAgentTotal,
                                 grandTotal: store.totalCounts.total)
                    if agg.id != store.aggregates.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(store.lastUpdated == nil
                 ? "Scanning…"
                 : "Updated \(Fmt.relative(store.lastUpdated))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
