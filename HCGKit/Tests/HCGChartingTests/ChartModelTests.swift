import Foundation
import Testing
@testable import HCGCharting

@Suite("Charting — chart model")
struct ChartModelTests {
    @Test("The live viewport ends at the newest candle; scrolling back moves it, within bounds")
    func viewport() {
        let live = ChartViewport(candleCount: 300, visible: 90, offsetFromLatest: 0)
        #expect(live.range == 210..<300)
        #expect(live.slot(of: 299) == 89)
        let back = ChartViewport(candleCount: 300, visible: 90, offsetFromLatest: 50)
        #expect(back.range == 160..<250)
        #expect(ChartViewport(candleCount: 300, visible: 90, offsetFromLatest: 10_000).range == 0..<1, "never scrolls past the oldest candle")
        let few = ChartViewport(candleCount: 10, visible: 90, offsetFromLatest: 0)
        #expect(few.range == 0..<10)
        #expect(few.slot(of: 9) == 89, "a short history still sits at the right edge")
        #expect(ChartViewport(candleCount: 0, visible: 90, offsetFromLatest: 0).range.isEmpty)
    }

    @Test("Crosshair hit-testing finds the candle under the pointer")
    func hitTesting() {
        let v = ChartViewport(candleCount: 300, visible: 100, offsetFromLatest: 0)
        #expect(v.index(atX: 999, width: 1_000) == 299)
        #expect(v.index(atX: 0, width: 1_000) == 200)
        #expect(v.index(atX: 505, width: 1_000) == 250)
        for i in v.range { #expect(v.index(atX: v.x(of: i, width: 1_000), width: 1_000) == i) }
        let few = ChartViewport(candleCount: 10, visible: 100, offsetFromLatest: 0)
        #expect(few.index(atX: 5, width: 1_000) == nil, "empty slots on the left")
    }

    @Test("The price scale fits the data with a margin and maps both ways")
    func priceScale() {
        let s = PriceScale(fitting: [100, 200], marginFraction: 0.1)
        #expect(s.lowTicks == 90 && s.highTicks == 210)
        #expect(s.y(210, height: 300) == 0 && s.y(90, height: 300) == 300)
        #expect(abs(s.ticks(atY: s.y(150, height: 300), height: 300) - 150) < 1e-9)
        let flat = PriceScale(fitting: [100, 100], marginFraction: 0, minimumTicks: 8)
        #expect(flat.lowTicks == 96 && flat.highTicks == 104, "a flat market still gets a usable range")
    }

    @Test("Axis labels are round prices on whole ticks")
    func labels() {
        // ES: 0.25 tick. 21,900–22,000 ticks = 5,475.00–5,500.00.
        let es = PriceScale(lowTicks: 21_900, highTicks: 22_000).labels(count: 5, tickSize: 0.25)
        #expect(es == [21_900, 21_920, 21_940, 21_960, 21_980, 22_000], "every 5.00 points")
        // CL: 0.01 tick. 7,000–7,060 ticks = 70.00–70.60.
        let cl = PriceScale(lowTicks: 7_000, highTicks: 7_060).labels(count: 6, tickSize: 0.01)
        #expect(cl == [7_000, 7_010, 7_020, 7_030, 7_040, 7_050, 7_060], "every 0.10")
        #expect(es.allSatisfy { $0 == $0.rounded() })
    }

    @Test("Studies are computed only for what is shown, aligned with the candles")
    func studies() {
        var settings = ChartSettings()
        settings.study = .macd
        settings.showBollinger = true
        let candles = series(.m1, Reference.trades).candles
        let s = ChartStudies(candles: candles, settings: settings)
        #expect(s.sma.count == candles.count && s.macd != nil && s.bollinger != nil)
        #expect(s.rsi.allSatisfy { $0 == nil }, "RSI not selected")
        #expect(s.sma == Indicators.sma(candles.map { Double($0.closeTicks) }, period: 20))
        #expect(!s.overlayValues(in: candles.indices).isEmpty)
    }

    @Test("Settings stay within usable bounds and round-trip as a preference")
    func settings() throws {
        var s = ChartSettings()
        s.visibleCandles = 5
        s.smaPeriod = 0
        let c = s.clamped()
        #expect(c.visibleCandles == 20 && c.smaPeriod == 2)
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(ChartSettings.self, from: data) == c)
    }

    private func series(_ timeframe: Timeframe, _ trades: [TradeEvent]) -> CandleSeries {
        var s = CandleSeries(timeframe: timeframe, limit: 10_000)
        for t in trades { s.add(t) }
        return s
    }
}
