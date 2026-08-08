import Foundation
import SwiftUI
import Persistence
import LLM

// MARK: - MizanAISettings
// Chooses the Mizan AI backend, in privacy order:
//   1. Apple's on-device model (Foundation Models) — free, private, no setup,
//      no network. Used automatically wherever the device supports it
//      (iPhone 15 Pro / A17 Pro and up, iOS 26+). Nothing to send anywhere.
//   2. The opt-in "use my own AI server" path — a private LAN / Tailscale link
//      to the user's own machine. OFF by default; only the injected context
//      figures + the question travel, and only to the host the user chose.
// The cloud (BYO Claude key) path is a planned third tier for devices without
// Apple Intelligence; it will slot in here behind its own explicit opt-in.
enum MizanAISettings {
    static let enabledKey = "mizanAIEnabled"
    static let serverURLKey = "mizanAIServerURL"
    static let modelKey = "mizanAIModel"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var serverURLString: String { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
    static var model: String {
        let value = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return value.isEmpty ? "llama3.1" : value
    }

    /// True when Apple's on-device model is present AND ready on this device.
    /// Compiles to `false` on toolchains without the FoundationModels SDK.
    static var isOnDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return AppleFoundationModelsBackend.isAvailable }
        #endif
        return false
    }

    /// The backend for LLMService, in privacy order: on-device first, then the
    /// opt-in server path, else nil (which keeps the AI screen in its empty
    /// state with setup guidance).
    static func makeBackend() -> LanguageModelBackend? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleFoundationModelsBackend.isAvailable {
            return AppleFoundationModelsBackend()
        }
        #endif
        guard isEnabled,
              let url = URL(string: serverURLString),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return RemoteLLMBackend(baseURL: url, model: model)
    }
}

// MARK: - ThemeChoice
// The user's appearance preference (Settings). "system" follows iOS; the
// other two pin the app. Stored via @AppStorage("themeChoice") and applied
// with .preferredColorScheme at RootView.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "themeChoice"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// nil = follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - BudgetCycle
// The monthly budget can reset on a chosen day (your salary/pay day) instead
// of the calendar 1st. This drives the Home budget card, the safe-to-spend
// widget, and the Buckets rings — but NOT retrospective views (Insights, the
// month story), which stay on calendar months by design.
enum BudgetCycle {
    static let startDayKey = "budgetCycleStartDay"

    /// Day of month the budget resets on (your pay day). Clamped to 1–28 so it
    /// exists in every month; 29–31 would skip February. Default 1 = the plain
    /// calendar month, so existing users see no change until they pick a day.
    static var startDay: Int {
        let raw = UserDefaults.standard.integer(forKey: startDayKey) // 0 when unset
        return raw == 0 ? 1 : min(28, max(1, raw))
    }

    static func setStartDay(_ day: Int) {
        UserDefaults.standard.set(min(28, max(1, day)), forKey: startDayKey)
    }

    /// "Reset budget now": start a fresh cycle from today — which also becomes
    /// the recurring reset day going forward.
    static func resetToToday() {
        setStartDay(Calendar.current.component(.day, from: Date()))
    }

    /// The current cycle window [start, end): from the most recent occurrence
    /// of `startDay` on/before `now`, to the next occurrence. With startDay = 1
    /// this is exactly the calendar month.
    static func currentWindow(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let day = startDay
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        func anchor(_ monthsOffset: Int) -> Date {
            let base = calendar.date(byAdding: .month, value: monthsOffset, to: monthStart) ?? monthStart
            var comps = calendar.dateComponents([.year, .month], from: base)
            comps.day = day
            return calendar.date(from: comps) ?? base
        }
        let thisAnchor = anchor(0)
        return now >= thisAnchor
            ? DateInterval(start: thisAnchor, end: anchor(1))
            : DateInterval(start: anchor(-1), end: thisAnchor)
    }

    /// Whole days from `now` until the cycle resets (min 1, so the daily
    /// allowance never divides by zero on reset day).
    static func daysLeft(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let end = currentWindow(now: now, calendar: calendar).end
        return max(1, calendar.dateComponents([.day], from: now, to: end).day ?? 1)
    }
}

// MARK: - AppPreferences
// Small on-device (UserDefaults) settings that aren't transaction data:
// the default account new captures draw from, plus the monthly-budget and
// category-color keys used elsewhere. Kept out of the encrypted DB by choice —
// these are single scalars, not financial records.
enum AppPreferences {
    static let defaultAccountKey = "defaultAccountId"

    static func defaultAccountId() -> Int64? {
        (UserDefaults.standard.object(forKey: defaultAccountKey) as? NSNumber)?.int64Value
    }

    static func setDefaultAccountId(_ id: Int64?) {
        if let id {
            UserDefaults.standard.set(NSNumber(value: id), forKey: defaultAccountKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultAccountKey)
        }
    }

    /// The default account id if it still exists, otherwise the first account —
    /// so a deleted default never leaves a capture pointing at nothing.
    static func resolvedDefaultAccountId(in accounts: [Account]) -> Int64? {
        if let id = defaultAccountId(), accounts.contains(where: { $0.id == id }) { return id }
        return accounts.first?.id
    }
}
