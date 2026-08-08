import SwiftUI
import GRDB
import Budgeting
import Capture
import Persistence
import UI

// MARK: - TransactionsView (blueprint Phases 3.4 + 3.5)
// Search (merchant text, category, account, date handled by month steps)
// over the full history, with swipe-to-edit/delete. Editing reuses the
// same TransactionFormView as every capture flow.
struct TransactionsView: View {
    @StateObject private var model = TransactionsViewModel()
    @State private var editing: Persistence.Transaction?
    @State private var editForm = TransactionFormData()
    @State private var filter: TxFilter = .all

    enum TxFilter: String, CaseIterable, Identifiable {
        case all = "All", income = "Income", expenses = "Expenses"
        var id: String { rawValue }
    }

    /// Transactions after the direction filter, grouped into day sections
    /// (newest day first, newest first within a day).
    private var grouped: [(day: Date, items: [Persistence.Transaction])] {
        let calendar = Calendar.current
        let items = model.transactions.filter {
            switch filter {
            case .all: return true
            case .income: return $0.direction == .income
            case .expenses: return $0.direction == .expense
            }
        }
        let dict = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { day in
            (day: day, items: (dict[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Filter", selection: $filter) {
                    ForEach(TxFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            kitRow(transaction)
                                .listRowBackground(KitTheme.card)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        model.delete(transaction)
                                    } label: { Label("Delete", systemImage: "trash") }
                                    Button {
                                        startEditing(transaction)
                                    } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(KitTheme.primary)
                                }
                        }
                    } header: {
                        Text(group.day.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(KitTheme.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .dismissableKeyboard()
            .scrollContentBackground(.hidden)
            .background(KitTheme.canvas.ignoresSafeArea())
            .navigationTitle("Transactions")
            .searchable(text: $model.searchText, prompt: "Search merchant…")
            .task { model.load() }
            .onChange(of: model.searchText) { _, _ in model.applyFilters() }
            .sheet(item: $editing) { transaction in
                NavigationStack {
                    TransactionFormView(
                        form: $editForm,
                        accounts: model.accounts,
                        categories: model.categories,
                        saveLabel: "Save changes"
                    ) {
                        model.saveEdit(of: transaction, form: editForm)
                        editing = nil
                    }
                    .navigationTitle("Edit transaction")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editing = nil }
                        }
                    }
                }
            }
        }
    }

    private func kitRow(_ transaction: Persistence.Transaction) -> some View {
        let income = transaction.direction == .income
        let category = model.categoryName(transaction.categoryId)
        return HStack(spacing: 12) {
            Image(systemName: WalletView.icon(for: category))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(KitTheme.categoryColor(category))
                .frame(width: 44, height: 44)
                .background(KitTheme.categoryColor(category).opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant ?? category)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                Text(category)
                    .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(income ? "+" : "−")\(Money.amount(transaction.amount)) \(transaction.currency)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(income ? KitTheme.income : KitTheme.expense)
                Text(transaction.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func startEditing(_ transaction: Persistence.Transaction) {
        editForm = TransactionFormData(
            amountText: "\(transaction.amount)",
            accountId: transaction.accountId,
            categoryId: transaction.categoryId,
            date: transaction.date,
            merchant: transaction.merchant ?? "",
            currency: transaction.currency
        )
        editing = transaction
    }
}

@MainActor
final class TransactionsViewModel: ObservableObject {
    @Published var transactions: [Persistence.Transaction] = []
    @Published var accounts: [Account] = []
    @Published var categories: [Persistence.Category] = []
    @Published var searchText = ""
    @Published var filterCategoryId: Int64?
    @Published var filterAccountId: Int64?

    private let search = TransactionSearchService()
    private let writer = TransactionWriter()
    private var categoryNames: [Int64: String] = [:]

    func categoryName(_ id: Int64) -> String { categoryNames[id] ?? "?" }

    func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            (accounts, categories) = try dbQueue.read { db in
                (
                    try Account.order(GRDB.Column("name")).fetchAll(db),
                    try Persistence.Category.order(GRDB.Column("name")).fetchAll(db)
                )
            }
            categoryNames = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                category.id.map { ($0, category.name) }
            })
            applyFilters()
        } catch { transactions = [] }
    }

    func applyFilters() {
        let filter = TransactionSearchService.Filter(
            text: searchText.isEmpty ? nil : searchText,
            categoryId: filterCategoryId,
            accountId: filterAccountId
        )
        transactions = (try? search.search(filter)) ?? []
    }

    func delete(_ transaction: Persistence.Transaction) {
        guard let id = transaction.id else { return }
        try? writer.delete(transactionId: id)
        applyFilters()
        NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
    }

    func saveEdit(of transaction: Persistence.Transaction, form: TransactionFormData) {
        guard let id = transaction.id,
              let amount = form.amount,
              let accountId = form.accountId,
              let categoryId = form.categoryId else { return }
        let draft = TransactionDraft(
            accountId: accountId,
            categoryId: categoryId,
            amount: amount,
            currency: form.currency,
            date: form.date,
            merchant: form.merchant.isEmpty ? nil : form.merchant,
            source: transaction.source // Preserved — editing doesn't change provenance.
        )
        try? writer.update(transactionId: id, with: draft)
        applyFilters()
        NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
    }
}
