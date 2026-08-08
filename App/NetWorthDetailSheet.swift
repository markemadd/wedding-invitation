import SwiftUI
import Charts
import UI

// MARK: - NetWorthDetailSheet (ENHANCEMENTS Wave A5)
// The tap target of the net-worth gauge: the split behind the single
// number (spendable vs debt) and a line chart of frozen NetWorthSnapshot
// records. No new table — Account.type and netWorthSnapshot already exist.
struct NetWorthDetailSheet: View {
    let netWorthText: String
    let spendable: String
    let debt: String
    let history: [DashboardViewModel.NetWorthPoint]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard {
                            VStack(spacing: 12) {
                                row("Net worth", netWorthText, emphasized: true)
                                Divider().overlay(KitTheme.ink.opacity(0.1))
                                row("Spendable", spendable, tint: AppTheme.accentMint)
                                row("Debt (cards)", debt, tint: .red)
                            }
                        }
                        if history.count >= 2 {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Net worth over time").font(.headline)
                                    Chart(history) { point in
                                        LineMark(
                                            x: .value("Date", point.date),
                                            y: .value("Net worth", point.value)
                                        )
                                        .foregroundStyle(AppTheme.accentMint)
                                        .interpolationMethod(.catmullRom)
                                    }
                                    .frame(height: 160)
                                }
                            }
                        } else {
                            Text("Net-worth history builds up as snapshots are recorded.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Net worth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, emphasized: Bool = false, tint: Color = .primary) -> some View {
        let baseFont: Font = emphasized ? .headline : .subheadline
        return HStack {
            Text(label)
                .font(baseFont)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(baseFont.monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
