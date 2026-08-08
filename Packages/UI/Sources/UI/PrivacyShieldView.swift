import SwiftUI

// MARK: - PrivacyShieldView (Phase 1 watch-out)
// iOS captures a screenshot of the current screen for the App Switcher the
// moment the app resigns active. Without this cover, that snapshot can show
// balances even though the app is "locked." The shield is overlaid whenever
// scenePhase leaves .active — BEFORE the snapshot is taken.
//
// It is deliberately OPAQUE (gradient base + logo), not just a translucent
// blur: a light blur can leave large numerals legible in the snapshot,
// which is exactly the leak this exists to prevent.
public struct PrivacyShieldView: View {
    public init() {}

    public var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accentMint)
        }
    }
}

#Preview {
    PrivacyShieldView()
}
