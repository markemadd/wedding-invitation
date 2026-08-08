import SwiftUI

// MARK: - Reusable glass card (blueprint Section 2)
// Every card on every screen should use this one view, not a hand-rolled
// background per screen — that's how visual drift creeps in over time.
public struct GlassCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(18)
            .background(.ultraThinMaterial) // The frosted-glass effect, built into SwiftUI.
            .cornerRadius(24) // Generous rounding (16–28px range) per the design direction.
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(KitTheme.ink.opacity(0.08), lineWidth: 0.5)
            )
    }
}
