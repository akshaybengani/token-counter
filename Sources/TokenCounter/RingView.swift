import SwiftUI

/// A progress ring drawn as one or more stacked arcs, with arbitrary content centred
/// inside it. One arc per provider in combined mode, a single arc for a provider ring.
struct RingView<Center: View>: View {
    var segments: [RingSegment]
    var lineWidth: CGFloat
    var glow: Bool = true
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)

            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: max(segment.end, segment.start + 0.0001))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: glow ? segment.color.opacity(0.40) : .clear, radius: glow ? 4 : 0)
            }
            .animation(.easeInOut(duration: 0.6), value: segments)

            center()
                .padding(lineWidth + 6)
        }
    }
}

extension RingView where Center == EmptyView {
    init(segments: [RingSegment], lineWidth: CGFloat, glow: Bool = true) {
        self.init(segments: segments, lineWidth: lineWidth, glow: glow) { EmptyView() }
    }
}

/// The used figure over the target, stacked, as it appears inside the main ring.
struct RingCenterLabel: View {
    var used: String
    var target: String

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

            Text(target)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
