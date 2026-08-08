import SwiftUI

// MARK: - SegmentedProgressBar (ENHANCEMENTS Wave A1)
// The blueprint's mint/cream/red progress language in one reusable view,
// replacing bare `ProgressView(value:)` bars whose single tint ignored the
// "on-track / approaching / over" color rule. Same three-state threshold
// as DashboardSection's month cards, now shared so every bar reads alike.
public struct SegmentedProgressBar: View {
    /// 0...1+, clamped visually at 1 (an over-budget bar fills fully rather
    /// than overflowing its track).
    public let fraction: Double
    public let height: CGFloat

    public init(fraction: Double, height: CGFloat = 6) {
        self.fraction = fraction
        self.height = height
    }

    private var tint: Color {
        fraction >= 1.0 ? .red
        : fraction >= 0.8 ? AppTheme.accentCream
        : AppTheme.accentMint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(KitTheme.ink.opacity(0.12))
                    .frame(height: height)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(1, max(0, fraction)), height: height)
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: height)
    }
}

#Preview {
    VStack(spacing: 16) {
        SegmentedProgressBar(fraction: 0.4)
        SegmentedProgressBar(fraction: 0.85)
        SegmentedProgressBar(fraction: 1.2)
    }
    .padding()
    .background(AppTheme.backgroundGradient)
}
