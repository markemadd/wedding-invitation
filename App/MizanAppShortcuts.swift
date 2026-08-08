import AppIntents

// MARK: - MizanAppShortcuts
// Surfaces the capture intents in the Shortcuts app and Siri so the user
// can build the SMS personal-automations without hunting for the actions.
// The SAME LogBankSMSIntent handles BOTH directions — the parser reads the
// message and logs InstaPay sends as expenses and InstaPay receives (تم
// استلام / أضيف إلى حسابك / "received via InstaPay") as income — so one
// automation on the InstaPay sender covers money in AND out. The extra
// phrases below just make the receive case easy to find and name.
struct MizanAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogBankSMSIntent(),
            phrases: [
                "Log a bank message in \(.applicationName)",
                "Capture a bank SMS in \(.applicationName)",
                "Log an InstaPay transfer in \(.applicationName)",
                "Log money received in \(.applicationName)",
                "Log an InstaPay payment received in \(.applicationName)"
            ],
            shortTitle: "Log bank / InstaPay SMS",
            systemImageName: "message.badge.filled.fill"
        )
        AppShortcut(
            intent: LogWalletTransactionIntent(),
            phrases: [
                "Log a wallet payment in \(.applicationName)"
            ],
            shortTitle: "Log wallet payment",
            systemImageName: "creditcard.fill"
        )
    }
}
