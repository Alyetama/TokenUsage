import SwiftUI

/// One agent's row in the breakdown list. Tap to expand the token-type split.
struct AgentRowView: View {
    let agg: AgentAggregate
    let maxTotal: Int
    let grandTotal: Int

    @State private var expanded = false

    private var fraction: Double {
        maxTotal > 0 ? Double(agg.counts.total) / Double(maxTotal) : 0
    }
    private var share: Double {
        grandTotal > 0 ? Double(agg.counts.total) / Double(grandTotal) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    badge
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agg.kind.displayName).font(.callout.weight(.medium))
                        Text(agg.kind.vendor).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    trailing
                }
            }
            .buttonStyle(.plain)

            if agg.hasUsage {
                bar
                if expanded { details }
            } else if let note = agg.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 52)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(agg.installed ? 1 : 0.5)
    }

    // MARK: Pieces

    private var badge: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(agg.kind.tint.gradient)
            .frame(width: 30, height: 30)
            .overlay(
                Text(agg.kind.monogram)
                    .font(.system(size: agg.kind.monogram.count > 1 ? 11 : 14,
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .opacity(agg.hasUsage ? 1 : 0.55)
    }

    @ViewBuilder
    private var trailing: some View {
        if agg.hasUsage {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.tokens(agg.counts.total))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                Text("≈ " + Fmt.cost(agg.cost))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption2).foregroundStyle(.tertiary)
        } else {
            Text(agg.installed ? "no usage" : "not installed")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(agg.kind.tint)
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
        .padding(.leading, 52)
    }

    private var details: some View {
        let maxModel = agg.models.map(\.counts.total).max() ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            Text(Fmt.breakdown(agg.counts))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(agg.models.count == 1 ? "1 MODEL" : "\(agg.models.count) MODELS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)

            ForEach(agg.models) { model in
                modelRow(model, maxModel: maxModel)
            }

            HStack {
                Text("\(agg.sessionCount) session\(agg.sessionCount == 1 ? "" : "s") · \(Int((share * 100).rounded()))% of all tokens")
                Spacer()
                Text("last active \(Fmt.relative(agg.lastActivity))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
        }
        .padding(.leading, 52)
        .padding(.top, 3)
    }

    private func modelRow(_ model: ModelAggregate, maxModel: Int) -> some View {
        let frac = maxModel > 0 ? Double(model.counts.total) / Double(maxModel) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Fmt.tokens(model.counts.total))
                    .font(.caption.weight(.medium)).monospacedDigit()
                Text("≈ " + Fmt.cost(model.cost))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(agg.kind.tint.opacity(0.55))
                        .frame(width: max(2, geo.size.width * frac))
                }
            }
            .frame(height: 3)
        }
    }

    private func toggle() {
        guard agg.hasUsage else { return }
        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
    }
}
