import SwiftUI
import GRDB
import Budgeting
import Forecasting
import LLM
import MizanSecurity
import Persistence
import UI

// MARK: - SettingsView (blueprint Phase 3.1 + FX rates + logout)
// Account & category management and the manual FX-rate table. Simple
// list/form CRUD over the Phase 1 tables — nothing here bypasses
// DatabaseManager.
// MARK: - Settings menu sections (the "Profile Page" tile hub)

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case accounts, categories, currency, budget, mizanAI, data, appearance, privacy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .categories: return "Categories"
        case .currency: return "Currency"
        case .budget: return "Budget"
        case .mizanAI: return "Mizan AI"
        case .data: return "Data"
        case .appearance: return "Appearance"
        case .privacy: return "Privacy"
        }
    }
    var subtitle: String {
        switch self {
        case .accounts: return "Balances & cards"
        case .categories: return "Names & colors"
        case .currency: return "Rates & price lookup"
        case .budget: return "Reset day & cycle"
        case .mizanAI: return "Your own AI server"
        case .data: return "Export, import, backup"
        case .appearance: return "Theme & widgets"
        case .privacy: return "Lock & sign out"
        }
    }
    var icon: String {
        switch self {
        case .accounts: return "building.columns.fill"
        case .categories: return "square.grid.2x2.fill"
        case .currency: return "dollarsign.circle.fill"
        case .budget: return "calendar"
        case .mizanAI: return "sparkles"
        case .data: return "externaldrive.fill"
        case .appearance: return "paintbrush.fill"
        case .privacy: return "lock.shield.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var lockViewModel: AppLockViewModel
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var model = SettingsViewModel()
    @State private var showProfileEdit = false
    @State private var colorCategory: Persistence.Category?
    @State private var deleteCategory: Persistence.Category?
    @AppStorage(ThemeChoice.storageKey) private var themeChoiceRaw = ThemeChoice.system.rawValue
    @AppStorage(MizanAISettings.enabledKey) private var aiEnabled = false
    @AppStorage(MizanAISettings.serverURLKey) private var aiServerURL = ""
    @AppStorage(MizanAISettings.modelKey) private var aiModel = ""
    @State private var aiTestResult: String?
    @State private var aiTesting = false
    @State private var showEraseConfirm = false
    @AppStorage(BudgetCycle.startDayKey) private var budgetCycleDay = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    profileCard
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(SettingsSection.allCases) { section in
                            NavigationLink(value: section) { tile(section) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(15)
            }
            .kitBackground()
            .dismissableKeyboard()
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsSection.self) { sectionPage($0) }
            .task { model.load() }
            .sheet(item: $colorCategory) { category in
                CategoryColorSheet(categoryName: category.name) {
                    model.load()
                    NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
                }
            }
            .sheet(item: $deleteCategory) { category in
                CategoryDeleteSheet(category: category,
                                    others: model.categories.filter { $0.id != category.id }) { target in
                    model.deleteCategory(category, movingTo: target)
                }
            }
            .sheet(isPresented: $showProfileEdit) { ProfileFormView(isOnboarding: false) }
            .sheet(isPresented: $model.showNewAccount) {
                NewAccountView { name, type, last4 in
                    model.addAccount(name: name, type: type, last4: last4)
                }
            }
            .alert("Settings", isPresented: .constant(model.message != nil)) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
            // Irreversible: wipes every transaction, account, budget, goal and
            // bill, then re-seeds the empty starter set. Behind an explicit,
            // destructive confirmation.
            .alert("Erase all data?", isPresented: $showEraseConfirm) {
                Button("Erase everything", role: .destructive) { model.eraseAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every transaction, account, budget, goal and bill on this device. It cannot be undone. Export a backup first if you might want your data back.")
            }
            // Backup passphrase: a SEPARATE secret from the device key —
            // this is what makes the backup restorable on any device.
            .alert("Backup passphrase", isPresented: $model.showBackupPassphrase) {
                SecureField("Passphrase", text: $model.backupPassphrase)
                Button("Export") { model.exportEncryptedBackup(keyManager: lockViewModel.keyManager) }
                Button("Cancel", role: .cancel) { model.backupPassphrase = "" }
            } message: {
                Text("Choose a strong passphrase — anyone with the file AND the passphrase can read your data. There is no recovery if you forget it.")
            }
            .fileImporter(isPresented: $model.showSignalImporter, allowedContentTypes: [.json]) { result in
                model.importSignals(result)
            }
            // Share sheet for whichever export was produced.
            .sheet(item: $model.shareURL) { wrapper in
                ShareSheet(url: wrapper.url)
            }
            // Ephemeral signal review — never persisted, discarded on close.
            .sheet(isPresented: .constant(!model.signals.isEmpty)) {
                NavigationStack {
                    List(model.signals) { signal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(signal.ticker).font(.headline)
                                Text(signal.signal.rawValue.uppercased())
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(signal.signal == .buy ? AppTheme.accentMint : (signal.signal == .sell ? .red : .gray), in: Capsule())
                                    .foregroundStyle(.black)
                                Spacer()
                                Text("\(Int(signal.confidence * 100))%").font(.caption)
                            }
                            Text(signal.rationale).font(.caption).foregroundStyle(.secondary)
                            Text(signal.timestamp.formatted()).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .navigationTitle("Signals (review only)")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Discard") { model.signals = [] }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cards

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
    }

    // MARK: Menu tiles + section pages

    private func tile(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: section.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(KitTheme.primary, in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 24)
            Text(section.title)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
            Text(section.subtitle)
                .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(16)
        .background(KitTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func sectionPage(_ section: SettingsSection) -> some View {
        ScrollView {
            VStack(spacing: 15) {
                switch section {
                case .accounts:
                    accountsCard
                    KitPrimaryButton("Save changes") { model.saveEdits() }
                case .categories:
                    categoriesCard
                case .currency:
                    ratesCard
                    preferencesCard
                    KitPrimaryButton("Save changes") { model.saveEdits() }
                case .budget:
                    budgetCycleCard
                case .mizanAI:
                    mizanAICard
                case .data:
                    dataCard
                case .appearance:
                    appearanceCard
                case .privacy:
                    privacyCard
                }
            }
            .padding(15)
        }
        .kitBackground()
        .dismissableKeyboard()
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Budget cycle: which day of the month the budget + safe-to-spend reset
    /// (your pay day), plus a one-tap "reset now".
    private var budgetCycleCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                header("Budget cycle")
                Text("Your Home budget, the safe-to-spend widget, and the Buckets rings reset on this day each month. Set it to your pay day.")
                    .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Stepper(value: $budgetCycleDay, in: 1...28) {
                    HStack {
                        Text("Reset day").font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                        Spacer()
                        Text(budgetCycleDay == 1 ? "1st · calendar month" : Self.ordinal(budgetCycleDay))
                            .font(.system(size: 14)).foregroundStyle(KitTheme.textSecondary)
                    }
                }
                .tint(KitTheme.primary)
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                Button {
                    budgetCycleDay = min(28, max(1, Calendar.current.component(.day, from: Date())))
                    budgetCycleChanged()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 15)).foregroundStyle(KitTheme.primary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset budget now").font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Text("Start a fresh cycle from today").font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: budgetCycleDay) { _, _ in budgetCycleChanged() }
    }

    /// Refresh Home, Buckets and the widget after the cycle changes.
    private func budgetCycleChanged() {
        NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
        WidgetSnapshotPublisher.refresh()
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (1, 11), (2, 12), (3, 13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix) of the month"
    }

    /// Appearance selector — System / Light / Dark, applied app-wide via
    /// RootView's .preferredColorScheme.
    private var appearanceCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                header("Appearance")
                HStack(spacing: 8) {
                    ForEach(ThemeChoice.allCases) { choice in
                        let selected = themeChoiceRaw == choice.rawValue
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { themeChoiceRaw = choice.rawValue }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: choice.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(choice.label)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(selected ? .black : KitTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selected ? KitTheme.primary : KitTheme.ink.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("System follows your iPhone's light/dark setting.")
                    .font(.system(size: 12)).foregroundStyle(KitTheme.textTertiary)
            }
        }
    }

    /// "Use my own AI server" — a private LAN / Tailscale link to a model
    /// running on the user's own machine (Ollama / LM Studio). Off by
    /// default; the warning makes the privacy tradeoff explicit.
    private var mizanAICard: some View {
        VStack(spacing: 15) {
            KitCard {
                VStack(alignment: .leading, spacing: 12) {
                    header("Mizan AI")
                    Toggle(isOn: $aiEnabled) {
                        Text("Use my AI server")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                    }
                    .tint(KitTheme.primary)
                    Text("""
                        Sends your question — including the money figures Mizan injects — to a model on your OWN computer over your network. \
                        Nothing goes to any third-party cloud. Leave off to keep everything on this phone.
                        """)
                        .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if aiEnabled {
                KitCard {
                    VStack(alignment: .leading, spacing: 14) {
                        aiField("Server URL", "http://192.168.1.20:11434", $aiServerURL, keyboard: .URL)
                        Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                        aiField("Model", "llama3.1", $aiModel, keyboard: .default)
                        Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                        Button {
                            testAIConnection()
                        } label: {
                            HStack(spacing: 8) {
                                if aiTesting { ProgressView() }
                                Text(aiTesting ? "Testing…" : "Test connection")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(KitTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(aiTesting || aiServerURL.isEmpty)
                        if let aiTestResult {
                            Text(aiTestResult)
                                .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Runs Ollama (:11434) or LM Studio (:1234). For access away from home, point this at your Mac's Tailscale address.")
                            .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func aiField(_ label: String, _ placeholder: String, _ text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
            Spacer()
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(KitTheme.textPrimary)
                .frame(maxWidth: 200)
        }
    }

    private func testAIConnection() {
        aiTesting = true
        aiTestResult = nil
        Task {
            defer { aiTesting = false }
            guard let backend = MizanAISettings.makeBackend() else {
                aiTestResult = "Enter a valid http:// server URL first."
                return
            }
            do {
                _ = try await backend.complete(prompt: "Reply with the word: ok")
                aiTestResult = "✓ Connected. Mizan AI is ready."
            } catch {
                aiTestResult = "✕ \(error.localizedDescription)"
            }
        }
    }

    private var privacyCard: some View {
        VStack(spacing: 15) {
            KitCard {
                VStack(alignment: .leading, spacing: 12) {
                    header("Privacy & security")
                    dataRow("Encrypted backup…", "lock.doc") { model.showBackupPassphrase = true }
                    Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                    Text("Your data is encrypted on-device and unlocked with Face ID. Nothing is sent to any server.")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textTertiary)
                }
            }
            logoutButton
        }
    }

    private var profileCard: some View {
        Button { showProfileEdit = true } label: {
            KitCard {
                HStack(spacing: 12) {
                    ProfileAvatar(size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name.isEmpty ? "Set up your profile" : profile.name)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                        Text("Name and photo · stored on this device")
                            .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    }
                    Spacer()
                    Text("Edit").font(.system(size: 13, weight: .semibold)).foregroundStyle(KitTheme.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var accountsCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                header("Accounts & cards")
                VStack(spacing: 0) {
                    ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                        let type = AccountType(rawValue: account.type)
                        HStack(spacing: 12) {
                            Image(systemName: HomeViewModel.walletIcon(type))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HomeViewModel.walletColor(type))
                                .frame(width: 36, height: 36)
                                .background(HomeViewModel.walletColor(type).opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                                Text(type?.displayName ?? account.type).font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                            }
                            Spacer()
                            AmountTextField(text: model.balanceBinding(for: account),
                                            font: .system(size: 15, weight: .semibold).monospacedDigit(),
                                            alignment: .trailing)
                                .frame(width: 100)
                        }
                        .padding(.vertical, 10)
                        if index < model.accounts.count - 1 {
                            Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                        }
                    }
                }
                Button { model.showNewAccount = true } label: {
                    Label("Add account or card", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.primary)
                }
                .buttonStyle(.plain)
                if !model.accounts.isEmpty {
                    Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                    HStack {
                        Text("Default account for new transactions")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(model.accounts) { account in
                                Button(account.name) { model.setDefaultAccount(account.id) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(model.defaultAccountName).font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                            }
                            .foregroundStyle(KitTheme.primary)
                        }
                    }
                }
                Text("Net worth = the sum of these balances. Every captured transaction keeps it updated. Current total: \(model.netWorthLine)")
                    .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
            }
        }
    }

    private var categoriesCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    header("Categories")
                    Spacer()
                    Text("tap to recolor · hold to delete")
                        .font(.system(size: 10)).foregroundStyle(KitTheme.textTertiary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(model.categories.enumerated()), id: \.element.id) { index, category in
                        Button { colorCategory = category } label: {
                            HStack(spacing: 10) {
                                Circle().fill(KitTheme.categoryColor(category.name)).frame(width: 14, height: 14)
                                Text(category.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                                Spacer()
                                Text(category.bucket.rawValue).font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { colorCategory = category } label: { Label("Change color", systemImage: "paintpalette") }
                            Button(role: .destructive) { deleteCategory = category } label: { Label("Delete category", systemImage: "trash") }
                        }
                        if index < model.categories.count - 1 {
                            Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("New category", text: $model.newCategoryName)
                        .font(.system(size: 14)).foregroundStyle(KitTheme.textPrimary)
                    Picker("", selection: $model.newCategoryBucket) {
                        ForEach(CategoryBucket.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().tint(KitTheme.primary)
                    Button("Add") { model.addCategory() }
                        .font(.system(size: 14, weight: .semibold)).tint(KitTheme.primary)
                        .disabled(model.newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }

    private var ratesCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                header("Exchange rates (EGP per unit)")
                VStack(spacing: 0) {
                    ForEach(Array(model.rates.enumerated()), id: \.element.id) { index, rate in
                        HStack {
                            Text(rate.currencyCode).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            TextField("0", text: model.rateBinding(for: rate))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(KitTheme.textPrimary).frame(width: 100)
                                .disabled(rate.currencyCode == "EGP")
                        }
                        .padding(.vertical, 10)
                        if index < model.rates.count - 1 {
                            Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                        }
                    }
                }
                Text("Manual by design — Mizan makes no network requests. Update these when rates move.")
                    .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
            }
        }
    }

    private var preferencesCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Online price lookup", isOn: $model.priceFetchEnabled)
                    .font(.system(size: 14, weight: .medium))
                    .tint(KitTheme.primary)
                Text("The one network exception: a per-ticker public price quote, fetched only when you tap refresh in Investments. Off = zero network requests.")
                    .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
            }
        }
    }

    private var dataCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                header("Data")
                dataRow("Export transactions (CSV)", "tablecells") { model.exportCSV() }
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                dataRow("Export everything (JSON)", "curlybraces.square") { model.exportJSON() }
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                dataRow("Encrypted backup…", "lock.doc") { model.showBackupPassphrase = true }
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                dataRow("Import stock signals…", "tray.and.arrow.down") { model.showSignalImporter = true }
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                Button { showEraseConfirm = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(KitTheme.expense).frame(width: 24)
                        Text("Erase all data…").font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.expense)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dataRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(KitTheme.primary).frame(width: 24)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var logoutButton: some View {
        Button(role: .destructive) { lockViewModel.lock() } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("Log out")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(KitTheme.expense)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(KitTheme.expense.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// Minimal UIActivityViewController wrapper for handing export files off.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable box so .sheet(item:) can present a bare URL.
struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - CategoryColorSheet

struct CategoryColorSheet: View {
    let categoryName: String
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick a color for \(categoryName)")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(KitTheme.categoryPaletteChoices, id: \.self) { hex in
                            Button {
                                KitTheme.setCategoryColor(hex, for: categoryName)
                                onDone(); dismiss()
                            } label: {
                                Circle().fill(Color(hexValue: hex))
                                    .frame(height: 46)
                                    .overlay(Circle().strokeBorder(KitTheme.ink.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        KitTheme.setCategoryColor(nil, for: categoryName)
                        onDone(); dismiss()
                    } label: {
                        Text("Reset to automatic")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(KitTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .kitBackground()
            .navigationTitle("Category color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(KitTheme.primary) } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - CategoryDeleteSheet

struct CategoryDeleteSheet: View {
    let category: Persistence.Category
    let others: [Persistence.Category]
    let onConfirm: (Persistence.Category) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var target: Persistence.Category?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Deleting “\(category.name)” moves its transactions to another category. This can't be undone.")
                        .font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                    if others.isEmpty {
                        KitCard { Text("Add another category first.").font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary) }
                    } else {
                        KitCard {
                            VStack(spacing: 0) {
                                ForEach(Array(others.enumerated()), id: \.element.id) { index, other in
                                    Button { target = other } label: {
                                        HStack(spacing: 10) {
                                            Circle().fill(KitTheme.categoryColor(other.name)).frame(width: 12, height: 12)
                                            Text(other.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                                            Spacer()
                                            if target?.id == other.id {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(KitTheme.primary)
                                            }
                                        }
                                        .padding(.vertical, 10).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if index < others.count - 1 { Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5) }
                                }
                            }
                        }
                    }
                    KitPrimaryButton("Move transactions & delete") {
                        if let target { onConfirm(target); dismiss() }
                    }
                    .disabled(target == nil)
                    .opacity(target == nil ? 0.4 : 1)
                }
                .padding(20)
            }
            .kitBackground()
            .navigationTitle("Delete category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(KitTheme.primary) } }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var categories: [Persistence.Category] = []
    @Published var rates: [FxRate] = []
    @Published var balanceTexts: [Int64: String] = [:]
    @Published var rateTexts: [String: String] = [:]
    @Published var newCategoryName = ""
    @Published var newCategoryBucket: CategoryBucket = .flexible
    @Published var showNewAccount = false
    @Published var message: String?
    @Published var defaultAccountId: Int64?
    /// Live "sum of balances" line for the accounts footer.
    var netWorthLine: String {
        let total = accounts.reduce(Decimal(0)) { $0 + $1.balance } // Display-only; assumes EGP accounts.
        return Money.egp(total)
    }
    var defaultAccountName: String {
        accounts.first { $0.id == defaultAccountId }?.name ?? (accounts.first?.name ?? "—")
    }

    func setDefaultAccount(_ id: Int64?) {
        defaultAccountId = id
        AppPreferences.setDefaultAccountId(id)
    }

    /// Delete a category, first moving its transactions and recurring series to
    /// `target` so no history is orphaned. Its allocations are removed.
    func deleteCategory(_ category: Persistence.Category, movingTo target: Persistence.Category) {
        guard let from = category.id, let to = target.id, from != to else { return }
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE \"transaction\" SET categoryId = ? WHERE categoryId = ?", arguments: [to, from])
                try db.execute(sql: "UPDATE recurringSeries SET categoryId = ? WHERE categoryId = ?", arguments: [to, from])
                try CategoryAllocation.filter(GRDB.Column("categoryId") == from).deleteAll(db)
                _ = try Persistence.Category.deleteOne(db, id: from)
            }
            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
            load()
        } catch { message = error.localizedDescription }
    }
    /// The narrow network exception's master switch — default OFF.
    @AppStorage("priceFetchEnabled") var priceFetchEnabled = false
    @Published var showBackupPassphrase = false
    @Published var backupPassphrase = ""
    @Published var showSignalImporter = false
    @Published var shareURL: ShareURL?
    @Published var signals: [StockSignalImport.Signal] = []

    private let exporter = ExportService()

    func exportCSV() {
        do {
            let csv = try exporter.transactionsCSV()
            let url = try exporter.writeExportFile(Data(csv.utf8), name: "mizan_transactions.csv")
            shareURL = ShareURL(url: url)
        } catch { message = error.localizedDescription }
    }

    func exportJSON() {
        do {
            let url = try exporter.writeExportFile(try exporter.fullJSON(), name: "mizan_export.json")
            shareURL = ShareURL(url: url)
        } catch { message = error.localizedDescription }
    }

    /// Wipes every user table and re-seeds the empty starter set, so the app
    /// returns to a clean first-run state (seeded accounts/categories, zero
    /// transactions). Refreshes the dashboard and widgets afterward.
    func eraseAllData() {
        do {
            try DatabaseManager.shared.eraseAllData()
            try StarterDataBootstrapper().seedIfNeeded()
            load()
            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
            WidgetSnapshotPublisher.refresh()
            message = "All data erased. Mizan is back to a clean start."
        } catch {
            message = error.localizedDescription
        }
    }

    func exportEncryptedBackup(keyManager: KeychainKeyManager) {
        defer { backupPassphrase = "" }
        do {
            let url = try BackupService(keyManager: keyManager)
                .exportEncryptedBackup(passphrase: backupPassphrase)
            shareURL = ShareURL(url: url)
        } catch { message = error.localizedDescription }
    }

    func importSignals(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // Security-scoped access for files picked outside the sandbox.
            guard url.startAccessingSecurityScopedResource() else {
                message = "Could not open that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            signals = try StockSignalImport.parse(try Data(contentsOf: url))
        } catch { message = error.localizedDescription }
    }

    func balanceBinding(for account: Account) -> Binding<String> {
        let key = account.id ?? -1
        return Binding(
            get: { self.balanceTexts[key] ?? "" },
            set: { self.balanceTexts[key] = $0 }
        )
    }

    func rateBinding(for rate: FxRate) -> Binding<String> {
        Binding(
            get: { self.rateTexts[rate.currencyCode] ?? "" },
            set: { self.rateTexts[rate.currencyCode] = $0 }
        )
    }

    func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            (accounts, categories, rates) = try dbQueue.read { db in
                (
                    try Account.order(GRDB.Column("name")).fetchAll(db),
                    try Persistence.Category.order(GRDB.Column("name")).fetchAll(db),
                    try FxRate.order(GRDB.Column("currencyCode")).fetchAll(db)
                )
            }
            for account in accounts { balanceTexts[account.id ?? -1] = AmountFormat.grouped(account.balance) }
            for rate in rates { rateTexts[rate.currencyCode] = "\(rate.rateToEGP)" }
            defaultAccountId = AppPreferences.resolvedDefaultAccountId(in: accounts)
        } catch { message = error.localizedDescription }
    }

    private func decimal(_ text: String?) -> Decimal? {
        guard let text else { return nil }
        return Decimal(
            string: text.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    func saveEdits() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.write { db in
                for var account in try Account.fetchAll(db) {
                    if let value = AmountFormat.decimal(self.balanceTexts[account.id ?? -1] ?? ""),
                       value != account.balance {
                        account.balance = value
                        try account.update(db)
                    }
                }
                for var rate in try FxRate.fetchAll(db) where rate.currencyCode != "EGP" {
                    if let value = self.decimal(self.rateTexts[rate.currencyCode]),
                       value > 0, value != rate.rateToEGP {
                        rate.rateToEGP = value
                        rate.updatedAt = Date()
                        try rate.update(db)
                    }
                }
            }
            load()
            message = "Saved."
        } catch { message = error.localizedDescription }
    }

    func addAccount(name: String, type: AccountType, last4: String? = nil) {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.write { db in
                var account = Account(name: name, type: type.rawValue, currency: "EGP",
                                      balance: 0, last4: last4)
                try account.insert(db)
            }
            load()
        } catch { message = error.localizedDescription }
    }

    func addCategory() {
        do {
            let name = newCategoryName.trimmingCharacters(in: .whitespaces)
            let bucket = newCategoryBucket
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.write { db in
                var category = Persistence.Category(name: name, bucket: bucket)
                try category.insert(db)
            }
            newCategoryName = ""
            load()
        } catch { message = error.localizedDescription }
    }
}
