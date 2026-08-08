import SwiftUI
import Forecasting
import Persistence
import UI

// MARK: - InvestView (blueprint Phase 5.3)
// Holdings with FIFO cost-basis lots, unrealized gains, the manual
// asset-class breakdown, and price refresh — manual entry always works;
// the online lookup only fires if the Settings toggle is on, and only on
// explicit tap (never a timer).
struct InvestView: View {
    @StateObject private var model = InvestViewModel()
    @AppStorage("priceFetchEnabled") private var priceFetchEnabled = false

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                if model.hasPositions { portfolioCard }
                if !model.breakdown.isEmpty { breakdownCard }
                positionsSection
                newHoldingCard
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(15)
        }
        .kitBackground()
        .dismissableKeyboard()
        .navigationTitle("Investments")
        .task { model.load() }
        .alert("Buy lot — \(model.lotPrompt?.holding.ticker ?? "")",
               isPresented: .constant(model.lotPrompt != nil)) {
            TextField("Quantity", text: $model.lotQuantity).keyboardType(.decimalPad)
            TextField("Price per unit", text: $model.lotPrice).keyboardType(.decimalPad)
            Button("Add") { model.addLot() }
            Button("Cancel", role: .cancel) { model.lotPrompt = nil }
        }
    }

    // MARK: - Cards

    private var portfolioCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio value")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                Text(model.totalValueText)
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(KitTheme.textPrimary)
                HStack(spacing: 6) {
                    Image(systemName: model.gainPositive ? "arrow.up.right" : "arrow.down.right")
                    Text("\(model.totalGainText) unrealized")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.gainPositive ? KitTheme.income : KitTheme.expense)
            }
        }
    }

    private var breakdownCard: some View {
        let total = max(model.breakdown.reduce(0) { $0 + $1.valueDouble }, 0.0001)
        return KitCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("By asset class").font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                ForEach(model.breakdown, id: \.assetClass) { slice in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(slice.assetClass).font(.system(size: 13, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Text("\(Int((slice.valueDouble / total * 100).rounded()))%")
                                .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                        }
                        KitProgressBar(fraction: slice.valueDouble / total,
                                       tint: KitTheme.categoryColor(slice.assetClass))
                    }
                }
            }
        }
    }

    private var positionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Positions").font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                Spacer()
            }
            if model.positions.isEmpty {
                KitCard {
                    Text("No holdings yet — add your first below.")
                        .font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                }
            } else {
                ForEach(model.positions) { position in positionCard(position) }
            }
        }
    }

    private func positionCard(_ position: InvestmentService.Position) -> some View {
        KitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(position.holding.ticker)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Text(position.holding.assetClass)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(KitTheme.primary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(KitTheme.primary.opacity(0.12), in: Capsule())
                    Spacer()
                    if priceFetchEnabled {
                        Button { model.refreshPrice(position, enabled: priceFetchEnabled) } label: {
                            Image(systemName: "arrow.clockwise").foregroundStyle(KitTheme.primary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Text("\(position.quantity) units · basis \(Money.amount(position.costBasis)) \(position.holding.currency)")
                    .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                if let gain = position.unrealizedGain, let value = position.marketValue {
                    Text("value \(Money.amount(value)) · unrealized \(gain >= 0 ? "+" : "")\(Money.amount(gain)) \(position.holding.currency)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(gain >= 0 ? KitTheme.income : KitTheme.expense)
                } else {
                    Text("no current price — refresh or set one below")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textTertiary)
                }
                HStack(spacing: 10) {
                    TextField("Price", text: model.priceBinding(for: position))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 14).monospacedDigit()).foregroundStyle(KitTheme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(KitTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                        .frame(width: 110)
                    Button("Set") { model.setManualPrice(position) }
                        .font(.system(size: 13, weight: .semibold)).tint(KitTheme.primary)
                    Spacer()
                    Button("Buy lot") { model.lotPrompt = position }
                        .font(.system(size: 13, weight: .semibold)).tint(KitTheme.primary)
                }
            }
        }
    }

    private var newHoldingCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("New holding").font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                HStack(spacing: 10) {
                    TextField("Ticker", text: $model.newTicker)
                        .foregroundStyle(KitTheme.textPrimary).frame(width: 80)
                    TextField("Asset class", text: $model.newAssetClass)
                        .foregroundStyle(KitTheme.textPrimary)
                    TextField("CCY", text: $model.newCurrency)
                        .foregroundStyle(KitTheme.textPrimary).frame(width: 56)
                }
                .font(.system(size: 14))
                Button { model.addHolding() } label: {
                    Text("Add holding")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(KitTheme.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.newTicker.isEmpty || model.newAssetClass.isEmpty)
            }
        }
    }
}

@MainActor
final class InvestViewModel: ObservableObject {
    struct BreakdownSlice {
        let assetClass: String
        let valueDouble: Double
    }

    @Published var positions: [InvestmentService.Position] = []
    @Published var breakdown: [BreakdownSlice] = []
    /// Portfolio summary (raw sums across holdings — assumes a single reporting
    /// currency; mixed-currency portfolios are summed numerically for a rough
    /// headline, with the per-position rows below showing exact figures).
    @Published var totalValueText = "—"
    @Published var totalGainText = "—"
    @Published var gainPositive = true
    @Published var hasPositions = false
    @Published var priceTexts: [Int64: String] = [:]
    @Published var newTicker = ""
    @Published var newAssetClass = ""
    @Published var newCurrency = "USD"
    @Published var lotPrompt: InvestmentService.Position?
    @Published var lotQuantity = ""
    @Published var lotPrice = ""
    @Published var message: String?

    private let service = InvestmentService()
    private let fetcher = PriceFetchService()

    func priceBinding(for position: InvestmentService.Position) -> Binding<String> {
        let key = position.holding.id ?? -1
        return Binding(
            get: { self.priceTexts[key] ?? "" },
            set: { self.priceTexts[key] = $0 }
        )
    }

    func load() {
        do {
            positions = try service.positions()
            breakdown = try service.assetClassBreakdown().map {
                BreakdownSlice(assetClass: $0.assetClass, valueDouble: NSDecimalNumber(decimal: $0.value).doubleValue)
            }
            hasPositions = !positions.isEmpty
            let totalValue = positions.reduce(Decimal(0)) { $0 + ($1.marketValue ?? $1.costBasis) }
            let totalGain = positions.reduce(Decimal(0)) { $0 + ($1.unrealizedGain ?? 0) }
            totalValueText = HomeViewModel.money(totalValue)
            gainPositive = totalGain >= 0
            totalGainText = "\(totalGain >= 0 ? "+" : "")\(HomeViewModel.money(totalGain))"
        } catch { message = error.localizedDescription }
    }

    func addHolding() {
        do {
            _ = try service.addHolding(ticker: newTicker, assetClass: newAssetClass, currency: newCurrency)
            newTicker = ""; newAssetClass = ""
            load()
        } catch { message = error.localizedDescription }
    }

    func addLot() {
        defer { lotPrompt = nil; lotQuantity = ""; lotPrice = "" }
        guard let position = lotPrompt, let id = position.holding.id,
              let quantity = Decimal(string: lotQuantity, locale: Locale(identifier: "en_US_POSIX")),
              let price = Decimal(string: lotPrice, locale: Locale(identifier: "en_US_POSIX")) else { return }
        do {
            try service.addLot(holdingId: id, quantity: quantity, purchasePrice: price, purchaseDate: Date())
            load()
        } catch { message = error.localizedDescription }
    }

    func setManualPrice(_ position: InvestmentService.Position) {
        guard let id = position.holding.id,
              let price = Decimal(string: priceTexts[id] ?? "", locale: Locale(identifier: "en_US_POSIX")),
              price > 0 else { return }
        try? service.updateCurrentPrice(holdingId: id, price: price)
        load()
    }

    func refreshPrice(_ position: InvestmentService.Position, enabled: Bool) {
        guard let id = position.holding.id else { return }
        let ticker = position.holding.ticker
        Task {
            do {
                let price = try await fetcher.fetchPrice(ticker: ticker, enabled: enabled)
                try service.updateCurrentPrice(holdingId: id, price: price)
                load()
            } catch { message = error.localizedDescription }
        }
    }
}
