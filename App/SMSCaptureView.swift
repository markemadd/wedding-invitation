import SwiftUI
import Capture
import UI

// MARK: - SMSCaptureView
// The no-setup SMS path: copy the bank message, paste, review, save.
// Same mandatory review as OCR/voice; the duplicate check runs on save
// via the shared post-save nudge, and a pre-parse warning shows for
// credit-looking messages.
struct SMSCaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var form = TransactionFormData()
    @State private var phase: Phase = .pasting
    @State private var creditWarning = false

    enum Phase { case pasting, reviewing }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pasting: pasteUI
                case .reviewing: reviewUI
                }
            }
            .navigationTitle("Bank SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var pasteUI: some View {
        VStack(spacing: 16) {
            Text("Paste the bank message")
                .font(.headline)
            TextEditor(text: $pastedText)
                .frame(height: 140)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .font(.callout)
            Button {
                if let clipboard = UIPasteboard.general.string {
                    pastedText = clipboard
                }
            } label: {
                Label("Paste from clipboard", systemImage: "doc.on.clipboard")
            }
            Button {
                parse()
            } label: {
                Text("Parse")
                    .font(.headline)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(AppTheme.accentMint, in: Capsule())
                    .foregroundStyle(.black)
            }
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }

    private var reviewUI: some View {
        VStack(spacing: 0) {
            if creditWarning {
                Text("Money IN detected — will be logged as income (raises your available money).")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.accentCream)
                    .padding(8)
            }
            TransactionFormView(
                form: $form,
                accounts: viewModel.accounts,
                categories: viewModel.categories,
                saveLabel: "Confirm & save"
            ) {
                if viewModel.save(form: form, source: .sms) {
                    dismiss()
                }
            }
        }
    }

    private func parse() {
        let parsed = BankSMSParser().parse(pastedText)
        creditWarning = !parsed.isDebit
        form = TransactionFormData()
        if let amount = parsed.amount { form.amountText = "\(amount)" }
        form.currency = parsed.currency
        form.date = parsed.date ?? Date() // The date printed in the SMS wins.
        form.direction = parsed.isDebit ? .expense : .income
        form.merchant = parsed.merchant ?? ""
        // Route to the account whose last-4 the SMS named, else the first.
        if let last4 = parsed.cardLast4,
           let matched = viewModel.accounts.first(where: { $0.last4 == last4 }) {
            form.accountId = matched.id
        } else {
            form.accountId = viewModel.accounts.first?.id
        }
        form.categoryId = viewModel.suggestedCategoryId(forMerchant: parsed.merchant ?? "")
        phase = .reviewing
    }
}
