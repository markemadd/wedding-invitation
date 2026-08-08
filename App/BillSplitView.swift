import SwiftUI
import PhotosUI
import Capture
import Persistence
import UI

// MARK: - BillSplitView
// "Split a bill" — scan a restaurant check or a shared supermarket receipt,
// assign each item to the people at the table, and get everyone's total. OCR is
// reused from ReceiptOCRService; the math is BillSplitCalculator (Capture).
// Nothing is saved unless you tap "Log my share", which writes YOUR portion as
// a normal expense.
struct BillSplitView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case setup, assign }
    private enum SplitMode: String, CaseIterable { case byShare = "By share", evenly = "Split evenly" }
    private let calc = BillSplitCalculator()
    private static let palette: [Color] = [
        Color(hexValue: 0x3DA35D), Color(hexValue: 0x3DB9FF), Color(hexValue: 0xB388FF),
        Color(hexValue: 0xFF9466), Color(hexValue: 0xFFC24B), Color(hexValue: 0xFF5D8F),
        Color(hexValue: 0x2FBF9E), Color(hexValue: 0x8A8DFF),
    ]

    @State private var phase: Phase = .setup
    @State private var peopleCount = 2
    @State private var names: [String] = ["", ""]
    @State private var items: [BillSplitItem] = []
    @State private var currency = "EGP"
    @State private var splitMode: SplitMode = .byShare
    @State private var serviceEnabled = true
    @State private var servicePercent: Decimal = 12
    @State private var taxEnabled = true
    @State private var taxPercent: Decimal = 14
    @State private var receiptTotal: Decimal?
    @State private var meIndex = 0

    @State private var showCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var processing = false
    @State private var ocrError: String?
    @State private var savedNote: String?

    var body: some View {
        NavigationStack {
            ZStack {
                KitTheme.canvas.ignoresSafeArea()
                Group {
                    switch phase {
                    case .setup:  setupPhase
                    case .assign: assignPhase
                    }
                }
                if processing { processingOverlay }
            }
            .navigationTitle("Split a bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if phase == .assign {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add item") { items.append(BillSplitItem(name: "", price: 0)) }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in if let image { runOCR(image) } }.ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, new in
                guard let first = new.first else { return }
                pickerItems = []
                Task { if let img = await loadImage(first) { runOCR(img) } }
            }
        }
    }

    // MARK: Phase 1 — who's splitting

    private var setupPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                KitCard {
                    VStack(alignment: .leading, spacing: 14) {
                        KitSectionHeader("How many are splitting?")
                        Stepper(value: $peopleCount, in: 2...12) {
                            Text("\(peopleCount) people").font(.system(size: 16, weight: .semibold))
                        }
                        .onChange(of: peopleCount) { _, count in syncNames(count) }
                        Divider().opacity(0.4)
                        ForEach(0..<peopleCount, id: \.self) { index in
                            HStack(spacing: 10) {
                                avatar(index).frame(width: 30, height: 30)
                                TextField("Person \(index + 1)", text: binding(forName: index))
                                    .textFieldStyle(.plain)
                            }
                        }
                    }
                }
                KitCard {
                    VStack(alignment: .leading, spacing: 12) {
                        KitSectionHeader("Add the bill")
                        Text("Scan the receipt to pull in items and prices, or add them by hand.")
                            .font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                        Button { showCamera = true } label: {
                            Label("Scan receipt", systemImage: "doc.text.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(KitTheme.primary)
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 1, matching: .images) {
                            Label("Choose a photo", systemImage: "photo").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(KitTheme.primary)
                        Button { items = [BillSplitItem(name: "", price: 0)]; phase = .assign } label: {
                            Text("Enter items manually").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.secondary)
                        if let ocrError { Text(ocrError).font(.caption).foregroundStyle(KitTheme.expense) }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Phase 2 — assign items + results

    private var assignPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modeCard
                if splitMode == .byShare {
                    KitSectionHeader("Items — assign each to a person")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach($items) { $item in itemRow($item) }
                extrasCard
                resultsCard
                actionsCard
                if let savedNote {
                    Text(savedNote).font(.footnote).foregroundStyle(KitTheme.primary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private func itemRow(_ item: Binding<BillSplitItem>) -> some View {
        let unassigned = item.wrappedValue.assignedTo.isEmpty
        return KitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Item", text: item.name).textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                    Spacer(minLength: 8)
                    TextField("0.00", value: item.price, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 84)
                    Text(currency).font(.caption).foregroundStyle(KitTheme.textSecondary)
                    Button { items.removeAll { $0.id == item.wrappedValue.id } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(KitTheme.textSecondary.opacity(0.5))
                    }
                }
                if splitMode == .byShare {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            personChip(label: "Everyone", active: item.wrappedValue.assignedTo.count == peopleCount,
                                       color: KitTheme.primary) { toggleEveryone(item) }
                            ForEach(0..<peopleCount, id: \.self) { index in
                                personChip(label: displayName(index),
                                           active: item.wrappedValue.assignedTo.contains(index),
                                           color: Self.palette[index % Self.palette.count]) { toggle(item, index) }
                            }
                        }
                    }
                    if unassigned {
                        Label("Not assigned yet", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(KitTheme.expense)
                    }
                }
            }
        }
    }

    private var modeCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Split mode", selection: $splitMode) {
                    ForEach(SplitMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(splitMode == .byShare
                     ? "Assign each item to whoever ordered it — everyone pays for just their own items, plus a fair share of tax & tip."
                     : "Skip who-had-what — the whole bill is divided equally between everyone.")
                    .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var extrasCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                KitSectionHeader("Service & tax")
                if let receiptTotal {
                    feeBanner(receiptTotal)
                }
                percentRow(title: "Service charge", isOn: $serviceEnabled, percent: $servicePercent, amount: serviceAmount)
                Divider().opacity(0.3)
                percentRow(title: "VAT / tax", isOn: $taxEnabled, percent: $taxPercent, amount: taxAmount)
                Text("Ordering to-go? Turn VAT off — takeaway usually isn't charged the 14%.")
                    .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if computedExtra > 0 {
                    Divider().opacity(0.4)
                    HStack {
                        Text("Added to the bill").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KitTheme.textSecondary)
                        Spacer()
                        Text(money(computedExtra)).font(.system(size: 14, weight: .bold)).monospacedDigit()
                    }
                }
            }
        }
    }

    private func feeBanner(_ total: Decimal) -> some View {
        let included = feesLikelyIncluded
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: included ? "checkmark.seal.fill" : "info.circle.fill")
                .foregroundStyle(included ? KitTheme.primary : Color(hexValue: 0xFF9466))
            Text(included
                 ? "The items already add up to the receipt total (\(money(total))) — service & tax look included in the prices, so keep them off."
                 : "Items add up to \(money(itemsSum)) but the receipt total is \(money(total)). Service & tax aren't in the prices — add them below.")
                .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background((included ? KitTheme.primary : Color(hexValue: 0xFF9466)).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func percentRow(title: String, isOn: Binding<Bool>,
                            percent: Binding<Decimal>, amount: Decimal) -> some View {
        VStack(spacing: 8) {
            Toggle(isOn: isOn) { Text(title).font(.system(size: 15, weight: .medium)) }
                .tint(KitTheme.primary)
            if isOn.wrappedValue {
                HStack(spacing: 6) {
                    TextField("0", value: percent, format: .number)
                        .keyboardType(.decimalPad).frame(width: 44)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4).background(KitTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    Text("% of items").font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                    Spacer()
                    Text(money(amount)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
    }

    private var resultsCard: some View {
        let totals = computedTotals
        let unassigned = splitMode == .byShare ? calc.unassignedTotal(items) : 0
        return KitCard {
            VStack(alignment: .leading, spacing: 12) {
                KitSectionHeader("Everyone owes")
                ForEach(0..<peopleCount, id: \.self) { index in
                    HStack(spacing: 10) {
                        avatar(index).frame(width: 28, height: 28)
                        Text(displayName(index)).font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text(money(totals.indices.contains(index) ? totals[index] : 0))
                            .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    }
                }
                Divider().opacity(0.4)
                HStack {
                    Text("Total").font(.system(size: 14, weight: .semibold)).foregroundStyle(KitTheme.textSecondary)
                    Spacer()
                    Text(money(totals.reduce(0, +))).font(.system(size: 15, weight: .bold)).monospacedDigit()
                }
                if unassigned > 0 {
                    Label("\(money(unassigned)) of items still unassigned", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(KitTheme.expense)
                }
            }
        }
    }

    private var actionsCard: some View {
        let totals = computedTotals
        return VStack(spacing: 10) {
            Menu {
                ForEach(0..<peopleCount, id: \.self) { index in
                    Button(displayName(index)) { meIndex = index; logMyShare(totals) }
                }
            } label: {
                Label("Log my share as an expense", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(KitTheme.primary)
            Button { UIPasteboard.general.string = breakdownText(totals) } label: {
                Label("Copy breakdown to share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(KitTheme.primary)
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Reading the receipt…").foregroundStyle(.white).font(.subheadline)
            }
            .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Derived

    private var itemsSum: Decimal { items.reduce(Decimal(0)) { $0 + $1.price } }

    // Service on the items subtotal; VAT compounds on (subtotal + service),
    // matching how Egyptian restaurant bills print — but each is toggleable.
    private var serviceAmount: Decimal {
        serviceEnabled ? BillSplitCalculator.round2(itemsSum * servicePercent / 100) : 0
    }
    private var taxAmount: Decimal {
        taxEnabled ? BillSplitCalculator.round2((itemsSum + serviceAmount) * taxPercent / 100) : 0
    }
    private var computedExtra: Decimal { serviceAmount + taxAmount }

    /// True when the scanned item prices already sum to ~the receipt total, i.e.
    /// service/tax are baked into the printed prices and shouldn't be re-added.
    private var feesLikelyIncluded: Bool {
        guard let receiptTotal, itemsSum > 0 else { return false }
        return receiptTotal <= itemsSum * Decimal(string: "1.02")!
    }

    /// Per-person totals for the current mode: itemised (each pays for their
    /// assigned items + a proportional share of service/tax) or an even split.
    private var computedTotals: [Decimal] {
        guard peopleCount > 0 else { return [] }
        switch splitMode {
        case .evenly:
            let each = (itemsSum + computedExtra) / Decimal(peopleCount)
            return calc.rounded(Array(repeating: each, count: peopleCount))
        case .byShare:
            let extras = computedExtra > 0
                ? [BillSplitExtra(label: "Service & tax", amount: computedExtra, mode: .proportional)] : []
            return calc.rounded(calc.totals(items: items, peopleCount: peopleCount, extras: extras))
        }
    }

    private func displayName(_ index: Int) -> String {
        let name = names.indices.contains(index) ? names[index].trimmingCharacters(in: .whitespaces) : ""
        return name.isEmpty ? "Person \(index + 1)" : name
    }

    // MARK: Small views

    private func avatar(_ index: Int) -> some View {
        let color = Self.palette[index % Self.palette.count]
        let initial = String(displayName(index).prefix(1)).uppercased()
        return Circle().fill(color.opacity(0.18)).overlay(
            Text(initial).font(.system(size: 12, weight: .bold)).foregroundStyle(color))
    }

    private func personChip(label: String, active: Bool, color: Color, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? color : color.opacity(0.12), in: Capsule())
                .foregroundStyle(active ? .white : color)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func binding(forName index: Int) -> Binding<String> {
        Binding(get: { names.indices.contains(index) ? names[index] : "" },
                set: { if names.indices.contains(index) { names[index] = $0 } })
    }

    private func syncNames(_ count: Int) {
        if names.count < count { names.append(contentsOf: Array(repeating: "", count: count - names.count)) }
        if meIndex >= count { meIndex = 0 }
    }

    private func toggle(_ item: Binding<BillSplitItem>, _ index: Int) {
        if item.wrappedValue.assignedTo.contains(index) { item.wrappedValue.assignedTo.remove(index) }
        else { item.wrappedValue.assignedTo.insert(index) }
    }

    private func toggleEveryone(_ item: Binding<BillSplitItem>) {
        let all = Set(0..<peopleCount)
        item.wrappedValue.assignedTo = item.wrappedValue.assignedTo == all ? [] : all
    }

    private func logMyShare(_ totals: [Decimal]) {
        guard totals.indices.contains(meIndex), totals[meIndex] > 0 else { return }
        var form = TransactionFormData()
        form.amountText = "\(totals[meIndex])"
        form.merchant = "Split bill"
        form.currency = currency
        form.direction = .expense
        form.accountId = AppPreferences.resolvedDefaultAccountId(in: viewModel.accounts)
        if viewModel.save(form: form, source: .manual) {
            savedNote = "Logged \(money(totals[meIndex])) as your share."
        }
    }

    private func breakdownText(_ totals: [Decimal]) -> String {
        var lines = ["Bill split — \(peopleCount) people"]
        for index in 0..<peopleCount where totals.indices.contains(index) {
            lines.append("• \(displayName(index)): \(money(totals[index]))")
        }
        lines.append("Total: \(money(totals.reduce(0, +)))")
        return lines.joined(separator: "\n")
    }

    private func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: value as NSDecimalNumber) ?? "0.00"
        return "\(currency) \(number)"
    }

    // MARK: OCR

    private func loadImage(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }

    private func runOCR(_ image: UIImage) {
        processing = true; ocrError = nil
        Task {
            defer { processing = false }
            guard let cgImage = image.cgImage else { ocrError = "Couldn't read that photo."; return }
            do {
                let candidates = try ReceiptOCRService().extractCandidates(
                    from: cgImage,
                    orientation: CGImagePropertyOrientation(image.imageOrientation))
                currency = candidates.currency
                items = candidates.lineItems.map { BillSplitItem(name: $0.name, price: $0.price) }
                receiptTotal = candidates.amount
                let scanned = candidates.lineItems.reduce(Decimal(0)) { $0 + $1.price }
                if let total = candidates.amount {
                    // If items already ≈ the receipt total, fees are baked into
                    // the printed prices — default them off so we don't double-add.
                    let inclusive = total <= scanned * Decimal(string: "1.02")!
                    serviceEnabled = !inclusive
                    taxEnabled = !inclusive
                }
                if items.isEmpty { items = [BillSplitItem(name: "", price: 0)] }
                phase = .assign
            } catch {
                ocrError = "Couldn't read that receipt — try a clearer photo or add items by hand."
            }
        }
    }
}
