import SwiftUI
import GRDB
import Budgeting
import Persistence
import LLM
import UI

// MARK: - MizanAIView (ENHANCEMENTS Wave C1)
// The grounded chat screen. Every question is answered from a small
// injected MizanContext of REAL numbers (never hallucinated), and the whole
// screen degrades gracefully to a "Model not available" state when no
// on-device model is bundled — which is the normal state today, since the
// MLX backend + weights are deferred by design.
struct MizanAIView: View {
    @StateObject private var model = MizanAIViewModel()
    @AppStorage("mizanUserName") private var userName = ""
    @State private var showNamePrompt = false

    // The 6 quick prompts from the inspiration; tapping fires immediately.
    private let quickPrompts = [
        "How much did I spend this month?",
        "Can I afford EGP 2000 this weekend?",
        "Show my top categories",
        "Trend over the last 30 days",
        "How am I doing on budgets?",
        "Find expenses over EGP 1000"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        greeting
                        if !model.isAvailable { unavailableBanner }
                        if let last = model.lastSessionSummary {
                            continueRow(last)
                        }
                        quickPromptGrid
                        if !model.messages.isEmpty { conversation }
                        disclaimer
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Mizan AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $model.roastingMode) {
                        Label("Roast", systemImage: "flame.fill")
                    }
                    .toggleStyle(.button)
                    .tint(AppTheme.accentCream)
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .task { model.loadContext() }
            .onReceive(NotificationCenter.default.publisher(for: .mizanDataDidChange)) { _ in
                model.loadContext()
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hey \(userName.isEmpty ? "there" : userName)")
                    .font(.largeTitle.weight(.bold))
                Button {
                    showNamePrompt = true
                } label: {
                    Image(systemName: "pencil.circle").font(.title3)
                }
                .tint(.secondary)
            }
            Text("Ask me anything about your money")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .alert("Your name", isPresented: $showNamePrompt) {
            TextField("Name", text: $userName)
            Button("Save") {}
        }
    }

    private var unavailableBanner: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accentCream)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mizan AI isn't set up yet").font(.subheadline.weight(.medium))
                    Text("""
                        On newer iPhones (with Apple Intelligence) it runs privately on-device automatically. \
                        Otherwise, turn on "Use my AI server" in Settings → Mizan AI. \
                        You can still explore the prompts below.
                        """)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Always-visible honest framing: Mizan AI narrates the user's own
    /// numbers, and when a server backend is in use those figures leave the
    /// phone. On-device (Apple) mode sends nothing anywhere.
    private var disclaimer: some View {
        Text(MizanAISettings.isOnDeviceAvailable
             ? "Runs on-device. Explains your own numbers — not financial advice."
             : "When a server is connected, your question and the shown figures are sent to it. Explains your own numbers — not financial advice.")
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func continueRow(_ text: String) -> some View {
        Button {
            model.send(text)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue your conversation").font(.caption).foregroundStyle(.secondary)
                    Text(text).font(.subheadline).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .tint(.primary)
    }

    private var quickPromptGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(quickPrompts, id: \.self) { prompt in
                Button { model.send(prompt) } label: {
                    Text(prompt)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                }
                .tint(.primary)
            }
            Button { model.roastMySpending() } label: {
                Label("Roast my spending 🔥", systemImage: "flame.fill")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(12)
                    .background(AppTheme.accentCream.opacity(0.2))
                    .cornerRadius(16)
            }
            .tint(AppTheme.accentCream)
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.messages) { message in
                HStack {
                    if message.role == .user { Spacer(minLength: 40) }
                    Text(message.text)
                        .font(.subheadline)
                        .padding(12)
                        .background(message.role == .user
                                    ? AppTheme.accentMint.opacity(0.2)
                                    : KitTheme.ink.opacity(0.08))
                        .cornerRadius(16)
                    if message.role == .assistant { Spacer(minLength: 40) }
                }
            }
            if model.isThinking {
                HStack { ProgressView(); Text("Thinking…").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your money…", text: $model.input)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .onSubmit { model.sendCurrentInput() }
            Button {
                model.sendCurrentInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .tint(AppTheme.accentMint)
            .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - MizanAIViewModel

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
final class MizanAIViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var isThinking = false
    @Published var roastingMode = false

    // Rebuilt from Settings each time the screen loads: nil backend (no AI
    // configured) or a RemoteLLMBackend pointing at the user's own machine.
    private var service = LLMService()
    private let allocation = SalaryAllocationService()
    private var context: MizanContext?

    var isAvailable: Bool { service.isAvailable }
    /// The most recent question, kept in memory only. Questions can carry
    /// financial details ("Can I afford EGP 2000…"), so they never touch
    /// plaintext UserDefaults — the encrypted DB is the only place money
    /// data persists.
    @Published private(set) var lastSessionSummary: String?

    init() {
        // Scrub the question an earlier build persisted in plaintext.
        UserDefaults.standard.removeObject(forKey: "mizanAILastQuestion")
        configureService()
    }

    /// Builds the LLM backend from the user's Settings. Off by default: only
    /// when "Use my AI server" is on AND a valid host is set does a
    /// RemoteLLMBackend get wired in — otherwise nil (the screen shows its
    /// "not configured" empty state).
    func configureService() {
        service = LLMService(backend: MizanAISettings.makeBackend())
    }

    // MARK: Context

    /// Builds the injected context from the same deterministic services the
    /// dashboard uses — the model only ever narrates these numbers.
    func loadContext() {
        configureService()
        do {
            let now = Date()
            let summaries = try allocation.monthlySummary(for: now).sorted { $0.spent > $1.spent }
            let spent = try allocation.totalSpent(for: now)
            let income = try allocation.currentIncome()?.amount ?? 0
            let budgetUsed = income > 0
                ? Int(truncating: NSDecimalNumber(decimal: min(1, spent / income) * 100))
                : 0
            let netWorth = try netWorthEGP()
            let top = summaries.prefix(3).map { "\($0.category.name): \($0.spent)" }
            context = MizanContext(
                currentMonth: now.formatted(.dateTime.month(.wide).year()),
                totalSpent: "\(spent)",
                income: "\(income)",
                topCategories: Array(top),
                budgetUsedPercent: budgetUsed,
                netWorth: "\(netWorth)"
            )
        } catch {
            context = nil
        }
    }

    private func netWorthEGP() throws -> Decimal {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        return try dbQueue.read { db in
            let converter = try CurrencyConverter(db: db)
            return try Account.fetchAll(db).reduce(Decimal(0)) {
                $0 + converter.toEGP($1.balance, from: $1.currency)
            }
        }
    }

    // MARK: Sending

    func sendCurrentInput() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        input = ""
        send(text)
    }

    func send(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text))
        lastSessionSummary = text
        guard let context else {
            respond("I can't read your data right now — try again after unlocking.")
            return
        }
        Task { await run { try await self.service.answer(question: text, context: context) } }
    }

    func roastMySpending() {
        messages.append(ChatMessage(role: .user, text: "Roast my spending 🔥"))
        guard let context else {
            respond("I can't read your data right now — try again after unlocking.")
            return
        }
        Task { await run { try await self.service.roast(context: context) } }
    }

    private func run(_ work: @escaping () async throws -> String) async {
        isThinking = true
        defer { isThinking = false }
        do {
            let reply = try await work()
            respond(reply)
        } catch {
            // Graceful degradation: the model-unavailable path lands here
            // and shows its own explanatory message instead of crashing.
            respond(error.localizedDescription)
        }
    }

    private func respond(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text))
    }
}
