import SwiftUI

// MARK: - SankeyView (roadmap Should-have)
// Income → category cash-flow diagram, drawn with Canvas (no charting
// library does Sankey natively). Deliberately TWO-HUE per the design
// direction: spending flows in mint, the unspent remainder flows to
// "Saved" in cream — a rainbow-per-category Sankey turns into noise.
public struct SankeyView: View {
    public struct Flow: Identifiable {
        public let name: String
        public let value: Double
        public let isSavings: Bool
        public var id: String { name }

        public init(name: String, value: Double, isSavings: Bool = false) {
            self.name = name
            self.value = value
            self.isSavings = isSavings
        }
    }

    let income: Double
    let flows: [Flow]

    public init(income: Double, flows: [Flow]) {
        self.income = income
        self.flows = flows
    }

    public var body: some View {
        Canvas { context, size in
            // Conservation: the left income bar must equal the sum of the
            // right flow bars (a Sankey where money in ≠ money out reads as
            // a bug). The right bars fill `usableHeight` between them, so the
            // income bar is drawn to that same total height. The caller is
            // expected to pass flows that sum to income (spending + Other +
            // Saved); `totalFlows` is the scale either way so the picture
            // always balances.
            let totalFlows = max(flows.reduce(0) { $0 + $1.value }, 1)
            let nodeWidth: CGFloat = 10
            let gap: CGFloat = 6
            let usableHeight = size.height - gap * CGFloat(max(0, flows.count - 1))

            // Left node: income bar, equal in length to the stacked right bars.
            let incomeHeight = usableHeight
            context.fill(
                Path(roundedRect: CGRect(x: 0, y: (size.height - incomeHeight) / 2,
                                         width: nodeWidth, height: incomeHeight), cornerRadius: 3),
                with: .color(Color("AccentMint"))
            )

            // Right nodes + connecting bands, stacked top to bottom.
            var rightY: CGFloat = 0
            var leftY = (size.height - incomeHeight) / 2
            for flow in flows {
                let height = usableHeight * flow.value / totalFlows
                let color = Color(flow.isSavings ? "AccentCream" : "AccentMint")
                context.fill(
                    Path(roundedRect: CGRect(x: size.width - nodeWidth, y: rightY,
                                             width: nodeWidth, height: height), cornerRadius: 3),
                    with: .color(color)
                )
                // Cubic band from the income bar to this node.
                var band = Path()
                let x0 = nodeWidth
                let x1 = size.width - nodeWidth
                let controlX = (x0 + x1) / 2
                band.move(to: CGPoint(x: x0, y: leftY))
                band.addCurve(to: CGPoint(x: x1, y: rightY),
                              control1: CGPoint(x: controlX, y: leftY),
                              control2: CGPoint(x: controlX, y: rightY))
                band.addLine(to: CGPoint(x: x1, y: rightY + height))
                band.addCurve(to: CGPoint(x: x0, y: leftY + height),
                              control1: CGPoint(x: controlX, y: rightY + height),
                              control2: CGPoint(x: controlX, y: leftY + height))
                band.closeSubpath()
                context.fill(band, with: .color(color.opacity(0.28)))

                // Label inside the band's right edge.
                context.draw(
                    Text("\(flow.name)").font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: x1 - 14, y: rightY + height / 2),
                    anchor: .trailing
                )
                leftY += height
                rightY += height + gap
            }
        }
    }
}
