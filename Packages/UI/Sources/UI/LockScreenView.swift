import SwiftUI

// MARK: - LockScreenView
// What the user sees while the app is locked. Pure presentation — the
// actual biometric flow lives in MizanSecurity's AppLockViewModel; this
// view only reports the button tap upward, keeping the UI package free of
// any security logic.
public struct LockScreenView: View {
    let errorMessage: String?
    let onUnlockTapped: () -> Void

    public init(errorMessage: String? = nil, onUnlockTapped: @escaping () -> Void) {
        self.errorMessage = errorMessage
        self.onUnlockTapped = onUnlockTapped
    }

    public var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.accentMint)
                Text("Mizan")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.primary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: onUnlockTapped) {
                    Label("Unlock", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(AppTheme.accentMint, in: Capsule())
                        .foregroundStyle(.black) // Mint is light in dark mode; black text keeps contrast in both appearances.
                }
            }
        }
    }
}

#Preview {
    LockScreenView(onUnlockTapped: {})
}
