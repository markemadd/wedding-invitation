import SwiftUI
import UIKit

// MARK: - Kit design system (Figma "Budget Tracking / Wallet App" UI Kit)
// A shared re-skin layer that ports the kit's flat dark aesthetic — near-black
// canvas, elevated #121418 cards, pill chips, segmented donut, record rows —
// while swapping the kit's indigo primary for Mizan's green (AppTheme
// .accentMint). Every tab pulls from these tokens/components so the whole app
// reads as one system and a palette change touches one file, not forty.
public enum KitTheme {
    /// Screen background — near-black in dark, near-white in light. All the
    /// structural tokens below are appearance-aware so the whole kit flips
    /// with the system/user theme; the accent palette (AppTheme.accentMint
    /// etc.) already carries its own light/dark asset variants.
    public static let canvas = Color(light: 0xF2F4F3, dark: 0x08090C)
    /// Elevated card / control surface — white card in light, #121418 in dark.
    public static let card = Color(light: 0xFFFFFF, dark: 0x121418)
    /// Primary accent — Mizan green. The asset resolves to a bright mint in
    /// dark and a deeper leaf green in light, so it reads on both canvases.
    public static let primary = AppTheme.accentMint
    /// Income / positive amounts (green, matching the primary language).
    public static let income = AppTheme.accentMint
    /// Expense / negative amounts (the kit's red, #DB3C3C — legible on both).
    public static let expense = Color(hexValue: 0xDB3C3C)

    // Text at three emphasis levels — white on dark, near-black on light.
    public static let textPrimary = Color(light: 0x0C1712, dark: 0xFFFFFF)
    public static let textSecondary = Color(light: 0x0C1712, lightAlpha: 0.58,
                                            dark: 0xFFFFFF, darkAlpha: 0.5)
    public static let textTertiary = Color(light: 0x0C1712, lightAlpha: 0.38,
                                           dark: 0xFFFFFF, darkAlpha: 0.3)

    /// The neutral "ink" used for hairlines, dividers, strokes, and subtle
    /// fills via `.opacity(...)`. White over the dark canvas, near-black over
    /// the light one — so `KitTheme.ink.opacity(0.06)` is a faint divider in
    /// both modes. Replaces the hardcoded `KitTheme.ink.opacity(...)` overlays.
    public static let ink = Color(light: 0x0A0A0A, dark: 0xFFFFFF)

    // Categorical hues for the donut / pills — kept distinct from the green
    // primary so categories stay legible against each other.
    public static let categoryPalette: [Color] = [
        Color(hexValue: 0x66FFA3), Color(hexValue: 0x3DB9FF), Color(hexValue: 0xFF66B2),
        Color(hexValue: 0xFFD466), Color(hexValue: 0xFF9466), Color(hexValue: 0xB388FF)
    ]

    /// The full swatch set offered when the user edits a category's color.
    public static let categoryPaletteChoices: [UInt32] = [
        0x66FFA3, 0x3DB9FF, 0xFF66B2, 0xFFD466, 0xFF9466, 0xB388FF, 0x4FE0C0,
        0xFF6B6B, 0x9CCC65, 0x7C4DFF, 0x64B5F6, 0xF06292, 0xFFA726, 0xE0E0E0
    ]

    /// Per-category color: a user-chosen override (stored on-device) if set,
    /// otherwise a deterministic hue from the name so the same category keeps
    /// the same color across relaunches. Overrides fix the palette collisions
    /// you get once you have more categories than base hues.
    public static func categoryColor(_ name: String) -> Color {
        if let hex = UserDefaults.standard.string(forKey: colorKey(name)),
           let value = UInt32(hex, radix: 16) {
            return Color(hexValue: value)
        }
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        return categoryPalette[hash % categoryPalette.count]
    }

    /// Store (or clear, with nil) a category's chosen color.
    public static func setCategoryColor(_ hexValue: UInt32?, for name: String) {
        if let hexValue {
            UserDefaults.standard.set(String(format: "%06X", hexValue), forKey: colorKey(name))
        } else {
            UserDefaults.standard.removeObject(forKey: colorKey(name))
        }
    }

    private static func colorKey(_ name: String) -> String { "categoryColor.\(name)" }
}

// MARK: - Screen background

public extension View {
    /// Applies the kit's flat dark canvas behind a screen's content.
    func kitBackground() -> some View {
        background(KitTheme.canvas.ignoresSafeArea())
    }
}

// MARK: - KitCard

/// Flat elevated card — the kit's #121418 surface at radius 12. Replaces the
/// frosted GlassCard wherever a screen adopts the kit look.
public struct KitCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KitTheme.card, in: RoundedRectangle(cornerRadius: 12))
            // A hairline edge so white cards separate from the light canvas;
            // near-invisible on the dark canvas where the fill already reads.
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(KitTheme.ink.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - KitSectionHeader

/// "Title  …  [Action]" row — title in white, an optional tinted pill button
/// on the trailing edge (the kit's "All Budgets" / "Statistics" affordance).
public struct KitSectionHeader: View {
    let title: String
    let action: String?
    let onAction: (() -> Void)?

    public init(_ title: String, action: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.action = action
        self.onAction = onAction
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KitTheme.textPrimary)
            Spacer()
            if let action {
                Button { onAction?() } label: {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KitTheme.primary)
                        .padding(10)
                        .background(KitTheme.primary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - AmountPill

/// Two-line pill: colored dot + name (white) over amount (in the accent
/// color). The kit's `Budget1` / `Category1` component.
public struct AmountPill: View {
    let color: Color
    let title: String
    let amount: String
    let iconSize: CGFloat
    let fillOpacity: Double

    public init(color: Color, title: String, amount: String,
                iconSize: CGFloat = 24, fillOpacity: Double = 0.1) {
        self.color = color
        self.title = title
        self.amount = amount
        self.iconSize = iconSize
        self.fillOpacity = fillOpacity
    }

    public var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KitTheme.textPrimary)
                Text(amount)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(color.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 35))
    }
}

// MARK: - KitProgressBar

/// Track + fill capsule (kit: 6px tall, 19px radius). Defaults to the green
/// primary; pass a tint for per-category bars.
public struct KitProgressBar: View {
    let fraction: Double
    let tint: Color

    public init(fraction: Double, tint: Color = KitTheme.primary) {
        self.fraction = fraction
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.12))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - DonutRing

/// Segmented donut with rounded caps and small gaps — the kit's "Expense"
/// ring. Segment values are relative and normalized here.
public struct DonutRing: View {
    public struct Segment: Identifiable {
        public let id = UUID()
        public let value: Double
        public let color: Color
        public init(value: Double, color: Color) {
            self.value = value
            self.color = color
        }
    }

    let segments: [Segment]
    let lineWidth: CGFloat
    private let gap = 0.012

    public init(segments: [Segment], lineWidth: CGFloat = 14) {
        self.segments = segments
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
                .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            var start = -0.25 // 12 o'clock
            for segment in segments {
                let sweep = segment.value / total
                let from = start + gap / 2
                let to = start + sweep - gap / 2
                var path = Path()
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .radians(from * 2 * .pi),
                    endAngle: .radians(to * 2 * .pi),
                    clockwise: false
                )
                context.stroke(path, with: .color(segment.color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                start += sweep
            }
        }
    }
}

// MARK: - KitListRow

/// A "Last Records" style row: rounded colored icon tile, title + subtitle on
/// the left, a trailing value (+ optional caption) on the right.
public struct KitListRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let value: String
    let valueColor: Color
    let caption: String?

    public init(icon: String, tint: Color, title: String, subtitle: String,
                value: String, valueColor: Color = KitTheme.textPrimary, caption: String? = nil) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueColor = valueColor
        self.caption = caption
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KitTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KitTheme.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(valueColor)
                if let caption {
                    Text(caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
    }
}

// MARK: - KitPrimaryButton

/// Full-width pill CTA in the green primary with dark text (green is too
/// bright for white text on the dark canvas).
public struct KitPrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(KitTheme.primary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Money formatting

/// One place that formats every money amount in the app: grouped thousands,
/// exactly two decimal places, and the "EGP" suffix. Amounts are already in
/// EGP by the time they reach the UI (services convert through the FX table),
/// so the suffix is always correct here.
public enum Money {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// "1,234.56" — grouped, exactly two decimals, no suffix.
    public static func amount(_ value: Decimal) -> String {
        formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// "1,234.56 EGP" — the standard money string used everywhere.
    public static func egp(_ value: Decimal) -> String {
        amount(value) + " EGP"
    }
}

// MARK: - Amount input (live thousands grouping)

/// Formatting for money-entry fields: groups the integer part with commas as
/// the user types ("4000" → "4,000"), keeps up to two decimals, and parses
/// back to an exact Decimal for storage.
public enum AmountFormat {
    /// Re-group a raw text input as the user types.
    public static func regroup(_ input: String) -> String {
        let filtered = input.filter { $0.isNumber || $0 == "." }
        if let dot = filtered.firstIndex(of: ".") {
            let intPart = String(filtered[..<dot])
            let fracPart = String(filtered[filtered.index(after: dot)...]).filter { $0.isNumber }.prefix(2)
            return group(intPart) + "." + fracPart
        }
        return group(filtered)
    }

    private static func group(_ digits: String) -> String {
        var clean = digits.filter { $0.isNumber }
        while clean.count > 1 && clean.first == "0" { clean.removeFirst() }
        guard !clean.isEmpty else { return "" }
        var result = ""
        for (offset, ch) in clean.reversed().enumerated() {
            if offset != 0 && offset % 3 == 0 { result.append(",") }
            result.append(ch)
        }
        return String(result.reversed())
    }

    /// Parse a grouped string back to an exact Decimal.
    public static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: ""),
                locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Grouped display for an existing value (for seeding an editor field).
    public static func grouped(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }
}

/// A decimal-pad text field that live-groups thousands with commas.
public struct AmountTextField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font
    var color: Color
    var alignment: TextAlignment

    public init(_ placeholder: String = "0", text: Binding<String>,
                font: Font = .system(size: 17, weight: .semibold),
                color: Color = KitTheme.textPrimary,
                alignment: TextAlignment = .leading) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.color = color
        self.alignment = alignment
    }

    public var body: some View {
        TextField(placeholder, text: Binding(
            get: { text },
            set: { text = AmountFormat.regroup($0) }
        ))
        .keyboardType(.decimalPad)
        .font(font)
        .foregroundStyle(color)
        .multilineTextAlignment(alignment)
    }
}

// MARK: - Color(hex:)

public extension String {
    /// Title-cases a display name WITHOUT clobbering deliberate casing:
    /// an all-lowercase word gets its first letter capitalized
    /// ("checking account" → "Checking Account", "cash" → "Cash"), while
    /// acronyms and mixed-case words are left alone ("CIB", "iPhone",
    /// "Debit Card" unchanged). Purely for display — never mutates stored
    /// account names.
    var smartTitleCased: String {
        split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard let first = word.first, word.allSatisfy({ $0.isLowercase || !$0.isLetter }) else {
                return String(word)
            }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

public extension Color {
    /// Build a color from a 0xRRGGBB literal.
    init(hexValue: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue:  Double(hexValue & 0xFF) / 255
        )
    }

    /// A color that resolves to `light` in light appearance and `dark` in
    /// dark appearance (each a 0xRRGGBB literal, with optional alpha). Backed
    /// by a dynamic UIColor so it re-resolves live when the theme changes.
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self = Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return UIColor(
                red:   CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue:  CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }
}
