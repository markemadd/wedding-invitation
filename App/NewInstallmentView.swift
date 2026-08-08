import SwiftUI

// Raw form fields for a new installment plan, grouped so the view model's
// add function takes one value instead of six loose parameters.
struct InstallmentDraft {
    var name: String
    var provider: String
    var monthly: String
    var total: String
    var paid: String
    var startDate: Date
}

// MARK: - NewInstallmentView (ENHANCEMENTS Wave B1)
// The add-plan form for the Bills tab's Installments sub-tab. Split from
// BillsView so that screen stays under the file-length budget.
struct NewInstallmentView: View {
    @ObservedObject var model: BillsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var provider = ""
    @State private var monthly = ""
    @State private var total = ""
    @State private var paid = "0"
    @State private var startDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. iPhone 15)", text: $name)
                TextField("Provider (e.g. ValU)", text: $provider)
                TextField("Monthly amount (EGP)", text: $monthly).keyboardType(.decimalPad)
                TextField("Total installments", text: $total).keyboardType(.numberPad)
                TextField("Already paid", text: $paid).keyboardType(.numberPad)
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                Button("Create") {
                    model.addInstallment(InstallmentDraft(
                        name: name, provider: provider, monthly: monthly,
                        total: total, paid: paid, startDate: startDate
                    ))
                    dismiss()
                }
                .disabled(name.isEmpty || Decimal(string: monthly) == nil || Int(total) == nil)
            }
            .navigationTitle("New installment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
