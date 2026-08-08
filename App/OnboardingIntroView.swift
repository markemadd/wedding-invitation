import SwiftUI
import UI

// MARK: - OnboardingIntroView
// First-launch intro carousel (GrowFi-style layout, Mizan branding & graphics):
// a wordmark + Skip, three slides each with a layered illustration, a heading,
// a line of copy, and an "on-device" reassurance line, then page dots and a
// Next / Get Started button. Shown once, before the lock, gated by "didSeeIntro".
struct OnboardingIntroView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Slide {
        let title: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(title: "Take control of your money",
              body: "Track every expense, see exactly where it goes, and watch your net worth grow — all in one place."),
        Slide(title: "Budgets that fit your life",
              body: "Set a budget that resets on your payday, see your safe-to-spend at a glance, and get nudged before you overspend."),
        Slide(title: "Private by design",
              body: "Everything stays encrypted on your iPhone. No accounts, no servers, no tracking — ever.")
    ]

    private var isLast: Bool { page == slides.count - 1 }

    var body: some View {
        ZStack {
            KitTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { index in
                        slideView(index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                dots.padding(.bottom, 22)

                KitPrimaryButton(isLast ? "Get Started" : "Next") {
                    if isLast { onFinish() } else { withAnimation { page += 1 } }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "leaf.circle.fill").foregroundStyle(KitTheme.primary)
                Text("Mizan").font(.system(size: 24, weight: .bold)).foregroundStyle(KitTheme.primary)
            }
            Spacer()
            if !isLast {
                Button("Skip") { onFinish() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KitTheme.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .frame(height: 44)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? KitTheme.primary : KitTheme.ink.opacity(0.18))
                    .frame(width: index == page ? 22 : 8, height: 8)
                    .animation(.easeInOut, value: page)
            }
        }
    }

    private func slideView(_ index: Int) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            OnboardingArtwork(index: index)
                .frame(height: 260)
                .padding(.horizontal, 28)
            Spacer(minLength: 24)
            Text(slides[index].title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(KitTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(slides[index].body)
                .font(.system(size: 15))
                .foregroundStyle(KitTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.horizontal, 34)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("Your data never leaves your phone")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(KitTheme.primary)
            .padding(.top, 16)
            Spacer(minLength: 8)
        }
    }
}

// MARK: - OnboardingArtwork
// Layered, semi-isometric illustrations built entirely in SwiftUI (no bundled
// assets, crisp at any size, theme-aware): a soft green gradient panel with a
// per-slide scene and floating accent chips for depth.
private struct OnboardingArtwork: View {
    let index: Int

    private let panelGradient = LinearGradient(
        colors: [Color(hexValue: 0x3DA35D), Color(hexValue: 0x2FBF9E)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(panelGradient)
                .shadow(color: Color(hexValue: 0x3DA35D).opacity(0.35), radius: 24, y: 14)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .blendMode(.plusLighter)
            scene
        }
        .frame(maxWidth: 320)
    }

    @ViewBuilder private var scene: some View {
        switch index {
        case 0: growthScene
        case 1: budgetScene
        default: privacyScene
        }
    }

    // Slide 1 — a card with an ascending bar chart, a rising arrow, a coin.
    private var growthScene: some View {
        ZStack {
            floatingChip { Label("+24%", systemImage: "arrow.up.right") }
                .offset(x: 92, y: -86)
            glassCard(width: 190, height: 150) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.5)).frame(width: 60, height: 7)
                        Spacer()
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach([0.45, 0.7, 0.55, 0.95], id: \.self) { height in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 20, height: 78 * height)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            coin.offset(x: -92, y: 78)
        }
    }

    // Slide 2 — a budget ring with a wallet glyph and floating category chips.
    private var budgetScene: some View {
        ZStack {
            floatingChip { Label("Food", systemImage: "fork.knife") }.offset(x: -96, y: -78)
            floatingChip { Label("Safe to spend", systemImage: "checkmark.seal.fill") }.offset(x: 70, y: 92)
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 14).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: 0.68)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 150)
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // Slide 3 — a phone with a shield-lock and floating privacy chips.
    private var privacyScene: some View {
        ZStack {
            floatingChip { Label("No accounts", systemImage: "person.slash") }.offset(x: -88, y: -84)
            floatingChip { Label("No tracking", systemImage: "eye.slash") }.offset(x: 92, y: 84)
            glassCard(width: 118, height: 178) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: pieces

    private var coin: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Image(systemName: "egyptianpoundsign").font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hexValue: 0x2F7D49))
        }
    }

    private func glassCard<Content: View>(width: CGFloat, height: CGFloat,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.35), lineWidth: 1))
            .frame(width: width, height: height)
            .overlay(content())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    private func floatingChip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hexValue: 0x2F7D49))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
