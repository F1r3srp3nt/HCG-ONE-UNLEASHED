import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Quote strip above the Order Flow panels: last, change, bid, ask, spread
/// and session statistics for the selected simulated market.
///
/// Trading figures use tabular digits and never wrap, so the strip offers
/// three layouts and shows the widest that fits. A single fixed row clipped
/// at the minimum window width (docs/M1_AUDIT.md, OF-1).
struct MarketHeaderBar: View {
    let snapshot: MarketSnapshot
    let isPlaying: Bool
    let speed: SimulationSpeed

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(detail: .full)
            row(detail: .compact)
            row(detail: .minimal)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HCGColor.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simulated \(snapshot.symbol.ticker) quote")
    }

    private enum Detail { case full, compact, minimal }

    private func row(detail: Detail) -> some View {
        let decimals = snapshot.spec.priceDecimals
        return HStack(alignment: .center, spacing: detail == .full ? 22 : 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.symbol.ticker)
                    .font(HCGFont.display(22, weight: .semibold))
                    .foregroundStyle(HCGColor.textPrimary)
                if detail != .minimal {
                    Text("\(snapshot.spec.venue) · \(snapshot.spec.name)")
                        .font(.caption)
                        .foregroundStyle(HCGColor.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            TradingStat("Last", value: PriceFormat.price(snapshot.last, decimals: decimals), size: 20)
            TradingStat("Change", value: PriceFormat.change(snapshot.change, decimals: decimals),
                        color: HCGColor.tone(for: snapshot.change))
            TradingStat("Bid", value: PriceFormat.price(snapshot.bid, decimals: decimals), color: HCGColor.bid)
            TradingStat("Ask", value: PriceFormat.price(snapshot.ask, decimals: decimals), color: HCGColor.ask)
            TradingStat("Spread", value: detail == .minimal
                        ? PriceFormat.price(snapshot.spread, decimals: decimals)
                        : "\(PriceFormat.price(snapshot.spread, decimals: decimals)) · \(PriceFormat.ticks(snapshot.spreadTicks))")
            if detail == .full {
                TradingStat("VWAP", value: snapshot.vwap.map { PriceFormat.price($0, decimals: decimals) } ?? "—")
                TradingStat("Volume", value: snapshot.totalVolume.formatted())
            }

            Spacer(minLength: 12)

            status(detail: detail)
        }
    }

    private func status(detail: Detail) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                StatusDot(isPlaying ? HCGColor.gain : HCGColor.textSecondary)
                Text(isPlaying ? "Running · \(speed.label)" : "Paused")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            if detail == .minimal {
                StatusBadge("Simulated", tone: .simulated)
            } else {
                SimulatedDataBadge()
            }
            if let scenario = snapshot.scenarioID, !snapshot.scenarioComplete, detail == .full {
                StatusBadge("Scenario · \(scenario)", tone: .warning)
            }
        }
    }
}
