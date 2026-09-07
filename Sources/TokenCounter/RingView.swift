import SwiftUI

/// What the ring's arc represents.
enum RingFill: Equatable {
    /// A single arc coloured by how close the figure is to its target. This is the
    /// resting state: the dial's colour is the reading you take at a glance.
    case level(fraction: Double, level: UsageLevel)
    /// One arc per provider, stacked, revealed on hover so the same dial also answers
    /// "which of them spent it".
    case segments([RingSegment])
}

/// A progress ring with arbitrary content centred inside it.
struct RingView<Center: View>: View {
    var fill: RingFill
    var lineWidth: CGFloat
    var glow: Bool = true
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)

            switch fill {
            case let .level(fraction, level):
                // A zero fraction draws nothing. Trimming to a hair instead would leave
                // a round-capped dot at twelve o'clock on every unused dial.
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(
                            colors: [level.color, level.trailing, level.color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: glow ? level.color.opacity(0.45) : .clear, radius: glow ? 5 : 0)
                    .opacity(fraction > 0 ? 1 : 0)

            case let .segments(segments):
                ForEach(segments) { segment in
                    Circle()
                        .trim(from: segment.start, to: max(segment.end, segment.start + 0.0001))
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: glow ? segment.color.opacity(0.40) : .clear, radius: glow ? 4 : 0)
                }
            }

            center()
                .padding(lineWidth + 6)
        }
        .animation(.easeInOut(duration: 0.28), value: fill)
    }
}

extension RingView where Center == EmptyView {
    init(fill: RingFill, lineWidth: CGFloat, glow: Bool = true) {
        self.init(fill: fill, lineWidth: lineWidth, glow: glow) { EmptyView() }
    }
}

/// The used figure over the target, stacked, as it appears inside the main ring.
struct RingCenterLabel: View {
    var used: String
    var target: String
    var caption: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(used)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 46, height: 1)

            Text(caption ?? target)
                .font(.system(size: caption == nil ? 13 : 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
