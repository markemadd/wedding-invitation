import SwiftUI
import UI

// MARK: - MainTabView — Liquid-Glass tab bar with a raised center "+"
// Four tabs (Wallet / Bills / Buckets / Insights) around a raised mint "+"
// that opens quick manual entry from anywhere. Settings moved off the bar
// to the gear in the Wallet header (it's not a daily destination). The bar
// sits in a bottom safeAreaInset — NOT an overlay — so every screen's
// scrollable content and bottom-pinned buttons end above it instead of
// being covered by it.
struct MainTabView: View {
    @State private var selection: Tab = .wallet
    /// Its own capture stack so the center "+" works from any tab; saving
    /// posts .mizanDataDidChange, which every screen already listens to.
    @StateObject private var quickAdd = CaptureViewModel()
    @State private var showQuickAdd = false

    enum Tab: Int, CaseIterable, Identifiable {
        case wallet, bills, buckets, insights
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .wallet: return "Wallet"
            case .bills: return "Bills"
            case .buckets: return "Buckets"
            case .insights: return "Insights"
            }
        }
        var icon: String {
            switch self {
            case .wallet: return "creditcard.fill"
            case .bills: return "arrow.2.circlepath"
            case .buckets: return "basket.fill"
            case .insights: return "chart.bar.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            tab(WalletView(), .wallet)
            tab(BillsView(), .bills)
            tab(BucketsView(), .buckets)
            tab(InsightsView(), .insights)
        }
        .tint(AppTheme.accentMint)
        // The bar floats over the tabs. Each screen reserves the matching
        // bottom space in its OWN scroll content (KitScreen.tabBarClearance),
        // because safeAreaInset applied here doesn't reliably propagate
        // through each tab's NavigationStack to its ScrollView.
        .overlay(alignment: .bottom) {
            GlassTabBar(selection: $selection) {
                showQuickAdd = true
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            ManualEntryView(viewModel: quickAdd)
                .onAppear { quickAdd.loadAfterUnlock() }
        }
        #if DEBUG
        .onAppear {
            // Screenshot capture opens a specific tab via env var.
            switch MizanScreenshotMode.initialTab {
            case "bills": selection = .bills
            case "buckets": selection = .buckets
            case "insights": selection = .insights
            case "wallet": selection = .wallet
            case "add": selection = .wallet; showQuickAdd = true
            default: break
            }
        }
        #endif
    }

    private func tab<Content: View>(_ content: Content, _ tag: Tab) -> some View {
        content
            .tag(tag)
            .toolbar(.hidden, for: .tabBar)
    }
}

// The height each screen must leave clear at the bottom so its last row
// (Arrange widgets, Save budget, …) sits above the floating tab bar +
// raised "+". Referenced by every tab screen's scroll content.
enum TabBarLayout {
    static let clearance: CGFloat = 104
}

// MARK: - GlassTabBar

struct GlassTabBar: View {
    @Binding var selection: MainTabView.Tab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.wallet)
            tabButton(.bills)
            addButton
            tabButton(.buckets)
            tabButton(.insights)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(KitTheme.ink.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: MainTabView.Tab) -> some View {
        let selected = tab == selection
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                if selected {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize()
                }
            }
            .foregroundStyle(selected ? .black : KitTheme.ink.opacity(0.65))
            .padding(.horizontal, selected ? 16 : 12)
            .frame(height: 44)
            .background {
                if selected {
                    Capsule().fill(AppTheme.accentMint)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The raised center "+": bigger than the tabs and lifted above the bar
    /// edge (classic FAB), always meaning "add a transaction".
    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(AppTheme.accentMint)
                        .shadow(color: AppTheme.accentMint.opacity(0.45), radius: 12, y: 4)
                )
                .overlay(Circle().strokeBorder(KitTheme.ink.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .offset(y: -16)
        .padding(.horizontal, 6)
    }
}
