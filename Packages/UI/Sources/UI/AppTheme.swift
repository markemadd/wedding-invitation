import SwiftUI

// MARK: - Design tokens (blueprint Section 2)
// Centralizing these in one file means every screen pulls from the same
// palette, and switching a color later touches one place, not forty.
public enum AppTheme {
    // Named semantically, not by hue, so "AccentMint" still makes sense
    // if the exact shade changes later. The actual values live in the app
    // target's Assets.xcassets with explicit light/dark appearance variants
    // (dark is the primary design target per Section 2).
    public static let accentMint = Color("AccentMint")
    public static let accentCream = Color("AccentCream")
    public static let backgroundGradientStart = Color("BackgroundGradientStart")
    public static let backgroundGradientEnd = Color("BackgroundGradientEnd")

    /// The signature deep green-to-black gradient — every screen's base
    /// layer. Glassmorphism cards only read correctly over this (a GlassCard
    /// on a plain flat background looks like a bug, not a design choice).
    public static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundGradientStart, backgroundGradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
