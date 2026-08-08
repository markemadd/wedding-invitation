import SwiftUI
import UI

// MARK: - StoryCardShareView
// The month-end story as a shareable image card — the free acquisition
// loop: people post their month, the card carries the brand. The card is
// rendered OFFSCREEN with ImageRenderer from the same deterministic
// MonthlyStoryService lines shown in Insights; nothing is recomputed, so
// the shared numbers always match the app. Redaction is ON by default —
// sharing must be a deliberate opt-in to showing real amounts.
struct StoryCardShareView: View {
    let monthTitle: String
    let lines: [String]

    @Environment(\.dismiss) private var dismiss
    /// Default ON: the safe direction for a card headed to social media.
    @State private var redactAmounts = true
    @State private var rendered: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StoryCard(monthTitle: monthTitle, lines: displayLines)
                        .frame(width: StoryCard.cardWidth)
                    KitCard {
                        Toggle(isOn: $redactAmounts) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide amounts")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(KitTheme.textPrimary)
                                Text("Percentages stay; money becomes •••")
                                    .font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                            }
                        }
                        .tint(KitTheme.primary)
                    }
                    if let rendered {
                        ShareLink(
                            item: rendered,
                            preview: SharePreview("Mizan — \(monthTitle)", image: rendered)
                        ) {
                            Label("Share card", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(KitTheme.primary, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(20)
            }
            .kitBackground()
            .navigationTitle("Share your month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.tint(KitTheme.primary)
                }
            }
            // Re-render whenever redaction flips (and once on appear).
            .task(id: redactAmounts) { render() }
        }
    }

    private var displayLines: [String] {
        redactAmounts ? lines.map(Self.redact) : lines
    }

    /// Blanks money figures but keeps the story readable: percentages
    /// ("23%"), and small whole counts (transactions, months, days — all
    /// < 32) survive; anything else numeric becomes •••. Conservative on
    /// purpose: a decimal like 45.50 is treated as money even though it's
    /// small.
    static func redact(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\d[\d.,]*"#) else { return line }
        let ns = line as NSString
        var result = line
        // Replace back-to-front so earlier ranges stay valid.
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).reversed() {
            let token = ns.substring(with: match.range)
            let after = match.range.upperBound < ns.length
                ? ns.substring(with: NSRange(location: match.range.upperBound, length: 1))
                : ""
            if after == "%" { continue }
            if !token.contains(".") && !token.contains(","), let value = Int(token), value < 32 { continue }
            let start = result.index(result.startIndex, offsetBy: match.range.location)
            let end = result.index(start, offsetBy: match.range.length)
            result.replaceSubrange(start..<end, with: "•••")
        }
        return result
    }

    /// Offscreen render at 3× — crisp enough for social feeds (~1080 px).
    @MainActor
    private func render() {
        let renderer = ImageRenderer(
            content: StoryCard(monthTitle: monthTitle, lines: displayLines)
                .frame(width: StoryCard.cardWidth)
        )
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            rendered = Image(uiImage: uiImage)
        }
    }
}

// MARK: - StoryCard (the image itself)
// Self-contained visual: no Environment dependencies, so ImageRenderer
// produces exactly what the preview shows.
struct StoryCard: View {
    static let cardWidth: CGFloat = 360

    let monthTitle: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KitTheme.primary)
                Text("Mizan")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text("My month in money")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(KitTheme.primary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(line)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                Text("tracked privately, on-device")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KitTheme.primary.opacity(0.8))
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(hexValue: 0x0C1410), Color(hexValue: 0x08090C)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(KitTheme.primary.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
