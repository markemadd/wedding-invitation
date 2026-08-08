import SwiftUI
import GRDB
import Persistence
import UI

// MARK: - AccountBalancesEditorView
// Presented when the user taps Total Balance on Home. Total Balance is the sum
// of these account/card balances (converted to EGP), so "editing the balance"
// means adjusting the accounts here — the total stays a true sum and captured
// transactions keep adjusting it. Writes go straight through DatabaseManager
// and post .mizanDataDidChange so every screen refreshes.
struct AccountBalancesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [Account] = []
    @State private var balanceTexts: [Int64: String] = [:]
    @State private var last4Texts: [Int64: String] = [:]
    @State private var showNewAccount = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    Text("Total Balance is the sum of your accounts and cards. Adjust any balance below — new transactions keep it up to date automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(KitTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if accounts.isEmpty {
                        KitCard {
                            Text("No accounts yet. Add your first account or card to start tracking your balance.")
                                .font(.system(size: 13))
                                .foregroundStyle(KitTheme.textSecondary)
                        }
                    } else {
                        KitCard {
                            VStack(spacing: 0) {
                                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                                    HStack(spacing: 12) {
                                        Image(systemName: HomeViewModel.walletIcon(AccountType(rawValue: account.type)))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(HomeViewModel.walletColor(AccountType(rawValue: account.type)))
                                            .frame(width: 36, height: 36)
                                            .background(HomeViewModel.walletColor(AccountType(rawValue: account.type)).opacity(0.14),
                                                        in: RoundedRectangle(cornerRadius: 11))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(account.name.smartTitleCased)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(KitTheme.textPrimary)
                                            HStack(spacing: 5) {
                                                Text(AccountType(rawValue: account.type)?.displayName ?? account.type)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(KitTheme.textSecondary)
                                                Text("· ••••")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(KitTheme.textTertiary)
                                                TextField("1234", text: last4Binding(for: account))
                                                    .keyboardType(.numberPad)
                                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                                    .foregroundStyle(KitTheme.textSecondary)
                                                    .frame(width: 40)
                                            }
                                        }
                                        Spacer()
                                        AmountTextField(text: binding(for: account),
                                                        font: .system(size: 15, weight: .semibold).monospacedDigit(),
                                                        alignment: .trailing)
                                            .frame(width: 110)
                                        Text(account.currency)
                                            .font(.system(size: 11))
                                            .foregroundStyle(KitTheme.textSecondary)
                                    }
                                    .padding(.vertical, 10)
                                    if index < accounts.count - 1 {
                                        Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                                    }
                                }
                            }
                        }
                    }

                    Button { showNewAccount = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add account or card")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KitTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    KitPrimaryButton("Save") { save() }
                }
                .padding(20)
            }
            .kitBackground()
            .dismissableKeyboard()
            .navigationTitle("Edit balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(KitTheme.primary)
                }
            }
            .task { load() }
            .sheet(isPresented: $showNewAccount) {
                NewAccountView { name, type, last4 in
                    addAccount(name: name, type: type, last4: last4)
                }
            }
            .alert("Balance", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func binding(for account: Account) -> Binding<String> {
        let key = account.id ?? -1
        return Binding(
            get: { balanceTexts[key] ?? "" },
            set: { balanceTexts[key] = $0 }
        )
    }

    /// Sanitizes to at most 4 digits as the user types.
    private func last4Binding(for account: Account) -> Binding<String> {
        let key = account.id ?? -1
        return Binding(
            get: { last4Texts[key] ?? "" },
            set: { last4Texts[key] = String($0.filter(\.isNumber).prefix(4)) }
        )
    }

    private func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            accounts = try dbQueue.read { db in
                try Account.order(GRDB.Column("name")).fetchAll(db)
            }
            for account in accounts {
                balanceTexts[account.id ?? -1] = AmountFormat.grouped(account.balance)
                last4Texts[account.id ?? -1] = account.last4 ?? ""
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func addAccount(name: String, type: AccountType, last4: String?) {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.write { db in
                var account = Account(name: name, type: type.rawValue, currency: "EGP",
                                      balance: 0, last4: last4)
                try account.insert(db)
            }
            load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.write { db in
                for var account in try Account.fetchAll(db) {
                    var changed = false
                    if let value = AmountFormat.decimal(balanceTexts[account.id ?? -1] ?? ""),
                       value != account.balance {
                        account.balance = value
                        changed = true
                    }
                    let editedLast4 = (last4Texts[account.id ?? -1]).flatMap { $0.isEmpty ? nil : $0 }
                    if editedLast4 != account.last4 {
                        account.last4 = editedLast4
                        changed = true
                    }
                    if changed { try account.update(db) }
                }
            }
            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
