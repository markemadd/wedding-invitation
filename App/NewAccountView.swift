import SwiftUI
import Persistence
import UI

// MARK: - NewAccountView
// Minimal quick-create for a card or account, reachable from the capture
// form ("Add card or account…"). Full account management (edit, delete,
// balances) is Phase 3.1; this exists so "which card did I pay with" never
// blocks on a missing picker entry.
struct NewAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: AccountType = .creditCard
    @State private var last4 = ""

    /// Called with the new account's name, type, and optional card last-4.
    let onCreate: (String, AccountType, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("New card or account") {
                    TextField("Name (e.g. CIB Credit)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { accountType in
                            Text(accountType.displayName).tag(accountType)
                        }
                    }
                }
                Section {
                    TextField("Last 4 digits (optional)", text: $last4)
                        .keyboardType(.numberPad)
                        .onChange(of: last4) { _, new in
                            last4 = String(new.filter(\.isNumber).prefix(4))
                        }
                } header: {
                    Text("Card number")
                } footer: {
                    Text("Only the last 4 digits — never the full number. Lets Mizan auto-match a bank SMS that names \"…\(last4.isEmpty ? "1234" : last4)\" to this account.")
                }
                Section {
                    Button("Add") {
                        onCreate(name.trimmingCharacters(in: .whitespaces), type,
                                 last4.isEmpty ? nil : last4)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Add account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
