import SwiftUI
import UIKit
import UserNotifications
import Persistence
import MizanSecurity
import UI

// Presents local notifications (e.g. category-limit alerts) as banners even
// while Mizan is in the foreground — otherwise iOS silently suppresses them.
final class NotificationForegrounder: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - Mizan app entry point (Phase 1 wiring)
// Composition root: this is the one place where the security module is
// wired into persistence (DatabaseManager gets its Keychain-backed key
// provider) and where scene-phase transitions drive the lock.
@main
struct MizanApp: App {
    @StateObject private var lockViewModel: AppLockViewModel
    @StateObject private var profile = ProfileStore()
    @Environment(\.scenePhase) private var scenePhase

    /// Shared so the lock flow and any future backup/logout UI use the same
    /// authenticated context (single Face ID prompt per unlock).
    private static let keyManager = KeychainKeyManager()
    private static let notificationDelegate = NotificationForegrounder()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        #if DEBUG
        // App Store screenshot capture: fixed-key demo DB, no Face ID, seeded
        // data, starts unlocked. Compiled out of Release; only fires when
        // launched with MIZAN_SCREENSHOT=1.
        if MizanScreenshotMode.isOn {
            MizanScreenshotMode.prepareDefaults()
            DatabaseManager.shared.configure(keyProvider: ScreenshotKeyProvider())
            try? ScreenshotSeeder().seed()
            let lock = AppLockViewModel(keyManager: Self.keyManager)
            lock.debugForceUnlock()
            _lockViewModel = StateObject(wrappedValue: lock)
            return
        }
        #endif
        DatabaseManager.shared.configure(keyProvider: Self.keyManager)
        _lockViewModel = StateObject(wrappedValue: AppLockViewModel(keyManager: Self.keyManager))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(lockViewModel)
                .environmentObject(profile)
                // Appearance follows the user's theme preference (see
                // RootView). The App Switcher privacy cover also lives in
                // RootView, driven by UIKit activity notifications.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        // Persist the latest widget snapshot BEFORE locking,
                        // so the widgets reflect this session's changes even
                        // while the app is closed.
                        WidgetSnapshotPublisher.refresh()
                        lockViewModel.lock() // Immediate, no Task/delay/timer.
                    }
                }
        }
    }
}

// MARK: - RootView
// Switches between the lock screen and the app content. The database is
// only reachable behind isUnlocked, and every service re-requests the
// connection through DatabaseManager, so UI state and connection state
// can never drift apart.
struct RootView: View {
    @EnvironmentObject private var lockViewModel: AppLockViewModel
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("didSeeIntro") private var didSeeIntro = false
    // The App Switcher privacy cover is driven by UIKit's activity
    // notifications, NOT SwiftUI's scenePhase. After the Face ID sheet
    // dismisses at launch, scenePhase can stay `.inactive` and never return to
    // `.active`, which left the opaque PrivacyShieldView stuck on top forever.
    // `didBecomeActive` fires reliably in that case, so the cover always clears
    // once the app is actually frontmost and interactive again.
    @State private var isActive = true
    /// System / Light / Dark — the whole app's appearance follows this.
    @AppStorage(ThemeChoice.storageKey) private var themeChoiceRaw = ThemeChoice.system.rawValue

    private var themeChoice: ThemeChoice { ThemeChoice(rawValue: themeChoiceRaw) ?? .system }

    var body: some View {
        content
            .overlay {
                // Covers the App Switcher / resign-active snapshot so balances
                // don't leak into the multitasking preview. Skipped while
                // locked — the lock screen holds nothing sensitive.
                if !isActive && lockViewModel.isUnlocked {
                    PrivacyShieldView()
                }
            }
            // The user's appearance preference. Safe here now that the privacy
            // shield runs off UIKit notifications, not scenePhase.
            .preferredColorScheme(themeChoice.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                isActive = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                isActive = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if !didSeeIntro {
            // First-launch intro carousel, before the lock (holds nothing
            // sensitive). Shown once. Kept dark regardless of theme — it's a
            // branded splash designed against the deep-green gradient.
            OnboardingIntroView { didSeeIntro = true }
                .preferredColorScheme(.dark)
        } else if lockViewModel.isUnlocked {
            if profile.didOnboard {
                MainTabView()
            } else {
                // First-run setup, shown once after the first unlock.
                ProfileFormView(isOnboarding: true)
            }
        } else {
            LockScreenView(errorMessage: lockViewModel.unlockErrorMessage) {
                Task { await lockViewModel.attemptUnlock() }
            }
            .task {
                // Prompt automatically on launch/relaunch; the button
                // remains as the retry path after a cancel or failure.
                await lockViewModel.attemptUnlock()
            }
        }
    }
}
