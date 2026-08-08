import SwiftUI
import Persistence

// MARK: - TransactionFormData
// Plain form state, deliberately NOT the Capture module's TransactionDraft:
// the UI package stays independent of capture services, and the amount is
// text-backed so typing stays exact — the string converts straight to
// Decimal on save, never passing through Double (the blueprint's money rule
// applies to the input path too).
public struct TransactionFormData: Equatable {
    /// Currencies offered in the picker. EGP is home; the rest cover
    /// travel receipts (the user's sample set was entirely EUR).
    public static let currencyOptions = ["EGP", "EUR", "USD", "GBP"]

    public var amountText: String
    public var accountId: Int64?
    public var categoryId: Int64?
    public var date: Date
    public var merchant: String
    public var currency: String
    public var direction: TransactionDirection

    public init(
        amountText: String = "",
        accountId: Int64? = nil,
        categoryId: Int64? = nil,
        date: Date = Date(),
        merchant: String = "",
        currency: String = "EGP",
        direction: TransactionDirection = .expense
    ) {
        self.amountText = amountText
        self.accountId = accountId
        self.categoryId = categoryId
        self.date = date
        self.merchant = merchant
        self.currency = currency
        self.direction = direction
    }

    /// Exact Decimal from the typed text; accepts both "." and "," as the
    /// separator (Arabic keyboards produce ","). nil = not yet valid.
    public var amount: Decimal? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    public var isValid: Bool {
        guard let amount, amount > 0 else { return false }
        return accountId != nil && categoryId != nil
    }
}

// MARK: - TransactionFormView (blueprint Phase 2.1)
// The single form used by manual entry, the OCR review step, the voice
// review step — and, in Phase 3, swipe-to-edit. One form means one set of
// validation behaviors everywhere.
public struct TransactionFormView: View {
    @Binding var form: TransactionFormData
    let accounts: [Account]
    let categories: [Persistence.Category]
    let saveLabel: String
    /// Fires as the merchant text changes so the owner can auto-suggest a
    /// category (CategoryMatcher lives in Capture; this view stays free of
    /// service dependencies).
    let onMerchantChange: ((String) -> Void)?
    /// Optional "add a new card/account" affordance under the picker.
    let onAddAccount: (() -> Void)?
    let onSave: () -> Void

    public init(
        form: Binding<TransactionFormData>,
        accounts: [Account],
        categories: [Persistence.Category],
        saveLabel: String = "Save",
        onMerchantChange: ((String) -> Void)? = nil,
        onAddAccount: (() -> Void)? = nil,
        onSave: @escaping () -> Void
    ) {
        self._form = form
        self.accounts = accounts
        self.categories = categories
        self.saveLabel = saveLabel
        self.onMerchantChange = onMerchantChange
        self.onAddAccount = onAddAccount
        self.onSave = onSave
    }

    /// Accounts grouped by type in a fixed, payment-minded order (cash,
    /// bank, debit, credit) so "which card did I pay with" is one glance.
    private var groupedAccounts: [(type: AccountType, accounts: [Account])] {
        AccountType.allCases.compactMap { type in
            let matching = accounts.filter { $0.type == type.rawValue }
            return matching.isEmpty ? nil : (type, matching)
        }
    }

    public var body: some View {
        Form {
            Section("Amount") {
                // Money out vs in (InstaPay receives, refunds). Expense is
                // the default; income raises the month's available money.
                Picker("Direction", selection: $form.direction) {
                    Text("Expense").tag(TransactionDirection.expense)
                    Text("Income").tag(TransactionDirection.income)
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("0.00", text: $form.amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                    Picker("", selection: $form.currency) {
                        ForEach(TransactionFormData.currencyOptions, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                if form.amount == nil && !form.amountText.isEmpty {
                    Text("Enter a valid number")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Paid with") {
                Picker("Account / card", selection: $form.accountId) {
                    Text("Choose…").tag(Int64?.none)
                    ForEach(groupedAccounts, id: \.type) { group in
                        Section(group.type.displayName) {
                            ForEach(group.accounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                    }
                }
                if let onAddAccount {
                    Button {
                        onAddAccount()
                    } label: {
                        Label("Add card or account…", systemImage: "creditcard")
                            .font(.subheadline)
                    }
                }
            }

            Section("Details") {
                TextField("Merchant", text: $form.merchant)
                    .onChange(of: form.merchant) { _, newValue in
                        onMerchantChange?(newValue)
                    }
                Picker("Category", selection: $form.categoryId) {
                    Text("Choose…").tag(Int64?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                DatePicker("Date", selection: $form.date, displayedComponents: [.date, .hourAndMinute])
            }

            Section {
                Button(saveLabel, action: onSave)
                    .disabled(!form.isValid)
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
        }
        .dismissableKeyboard()
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
}
