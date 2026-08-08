import SwiftUI
import GRDB
import Capture
import Persistence
import UI

// MARK: - TransferView
// Move money between two of your accounts/cards. A transfer is recorded as two
// transactions through TransactionWriter (the one place balance math lives):
// an expense on the source account and an income on the destination, both in a
// "Transfer" category. Net worth is unchanged, and because spending aggregates
// net income against expenses per category, the pair cancels to zero in your
// spending — a transfer never looks like spending.
struct TransferView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [Account] = []
    @State private var fromId: Int64?
    @State private var toId: Int64?
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    private let writer = TransactionWriter()

    private var fromAccount: Account? { accounts.first { $0.id == fromId } }
    private var toAccount: Account? { accounts.first { $0.id == toId } }
    private var canTransfer: Bool {
        guard let fromId, let toId, fromId != toId else { return false }
        let amount = AmountFormat.decimal(amountText) ?? 0
        return amount > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    if accounts.count < 2 {
                        KitCard {
                            Text("You need at least two accounts to transfer. Add another in Settings or from the balance editor.")
                                .font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                        }
                    } else {
                        accountsCard
                        amountCard
                        detailsCard
                        KitPrimaryButton("Transfer") { performTransfer() }
                            .disabled(!canTransfer)
                            .opacity(canTransfer ? 1 : 0.4)
                    }
                }
                .padding(15)
            }
            .kitBackground()
            .dismissableKeyboard()
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(KitTheme.primary)
                }
            }
            .task { load() }
            .alert("Transfer", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var accountsCard: some View {
        KitCard {
            VStack(spacing: 14) {
                accountPicker(title: "From", selection: $fromId, exclude: toId)
                HStack {
                    Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                    Button {
                        let f = fromId; fromId = toId; toId = f
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(KitTheme.primary)
                            .frame(width: 30, height: 30)
                            .background(KitTheme.primary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                }
                accountPicker(title: "To", selection: $toId, exclude: fromId)
            }
        }
    }

    private func accountPicker(title: String, selection: Binding<Int64?>, exclude: Int64?) -> some View {
        let selected = accounts.first { $0.id == selection.wrappedValue }
        return Menu {
            ForEach(accounts.filter { $0.id != exclude }) { account in
                Button {
                    selection.wrappedValue = account.id
                } label: {
                    Text("\(account.name) — \(Money.egp(account.balance))")
                }
            }
        } label: {
            HStack(spacing: 12) {
                let type = AccountType(rawValue: selected?.type ?? "")
                Image(systemName: HomeViewModel.walletIcon(type))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HomeViewModel.walletColor(type))
                    .frame(width: 36, height: 36)
                    .background(HomeViewModel.walletColor(type).opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                    Text(selected?.name ?? "Choose account")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
            }
        }
    }

    private var amountCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount").font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AmountTextField(text: $amountText,
                                    font: .system(size: 30, weight: .bold).monospacedDigit(),
                                    color: KitTheme.primary)
                    Text(fromAccount?.currency ?? "EGP")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                }
                if let from = fromAccount, let to = toAccount, from.currency != to.currency {
                    Text("Converted into \(to.currency) on arrival using your exchange rates.")
                        .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                }
            }
        }
    }

    private var detailsCard: some View {
        KitCard {
            VStack(spacing: 14) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .font(.system(size: 14, weight: .medium))
                    .tint(KitTheme.primary)
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                HStack {
                    Text("Note").font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    TextField("optional", text: $note)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14)).foregroundStyle(KitTheme.textPrimary)
                }
            }
        }
    }

    // MARK: Actions

    private func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            accounts = try dbQueue.read { db in
                try Account.order(GRDB.Column("name")).fetchAll(db)
            }
            if fromId == nil { fromId = accounts.first?.id }
            if toId == nil { toId = accounts.dropFirst().first?.id }
        } catch { errorMessage = error.localizedDescription }
    }

    private func performTransfer() {
        guard let fromId, let toId, fromId != toId else {
            errorMessage = "Choose two different accounts."; return
        }
        guard let amount = AmountFormat.decimal(amountText), amount > 0 else {
            errorMessage = "Enter a valid amount."; return
        }
        do {
            let categoryId = try ensureTransferCategory()
            let currency = fromAccount?.currency ?? "EGP"
            let fromName = fromAccount?.name ?? "account"
            let toName = toAccount?.name ?? "account"
            let label = note.trimmingCharacters(in: .whitespaces)

            // One atomic pair — a failure can never debit the source
            // without crediting the destination.
            _ = try writer.insertPair(
                TransactionDraft(
                    accountId: fromId, categoryId: categoryId, amount: amount, currency: currency,
                    date: date, merchant: label.isEmpty ? "Transfer to \(toName)" : label,
                    source: .manual, direction: .expense),
                TransactionDraft(
                    accountId: toId, categoryId: categoryId, amount: amount, currency: currency,
                    date: date, merchant: label.isEmpty ? "Transfer from \(fromName)" : label,
                    source: .manual, direction: .income))

            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Finds the shared "Transfer" category, creating it once if needed.
    private func ensureTransferCategory() throws -> Int64 {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        return try dbQueue.write { db in
            if let existing = try Persistence.Category
                .filter(GRDB.Column("name") == "Transfer").fetchOne(db), let id = existing.id {
                return id
            }
            var category = Persistence.Category(name: "Transfer", bucket: .flexible)
            try category.insert(db)
            guard let id = category.id else { throw TransferError.categoryCreationFailed }
            return id
        }
    }

    private enum TransferError: Error { case categoryCreationFailed }
}
