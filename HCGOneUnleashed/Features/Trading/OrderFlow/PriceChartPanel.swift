import Charts
import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Candlestick chart of the simulated market with bid, ask, last and VWAP.
struct PriceChartPanel: View {
    let series: PriceSeries
    let spec: InstrumentSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Price", detail: "\(series.candles.count) bars · \(SimulationProfile.standard(for: spec.symbol).updatesPerBar) updates per bar") {
                legend
            }
            chart
        }
        .padding(14)
        .background(HCGColor.surface)
    }

    private var chart: some View {
        let decimals = spec.priceDecimals
        let minimumBody = spec.tickSize * 0.25
        return Chart {
            ForEach(series.candles) { candle in
                let color = candle.isUp ? HCGColor.gain : HCGColor.loss
                let mid = (candle.open + candle.close) / 2
                let bodyLow = abs(candle.close - candle.open) < minimumBody ? mid - minimumBody / 2 : min(candle.open, candle.close)
                let bodyHigh = abs(candle.close - candle.open) < minimumBody ? mid + minimumBody / 2 : max(candle.open, candle.close)

                RuleMark(x: .value("Bar", "\(candle.index)"),
                         yStart: .value("Low", candle.low),
                         yEnd: .value("High", candle.high))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(color)
                RectangleMark(x: .value("Bar", "\(candle.index)"),
                              yStart: .value("Body low", bodyLow),
                              yEnd: .value("Body high", bodyHigh),
                              width: .ratio(0.62))
                    .foregroundStyle(color.opacity(0.85))
            }

            if let vwap = series.vwap {
                RuleMark(y: .value("VWAP", vwap))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(HCGColor.vwap)
            }
            RuleMark(y: .value("Bid", series.bid))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(HCGColor.bid.opacity(0.7))
            RuleMark(y: .value("Ask", series.ask))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(HCGColor.ask.opacity(0.7))
            RuleMark(y: .value("Last", series.last))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(HCGColor.lastTrade.opacity(0.35))
                .annotation(position: .overlay, alignment: .trailing) {
                    Text(PriceFormat.price(series.last, decimals: decimals))
                        .font(HCGFont.value(10, weight: .semibold))
                        .foregroundStyle(HCGColor.onAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(HCGColor.accent, in: RoundedRectangle(cornerRadius: 3))
                }
        }
        .chartYScale(domain: series.priceRange)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(HCGColor.separator)
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(decimals)))
                    .font(HCGFont.value(10, weight: .regular))
                    .foregroundStyle(HCGColor.textSecondary)
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Simulated \(spec.symbol.ticker) price chart")
        .accessibilityValue("Last \(PriceFormat.price(series.last, decimals: decimals))")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendSwatch(color: HCGColor.bid, title: "Bid")
            LegendSwatch(color: HCGColor.ask, title: "Ask")
            if series.vwap != nil { LegendSwatch(color: HCGColor.vwap, title: "VWAP") }
        }
    }
}

private struct LegendSwatch: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 10, height: 2)
            Text(title).font(.caption).foregroundStyle(HCGColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
