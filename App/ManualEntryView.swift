import SwiftUI
import Persistence
import UI

// MARK: - ManualEntryView (blueprint Phase 2.1)
// Manual path with two conveniences layered on the shared form:
//  - typing a merchant auto-suggests a category (never overwriting one the
//    user picked by hand),
//  - a card/account can be created inline without leaving the flow.
struct ManualEntryView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var form = TransactionFormData()
    @State private var showNewAccount = false
    /// The last category id WE set from a merchant suggestion. If the
    /// current selection differs, the user chose it manually and
    /// auto-suggestion must keep its hands off.
    @State private var lastAutoSuggestion: Int64?

    var body: some View {
        NavigationStack {
            TransactionFormView(
                form: $form,
                accounts: viewModel.accounts,
                categories: viewModel.categories,
                saveLabel: "Save transaction",
                onMerchantChange: { merchant in
                    applyCategorySuggestion(forMerchant: merchant)
                },
                onAddAccount: { showNewAccount = true }
            ) {
                if viewModel.save(form: form, source: .manual) {
                    dismiss()
                }
            }
            .navigationTitle("Manual entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showNewAccount) {
                NewAccountView { name, type, last4 in
                    if let newId = viewModel.createAccount(name: name, type: type, last4: last4) {
                        form.accountId = newId
                    }
                }
            }
            .onAppear {
                form.accountId = form.accountId ?? AppPreferences.resolvedDefaultAccountId(in: viewModel.accounts)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    /// Auto-fill the category from the merchant, but only while the field
    /// is untouched or still holding our previous suggestion — a manual
    /// choice always wins over the matcher.
    private func applyCategorySuggestion(forMerchant merchant: String) {
        let userPickedManually = form.categoryId != nil && form.categoryId != lastAutoSuggestion
        guard !userPickedManually else { return }
        guard let suggestion = viewModel.suggestedCategoryId(forMerchant: merchant) else { return }
        // Don't churn the picker to "Uncategorized" while typing — only
        // positive matches are worth auto-applying.
        if suggestion != viewModel.uncategorizedId {
            form.categoryId = suggestion
            lastAutoSuggestion = suggestion
        }
    }
}
