import SwiftUI

// MARK: - Radial gauge for net worth (blueprint Section 2)
// A simple arc built from Shape + trim(from:to:) — no third-party charting
// library needed for something this specific. Used for the single "big
// number" moment on the home screen (the "All Total" dial in the reference).
public struct RadialGauge: View {
    /// 0...1, e.g. how "healthy" the net worth trend is this month.
    public let progress: Double

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(KitTheme.ink.opacity(0.15), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.1, to: 0.1 + progress * 0.8)
                .stroke(AppTheme.accentMint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
    }
}
