import Foundation

/// Technical indicators over candle data.
///
/// Every function returns one value per input element, `nil` while the
/// indicator is still warming up, so results line up with their candles.
/// Conventions follow TA-Lib (the reference the tests compare against):
/// EMAs are seeded with the simple average of their first `period` values,
/// RSI and ATR use Wilder's smoothing, Bollinger Bands use the population
/// standard deviation. See docs/CHARTING.md.
public enum Indicators {
    // MARK: Moving averages

    /// Simple moving average; first value at index `period − 1`.
    public static func sma(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return Array(repeating: nil, count: values.count) }
        var out = [Double?](repeating: nil, count: values.count)
        var sum = values[0..<period].reduce(0, +)
        out[period - 1] = sum / Double(period)
        for i in period..<values.count {
            sum += values[i] - values[i - period]
            out[i] = sum / Double(period)
        }
        return out
    }

    /// Exponential moving average with α = 2 / (period + 1), seeded with the
    /// SMA of the first `period` values; first value at index `period − 1`.
    public static func ema(_ values: [Double], period: Int) -> [Double?] {
        ema(values, period: period, seededAt: period - 1)
    }

    // MARK: Oscillators

    /// Relative Strength Index with Wilder's smoothing; first value at index
    /// `period`. A window with no movement at all reads 0, as in TA-Lib.
    public static func rsi(_ values: [Double], period: Int = 14) -> [Double?] {
        guard period > 0, values.count > period else { return Array(repeating: nil, count: values.count) }
        var out = [Double?](repeating: nil, count: values.count)
        var gain = 0.0
        var loss = 0.0
        for i in 1...period {
            let change = values[i] - values[i - 1]
            if change > 0 { gain += change } else { loss -= change }
        }
        gain /= Double(period)
        loss /= Double(period)
        out[period] = rsiValue(gain, loss)
        for i in (period + 1)..<values.count {
            let change = values[i] - values[i - 1]
            gain = (gain * Double(period - 1) + max(change, 0)) / Double(period)
            loss = (loss * Double(period - 1) + max(-change, 0)) / Double(period)
            out[i] = rsiValue(gain, loss)
        }
        return out
    }

    private static func rsiValue(_ gain: Double, _ loss: Double) -> Double {
        gain + loss == 0 ? 0 : 100 * gain / (gain + loss)
    }

    public struct MACDResult: Equatable, Sendable {
        public let macd: [Double?]
        public let signal: [Double?]
        public let histogram: [Double?]
    }

    /// MACD: EMA(fast) − EMA(slow), its EMA(signal), and the difference.
    ///
    /// Both EMAs start together at index `slow − 1`: the fast EMA is seeded
    /// with the average of the `fast` values ending there, the slow EMA with
    /// the `slow` values ending there. The signal EMA is seeded the same way
    /// at `slow + signal − 2`. This is TA-Lib's `MACD` convention; the
    /// textbook variant that starts the fast EMA at index `fast − 1` differs
    /// only in the first few dozen values. MACD starts at index `slow − 1`,
    /// signal and histogram at `slow + signal − 2`.
    public static func macd(_ values: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> MACDResult {
        let count = values.count
        var line = [Double?](repeating: nil, count: count)
        var signalLine = [Double?](repeating: nil, count: count)
        var histogram = [Double?](repeating: nil, count: count)
        guard fast > 0, slow >= fast, signal > 0, count >= slow else {
            return MACDResult(macd: line, signal: signalLine, histogram: histogram)
        }
        let fastEMA = ema(values, period: fast, seededAt: slow - 1)
        let slowEMA = ema(values, period: slow, seededAt: slow - 1)
        var lineValues: [Double] = []
        for i in (slow - 1)..<count {
            guard let f = fastEMA[i], let s = slowEMA[i] else { continue }
            line[i] = f - s
            lineValues.append(f - s)
        }
        let smoothed = ema(lineValues, period: signal, seededAt: signal - 1)
        for (offset, value) in smoothed.enumerated() {
            guard let value else { continue }
            signalLine[slow - 1 + offset] = value
            histogram[slow - 1 + offset] = lineValues[offset] - value
        }
        return MACDResult(macd: line, signal: signalLine, histogram: histogram)
    }

    /// EMA whose seed is the SMA of the `period` values ending at `seedIndex`.
    private static func ema(_ values: [Double], period: Int, seededAt seedIndex: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: values.count)
        guard period > 0, seedIndex >= period - 1, seedIndex < values.count else { return out }
        let alpha = 2 / Double(period + 1)
        var previous = values[(seedIndex - period + 1)...seedIndex].reduce(0, +) / Double(period)
        out[seedIndex] = previous
        for i in (seedIndex + 1)..<values.count {
            previous = (values[i] - previous) * alpha + previous
            out[i] = previous
        }
        return out
    }

    // MARK: Volatility

    public struct Bands: Equatable, Sendable {
        public let upper: [Double?]
        public let middle: [Double?]
        public let lower: [Double?]
    }

    /// Bollinger Bands: SMA(period) ± deviations × population standard
    /// deviation over the same window.
    public static func bollinger(_ values: [Double], period: Int = 20, deviations: Double = 2) -> Bands {
        let middle = sma(values, period: period)
        var upper = [Double?](repeating: nil, count: values.count)
        var lower = [Double?](repeating: nil, count: values.count)
        for i in values.indices {
            guard let mean = middle[i] else { continue }
            // Two-pass variance: accurate at price levels of several thousand.
            var sumSquares = 0.0
            for v in values[(i - period + 1)...i] { sumSquares += (v - mean) * (v - mean) }
            let sd = (sumSquares / Double(period)).squareRoot()
            upper[i] = mean + deviations * sd
            lower[i] = mean - deviations * sd
        }
        return Bands(upper: upper, middle: middle, lower: lower)
    }

    /// True range; index 0 has no previous close, so it is `nil` (TA-Lib).
    public static func trueRange(high: [Double], low: [Double], close: [Double]) -> [Double?] {
        let count = min(high.count, low.count, close.count)
        var out = [Double?](repeating: nil, count: count)
        guard count > 1 else { return out }
        for i in 1..<count {
            out[i] = max(high[i] - low[i], abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1]))
        }
        return out
    }

    /// Average True Range with Wilder's smoothing; first value at index
    /// `period` (the mean of the first `period` true ranges).
    public static func atr(high: [Double], low: [Double], close: [Double], period: Int = 14) -> [Double?] {
        let tr = trueRange(high: high, low: low, close: close)
        guard period > 0, tr.count > period else { return Array(repeating: nil, count: tr.count) }
        var out = [Double?](repeating: nil, count: tr.count)
        var value = tr[1...period].reduce(0) { $0 + ($1 ?? 0) } / Double(period)
        out[period] = value
        for i in (period + 1)..<tr.count {
            value = (value * Double(period - 1) + (tr[i] ?? 0)) / Double(period)
            out[i] = value
        }
        return out
    }

    // MARK: Volume

    /// Session VWAP at the close of each candle, in ticks: Σ(price × size) /
    /// Σ size over every trade since the session opened (22:00 UTC). Exact,
    /// because candles carry their trades' notional.
    public static func sessionVWAP(_ candles: [Candle]) -> [Double?] {
        var out = [Double?](repeating: nil, count: candles.count)
        var session: Int?
        var notional = 0.0
        var volume = 0
        for (i, candle) in candles.enumerated() {
            let day = Timeframe.sessionDay(candle.start)
            if day != session {
                session = day
                notional = 0
                volume = 0
            }
            notional += candle.notionalTicks
            volume += candle.volume
            if volume > 0 { out[i] = notional / Double(volume) }
        }
        return out
    }
}

public extension CandleSeries {
    /// Close prices of every candle (closed and forming), in ticks.
    var closes: [Double] { candles.map { Double($0.closeTicks) } }
}
