import SwiftUI

// MARK: - CategoryChip (ENHANCEMENTS Wave A2)
// Circular colored chip shown wherever a category appears inline. The color
// is derived deterministically from the category name, so the same category
// is always the same color across relaunches without adding a color column
// to the schema — O(1), no migration, no persistence.
public struct CategoryChip: View {
    public let name: String
    public let size: CGFloat

    public init(name: String, size: CGFloat = 32) {
        self.name = name
        self.size = size
    }

    // Stable hue from the name's scalar hash. The 0–300° span excludes the
    // cold blue-gray band that would read as "default/unset".
    private var chipColor: Color {
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let hue = Double(hash % 300) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(chipColor.opacity(0.25))
                .frame(width: size, height: size)
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(chipColor)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        CategoryChip(name: "Food")
        CategoryChip(name: "Transfer")
        CategoryChip(name: "Coffee")
        CategoryChip(name: "سوبر ماركت")
    }
    .padding()
    .background(AppTheme.backgroundGradient)
}
