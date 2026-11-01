import Foundation
import Testing
@testable import HCGCharting

private func utc(_ text: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)!
}

/// Indicator outputs must match the reference element by element: the same
/// warm-up (`nil`) positions and values within `tolerance`.
private func expectMatches(_ actual: [Double?], _ expected: [Double?], tolerance: Double, _ name: String) {
    #expect(actual.count == expected.count, "\(name): length")
    var worst = 0.0
    for (i, (a, e)) in zip(actual, expected).enumerated() {
        switch (a, e) {
        case (nil, nil): continue
        case let (a?, e?): worst = max(worst, abs(a - e))
        default: Issue.record("\(name)[\(i)]: \(String(describing: a)) vs reference \(String(describing: e))")
        }
    }
    #expect(worst <= tolerance, "\(name): largest difference \(worst)")
}

private func series(_ timeframe: Timeframe, from trades: [TradeEvent], limit: Int = 10_000) -> CandleSeries {
    var s = CandleSeries(timeframe: timeframe, limit: limit)
    for t in trades { s.add(t) }
    return s
}

@Suite("Charting — timeframes")
struct TimeframeTests {
    @Test("Intraday candles align to the UTC clock; 4h and 1D to the 22:00 UTC session open")
    func alignment() {
        let t = utc("2026-01-05T14:37:42Z")
        #expect(Timeframe.m1.bucketStart(t) == utc("2026-01-05T14:37:00Z"))
        #expect(Timeframe.m5.bucketStart(t) == utc("2026-01-05T14:35:00Z"))
        #expect(Timeframe.m15.bucketStart(t) == utc("2026-01-05T14:30:00Z"))
        #expect(Timeframe.h1.bucketStart(t) == utc("2026-01-05T14:00:00Z"))
        #expect(Timeframe.h4.bucketStart(t) == utc("2026-01-05T14:00:00Z"), "22, 02, 06, 10, 14, 18 UTC")
        #expect(Timeframe.h4.bucketStart(utc("2026-01-05T23:10:00Z")) == utc("2026-01-05T22:00:00Z"))
        #expect(Timeframe.d1.bucketStart(t) == utc("2026-01-04T22:00:00Z"), "the session that opened Sunday 22:00 UTC")
        #expect(Timeframe.d1.bucketStart(utc("2026-01-05T22:00:00Z")) == utc("2026-01-05T22:00:00Z"))
        #expect(Timeframe.sessionDay(utc("2026-01-05T21:59:59Z")) + 1 == Timeframe.sessionDay(utc("2026-01-05T22:00:00Z")))
        #expect(Timeframe.allCases.map(\.label) == ["1m", "5m", "15m", "1h", "4h", "1D"])
    }
}

@Suite("Charting — candles from trades")
struct CandleAggregationTests {
    @Test("Every timeframe matches pandas' resampling of the same 1,500 trades", arguments: Timeframe.allCases)
    func matchesPandas(_ timeframe: Timeframe) throws {
        let built = series(timeframe, from: Reference.trades).candles
        let expected = try #require(Reference.candles[timeframe])
        #expect(built.count == expected.count)
        for (c, e) in zip(built, expected) {
            #expect(c.start.timeIntervalSince1970 == e.0)
            let prices: [Int64] = [c.openTicks, c.highTicks, c.lowTicks, c.closeTicks]
            let expectedPrices: [Int64] = [e.1, e.2, e.3, e.4]
            #expect(prices == expectedPrices, "\(timeframe) \(c.start)")
            let counts: [Int] = [c.volume, c.buyVolume, c.sellVolume, c.trades]
            let expectedCounts: [Int] = [e.5, e.6, e.7, e.8]
            #expect(counts == expectedCounts)
            #expect(c.notionalTicks == e.9)
        }
    }

    @Test("Trades arriving in any order build the same candles")
    func orderIndependent() {
        var shuffled = Reference.trades
        var state: UInt64 = 42
        for i in stride(from: shuffled.count - 1, to: 0, by: -1) {   // deterministic Fisher–Yates
            state = state &* 6364136223846793005 &+ 1442695040888963407
            shuffled.swapAt(i, Int(state >> 33) % (i + 1))
        }
        for timeframe in Timeframe.allCases {
            let inOrder = series(timeframe, from: Reference.trades).candles
            let scrambled = series(timeframe, from: shuffled).candles
            #expect(inOrder == scrambled, "\(timeframe)")
        }
    }

    @Test("Higher timeframes equal their lower-timeframe candles combined")
    func timeframesAgree() {
        let m1 = series(.m1, from: Reference.trades).candles
        for higher in [Timeframe.m5, .m15, .h1, .h4, .d1] {
            let built = series(higher, from: Reference.trades).candles
            let groups = Dictionary(grouping: m1) { higher.bucketStart($0.start) }
            #expect(built.count == groups.count)
            for c in built {
                let parts = (groups[c.start] ?? []).sorted { $0.start < $1.start }
                #expect(c.openTicks == parts.first?.openTicks && c.closeTicks == parts.last?.closeTicks)
                #expect(c.highTicks == parts.map(\.highTicks).max() && c.lowTicks == parts.map(\.lowTicks).min())
                #expect(c.volume == parts.reduce(0) { $0 + $1.volume } && c.delta == parts.reduce(0) { $0 + $1.delta })
            }
        }
    }

    @Test("Only the forming candle changes until a new period starts; history is bounded")
    func formingAndLimit() {
        var s = CandleSeries(timeframe: .m1, limit: 5)
        let base = utc("2026-01-05T14:30:00Z")
        s.add(TradeEvent(time: base.addingTimeInterval(1), priceTicks: 100, size: 2, aggressor: .buy))
        s.add(TradeEvent(time: base.addingTimeInterval(30), priceTicks: 103, size: 1, aggressor: .sell))
        #expect(s.closed.isEmpty)
        #expect(s.forming?.closeTicks == 103 && s.forming?.highTicks == 103 && s.forming?.delta == 1)
        for minute in 1...10 {
            s.add(TradeEvent(time: base.addingTimeInterval(Double(minute * 60 + 5)), priceTicks: 100 + Int64(minute), size: 1, aggressor: .buy))
        }
        #expect(s.count == 5, "4 closed + 1 forming")
        #expect(s.forming?.start == base.addingTimeInterval(600))
        s.add(TradeEvent(time: base.addingTimeInterval(1), priceTicks: 1, size: 1, aggressor: .buy))
        #expect(s.droppedTrades == 1, "older than the kept history")
        #expect(s.candles.allSatisfy { $0.lowTicks > 1 })
    }

    @Test("Candle VWAP and delta come from the trades")
    func candleValues() {
        let base = utc("2026-01-05T14:30:00Z")
        var s = CandleSeries(timeframe: .m1)
        s.add(TradeEvent(time: base, priceTicks: 100, size: 3, aggressor: .buy))
        s.add(TradeEvent(time: base.addingTimeInterval(1), priceTicks: 104, size: 1, aggressor: .sell))
        let c = s.forming!
        #expect(c.vwapTicks == 101)
        #expect(c.delta == 2 && c.trades == 2 && c.isUp)
    }
}

@Suite("Charting — indicators against TA-Lib and pandas")
struct IndicatorReferenceTests {
    let close = Reference.close

    @Test("SMA(20)") func sma() { expectMatches(Indicators.sma(close, period: 20), Reference.sma20, tolerance: 1e-8, "SMA20") }
    @Test("EMA(9) and EMA(21)") func ema() {
        expectMatches(Indicators.ema(close, period: 9), Reference.ema9, tolerance: 1e-8, "EMA9")
        expectMatches(Indicators.ema(close, period: 21), Reference.ema21, tolerance: 1e-8, "EMA21")
    }
    @Test("RSI(14), Wilder") func rsi() { expectMatches(Indicators.rsi(close, period: 14), Reference.rsi14, tolerance: 1e-9, "RSI14") }

    @Test("MACD(12, 26, 9): line, signal, histogram")
    func macd() {
        let m = Indicators.macd(close)
        // TA-Lib reports all three from index 33; the line itself is defined from index 25.
        expectMatches(Array(m.macd[33...]), Array(Reference.macd[33...]), tolerance: 1e-8, "MACD")
        #expect(m.macd[25] != nil && m.macd[24] == nil)
        expectMatches(m.signal, Reference.macdSignal, tolerance: 1e-8, "signal")
        expectMatches(m.histogram, Reference.macdHistogram, tolerance: 1e-8, "histogram")
    }

    @Test("Bollinger Bands(20, 2σ)")
    func bollinger() {
        let b = Indicators.bollinger(close, period: 20, deviations: 2)
        expectMatches(b.upper, Reference.bollingerUpper, tolerance: 1e-6, "upper")
        expectMatches(b.middle, Reference.bollingerMiddle, tolerance: 1e-8, "middle")
        expectMatches(b.lower, Reference.bollingerLower, tolerance: 1e-6, "lower")
    }

    @Test("ATR(14), Wilder")
    func atr() {
        expectMatches(Indicators.atr(high: Reference.high, low: Reference.low, close: close, period: 14),
                      Reference.atr14, tolerance: 1e-9, "ATR14")
    }

    @Test("Session VWAP from trades, resetting at the 22:00 UTC session open")
    func vwap() {
        for (timeframe, expected) in [(Timeframe.m1, Reference.sessionVWAP1m), (.m5, Reference.sessionVWAP5m)] {
            let candles = series(timeframe, from: Reference.trades).candles
            let vwap = Indicators.sessionVWAP(candles)
            expectMatches(vwap, expected.map { Optional($0) }, tolerance: 1e-9, "VWAP \(timeframe)")
        }
        // The reference crosses 22:00 UTC: the first candle after it starts a new average at its own VWAP.
        let m1 = series(.m1, from: Reference.trades).candles
        let i = m1.firstIndex { $0.start >= utc("2026-01-05T22:00:00Z") }!
        #expect(Indicators.sessionVWAP(m1)[i] == m1[i].vwapTicks)
    }

    @Test("Too little data gives no values; a flat market reads RSI 0, as in TA-Lib")
    func edges() {
        #expect(Indicators.sma([1, 2], period: 3) == [nil, nil])
        #expect(Indicators.ema([], period: 3).isEmpty)
        #expect(Indicators.rsi(Array(repeating: 5, count: 20)).compactMap { $0 }.allSatisfy { $0 == 0 })
        #expect(Indicators.atr(high: [1], low: [1], close: [1]) == [nil])
        #expect(Indicators.macd([1, 2, 3]).macd == [nil, nil, nil])
    }
}
