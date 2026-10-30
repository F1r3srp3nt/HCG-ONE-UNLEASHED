import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Depth of market: resting bid and ask sizes around the inside quote.
/// The number of levels adapts to the panel height so the ladder never scrolls.
struct DepthLadderPanel: View {
    let snapshot: MarketSnapshot
    let maxLevelsPerSide: Int

    /// Hovered row by position (not by price), so the highlight stays under
    /// the pointer while the simulated book moves.
    @State private var hoveredRow: Int?

    private let rowHeight: CGFloat = 19
    private let priceColumnWidth: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Depth of market", detail: "Spread \(PriceFormat.ticks(snapshot.spreadTicks))")
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            columnHeaders
            Divider()
            GeometryReader { geometry in
                let ladder = DepthLadder(snapshot: snapshot, levelsPerSide: levels(for: geometry.size.height))
                let sideWidth = max(0, (geometry.size.width - priceColumnWidth) / 2)
                VStack(spacing: 0) {
                    ForEach(ladder.rows.indices, id: \.self) { index in
                        LadderRow(row: ladder.rows[index], maxSize: ladder.maxVisibleSize, decimals: snapshot.spec.priceDecimals,
                                  sideWidth: sideWidth, priceWidth: priceColumnWidth, height: rowHeight,
                                  isHovered: hoveredRow == index)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let index = Int(location.y / rowHeight)
                        hoveredRow = (0..<ladder.rows.count).contains(index) ? index : nil
                    case .ended:
                        hoveredRow = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            Divider()
            footer
        }
        .background(HCGColor.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simulated depth of market for \(snapshot.symbol.ticker)")
    }

    /// Levels per side that fit the available height (inside-spread rows included).
    private func levels(for height: CGFloat) -> Int {
        let rows = Int(height / rowHeight)
        let insideSpread = max(0, snapshot.spreadTicks - 1)
        let fitting = (rows - insideSpread) / 2
        return max(3, min(maxLevelsPerSide, fitting))
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("BID SIZE").frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8)
            Text("PRICE").frame(width: priceColumnWidth)
            Text("ASK SIZE").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
        }
        .font(HCGFont.eyebrow)
        .tracking(HCGTracking.eyebrow)
        .foregroundStyle(HCGColor.textSecondary)
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        let bidDepth = snapshot.bids.reduce(0) { $0 + $1.size }
        let askDepth = snapshot.asks.reduce(0) { $0 + $1.size }
        return HStack {
            Text("Bid depth \(bidDepth.formatted())").foregroundStyle(HCGColor.bid)
            Spacer()
            Text("\(snapshot.bids.count) levels per side")
            Spacer()
            Text("Ask depth \(askDepth.formatted())").foregroundStyle(HCGColor.ask)
        }
        .font(HCGFont.value(11, weight: .regular))
        .foregroundStyle(HCGColor.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct LadderRow: View {
    let row: DepthLadder.Row
    let maxSize: Int
    let decimals: Int
    let sideWidth: CGFloat
    let priceWidth: CGFloat
    let height: CGFloat
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            sizeCell(row.bidSize, color: HCGColor.bid, alignment: .trailing, isBest: row.isBestBid)
            priceCell
            sizeCell(row.askSize, color: HCGColor.ask, alignment: .leading, isBest: row.isBestAsk)
        }
        .frame(height: height)
        .background(rowBackground)
        // Tooltip text must not change every update (sizes do), or macOS keeps
        // dismissing it; VoiceOver still gets the live size.
        .help(stableTooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func sizeCell(_ size: Int?, color: Color, alignment: Alignment, isBest: Bool) -> some View {
        ZStack(alignment: alignment) {
            if let size {
                Rectangle()
                    .fill(color.opacity(isBest ? 0.28 : 0.16))
                    .frame(width: max(2, sideWidth * CGFloat(size) / CGFloat(maxSize)))
                Text(size.formatted())
                    .font(HCGFont.value(12, weight: isBest ? .semibold : .regular))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: sideWidth, height: height, alignment: alignment)
        .clipped()
    }

    private var priceCell: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 6))
                .foregroundStyle(HCGColor.accent)
                .opacity(row.isLast ? 1 : 0)
            Text(PriceFormat.price(row.price, decimals: decimals))
                .font(HCGFont.value(12, weight: row.isBestBid || row.isBestAsk || row.isLast ? .semibold : .regular))
                .foregroundStyle(row.isInsideSpread ? HCGColor.textSecondary : HCGColor.textPrimary)
        }
        .frame(width: priceWidth, height: height)
        .background(row.isLast ? HCGColor.accent.opacity(0.12) : .clear)
    }

    private var rowBackground: Color {
        if isHovered { return HCGColor.surfaceRaised }
        if row.isInsideSpread { return HCGColor.surfaceRaised.opacity(0.45) }
        return .clear
    }

    private var stableTooltip: String {
        let price = PriceFormat.price(row.price, decimals: decimals)
        if row.bidSize != nil { return "Simulated resting bids at \(price)" }
        if row.askSize != nil { return "Simulated resting offers at \(price)" }
        return "\(price) — inside the spread, no resting orders (simulated)"
    }

    private var accessibilityText: String {
        let price = PriceFormat.price(row.price, decimals: decimals)
        if let bid = row.bidSize { return "Bid \(bid) contracts at \(price)\(row.isBestBid ? ", best bid" : ""), simulated" }
        if let ask = row.askSize { return "Ask \(ask) contracts at \(price)\(row.isBestAsk ? ", best ask" : ""), simulated" }
        return "\(price), inside the spread, no resting orders, simulated"
    }
}
