import SwiftUI
import GRDB
import Persistence
import UI

// Raw form fields for a new bank certificate, grouped so the view model's
// add function takes one value.
struct CertificateDraft {
    var name: String
    var bankName: String
    var principal: String
    var monthlyInterest: String
    var startDate: Date
    var maturityDate: Date
    var accountId: Int64?
}

// MARK: - NewCertificateView
// Add-certificate form for the Bills tab's Certificates sub-tab. Captures
// the monthly interest, the maturity date, and the account the interest
// deposits into (so "Log interest" can credit the right balance).
struct NewCertificateView: View {
    @ObservedObject var model: BillsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bankName = ""
    @State private var principal = ""
    @State private var monthlyInterest = ""
    @State private var startDate = Date()
    @State private var maturityDate = Calendar.current.date(byAdding: .year, value: 3, to: Date()) ?? Date()
    @State private var accountId: Int64?
    @State private var accounts: [Account] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Certificate") {
                    TextField("Name (e.g. NBE 3-year)", text: $name)
                    TextField("Bank (optional)", text: $bankName)
                    TextField("Principal (EGP)", text: $principal).keyboardType(.decimalPad)
                    TextField("Monthly interest (EGP)", text: $monthlyInterest).keyboardType(.decimalPad)
                }
                Section {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Maturity date", selection: $maturityDate, displayedComponents: .date)
                }
                Section {
                    Picker("Deposits to", selection: $accountId) {
                        Text("None").tag(Int64?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Int64?.some(account.id ?? -1))
                        }
                    }
                } footer: {
                    Text("The account the monthly interest is paid into. Needed so \"Log interest\" credits the right balance.")
                }
                Button("Create") {
                    model.addCertificate(CertificateDraft(
                        name: name.trimmingCharacters(in: .whitespaces),
                        bankName: bankName.trimmingCharacters(in: .whitespaces),
                        principal: principal,
                        monthlyInterest: monthlyInterest,
                        startDate: startDate,
                        maturityDate: maturityDate,
                        accountId: accountId))
                    dismiss()
                }
                .disabled(name.isEmpty || Decimal(string: monthlyInterest) == nil)
            }
            .navigationTitle("New certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                accounts = (try? DatabaseManager.shared.dbQueue().read { db in
                    try Account.order(GRDB.Column("name")).fetchAll(db)
                }) ?? []
                if accountId == nil { accountId = accounts.first?.id }
            }
        }
    }
}
