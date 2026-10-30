import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Quote strip above the Order Flow panels: last, change, bid, ask, spread
/// and session statistics for the selected simulated market.
struct MarketHeaderBar: View {
    let snapshot: MarketSnapshot
    let isPlaying: Bool
    let speed: SimulationSpeed

    var body: some View {
        let decimals = snapshot.spec.priceDecimals
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.symbol.ticker)
                    .font(HCGFont.display(22, weight: .semibold))
                    .foregroundStyle(HCGColor.textPrimary)
                Text("\(snapshot.spec.venue) · \(snapshot.spec.name)")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, alignment: .leading)

            TradingStat("Last", value: PriceFormat.price(snapshot.last, decimals: decimals), size: 20)
            TradingStat("Change", value: PriceFormat.change(snapshot.change, decimals: decimals),
                        color: HCGColor.tone(for: snapshot.change))
            TradingStat("Bid", value: PriceFormat.price(snapshot.bid, decimals: decimals), color: HCGColor.bid)
            TradingStat("Ask", value: PriceFormat.price(snapshot.ask, decimals: decimals), color: HCGColor.ask)
            TradingStat("Spread", value: "\(PriceFormat.price(snapshot.spread, decimals: decimals)) · \(PriceFormat.ticks(snapshot.spreadTicks))")
            TradingStat("VWAP", value: snapshot.vwap.map { PriceFormat.price($0, decimals: decimals) } ?? "—")
            TradingStat("Volume", value: snapshot.totalVolume.formatted())

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    StatusDot(isPlaying ? HCGColor.gain : HCGColor.textSecondary)
                    Text(isPlaying ? "Running · \(speed.label)" : "Paused")
                        .font(.caption)
                        .foregroundStyle(HCGColor.textSecondary)
                        .monospacedDigit()
                }
                SimulatedDataBadge()
                if let scenario = snapshot.scenarioID, !snapshot.scenarioComplete {
                    StatusBadge("Scenario · \(scenario)", tone: .warning)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(HCGColor.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simulated \(snapshot.symbol.ticker) quote")
    }
}
