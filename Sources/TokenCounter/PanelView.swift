import SwiftUI

struct PanelView: View {
    @EnvironmentObject var store: UsageStore
    @State private var hovering = false
    @State private var hoveringRing = false

    var body: some View {
        VStack(spacing: 10) {
            header

            switch store.mode {
            case .combined: combined
            case .separate: separate
            }

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .frame(width: 216)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(store.level.color)
                .frame(width: 6, height: 6)
            Text("TOKENS TODAY")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.9)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            }
        }
    }

    // MARK: - Combined: one ring, one arc per provider

    private var combined: some View {
        VStack(spacing: 10) {
            // At rest the dial's colour is the reading. Hovering it splits the same arc
            // by provider, which answers "which of them spent it" without a second chart.
            RingView(
                fill: hoveringRing
                    ? .segments(store.combinedSegments)
                    : .level(fraction: store.combinedFraction, level: store.level),
                lineWidth: 13
            ) {
                RingCenterLabel(
                    used: (store.hasPartialData ? "≥" : "") + Fmt.compact(store.combinedUsed),
                    target: Fmt.compactTight(store.combinedTarget),
                    caption: hoveringRing ? "by provider" : nil
                )
            }
            .frame(width: 132, height: 132)
            .padding(.vertical, 2)
            .onHover { hoveringRing = $0 }

            VStack(spacing: 2) {
                Text(store.percentText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.level.color)
                    .monospacedDigit()

                Text(store.combinedRawFraction >= 1
                     ? "over daily target"
                     : "\(Fmt.compact(store.combinedRemaining)) left today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            legend

            if store.showBreakdown {
                breakdown(store.combinedCounts)
            }
        }
    }

    private var legend: some View {
        VStack(spacing: 3) {
            ForEach(store.activeProviders) { id in
                let snap = store.snapshot(id)
                HStack(spacing: 6) {
                    // Full strength always. Dimming these was diluting them toward
                    // the panel background, which eroded the separation the palette
                    // was validated for; identity is not something to de-emphasise.
                    Circle()
                        .fill(snap.installed ? id.tint : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                    Text(id.shortName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(legendValue(id, snap))
                        .font(.system(size: snap.installed && snap.quality != .unavailable ? 10 : 9,
                                      weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(snap.installed && snap.quality != .unavailable
                                         ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .padding(.top, 1)
        .animation(.easeInOut(duration: 0.2), value: hoveringRing)
    }

    private func legendValue(_ id: ProviderID, _ snap: ProviderSnapshot) -> String {
        guard snap.installed else { return "Not installed" }
        guard snap.quality != .unavailable else { return "No token data" }
        let marker = snap.quality == .partial && store.used(id) > 0 ? "≥" : ""
        return marker + Fmt.compact(store.used(id))
    }

    // MARK: - Separate: a small ring per provider, each with its own target

    private var separate: some View {
        VStack(spacing: 9) {
            ForEach(store.activeProviders) { id in
                providerRow(id)
            }
        }
        .padding(.vertical, 2)
    }

    private func providerRow(_ id: ProviderID) -> some View {
        let snap = store.snapshot(id)
        let used = store.used(id)
        let reports = snap.installed && snap.quality != .unavailable

        return HStack(spacing: 9) {
            RingView(
                fill: .level(fraction: reports ? store.fraction(id) : 0,
                             level: UsageLevel(fraction: store.rawFraction(id))),
                lineWidth: 5,
                glow: false
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(id.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(rowSubtitle(id, snap, used: used, reports: reports))
                    .font(.system(size: 9))
                    .foregroundStyle(reports ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            if reports {
                Text(store.percentText(store.rawFraction(id)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(UsageLevel(fraction: store.rawFraction(id)).color)
                    .monospacedDigit()
            }
        }
    }

    private func rowSubtitle(_ id: ProviderID, _ snap: ProviderSnapshot, used: Int, reports: Bool) -> String {
        guard snap.installed else { return "Not installed" }
        guard snap.quality != .unavailable else {
            return snap.counts.calls > 0
                ? "No token data · \(Fmt.calls(snap.counts.calls))"
                : "No token data"
        }
        let marker = snap.quality == .partial && used > 0 ? "≥" : ""
        return "\(marker)\(Fmt.compact(used)) of \(Fmt.compactTight(store.target(id)))"
    }

    // MARK: - Breakdown

    private func breakdown(_ counts: TokenCounts) -> some View {
        HStack(spacing: 0) {
            stat("in", counts.input)
            divider
            stat("out", counts.output)
            divider
            stat("cache", counts.cacheWrite)
            if store.includeCacheReads {
                divider
                stat("read", counts.cacheRead)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 18)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text(Fmt.compact(value))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(Fmt.relative(store.lastUpdated))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            if hovering {
                iconButton("arrow.clockwise", help: "Refresh now") { store.refresh() }
                iconButton("gearshape", help: "Settings") { AppDelegate.shared?.openSettings() }
            }
        }
        .frame(height: 14)
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
