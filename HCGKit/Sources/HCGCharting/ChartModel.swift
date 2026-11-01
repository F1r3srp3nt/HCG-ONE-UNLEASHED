import Foundation

/// The lower study pane under the price chart.
public enum ChartStudy: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, rsi, macd, atr

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: "None"
        case .rsi: "RSI (14)"
        case .macd: "MACD (12, 26, 9)"
        case .atr: "ATR (14)"
        }
    }
}

/// What the chart shows. Saved as a user preference.
public struct ChartSettings: Codable, Hashable, Sendable {
    public var timeframe: Timeframe = .m5
    public var showSMA = true
    public var smaPeriod = 20
    public var showFastEMA = true
    public var fastEMAPeriod = 9
    public var showSlowEMA = false
    public var slowEMAPeriod = 21
    public var showBollinger = false
    public var showVWAP = true
    public var study: ChartStudy = .rsi
    /// Candles across the visible width (zoom).
    public var visibleCandles = 90

    public init() {}

    public static let visibleRange = 20...400

    /// Keeps periods and zoom within usable bounds.
    public func clamped() -> ChartSettings {
        var s = self
        s.smaPeriod = min(max(s.smaPeriod, 2), 200)
        s.fastEMAPeriod = min(max(s.fastEMAPeriod, 2), 200)
        s.slowEMAPeriod = min(max(s.slowEMAPeriod, 2), 200)
        s.visibleCandles = min(max(s.visibleCandles, Self.visibleRange.lowerBound), Self.visibleRange.upperBound)
        return s
    }
}

/// Every indicator series for one candle array, aligned with the candles
/// (computed once per frame, then only drawn).
public struct ChartStudies: Sendable, Equatable {
    public let sma: [Double?]
    public let fastEMA: [Double?]
    public let slowEMA: [Double?]
    public let bollinger: Indicators.Bands?
    public let vwap: [Double?]
    public let rsi: [Double?]
    public let macd: Indicators.MACDResult?
    public let atr: [Double?]

    public init(candles: [Candle], settings: ChartSettings) {
        let closes = candles.map { Double($0.closeTicks) }
        let none = [Double?](repeating: nil, count: candles.count)
        sma = settings.showSMA ? Indicators.sma(closes, period: settings.smaPeriod) : none
        fastEMA = settings.showFastEMA ? Indicators.ema(closes, period: settings.fastEMAPeriod) : none
        slowEMA = settings.showSlowEMA ? Indicators.ema(closes, period: settings.slowEMAPeriod) : none
        bollinger = settings.showBollinger ? Indicators.bollinger(closes, period: 20, deviations: 2) : nil
        vwap = settings.showVWAP ? Indicators.sessionVWAP(candles) : none
        rsi = settings.study == .rsi ? Indicators.rsi(closes, period: 14) : none
        macd = settings.study == .macd ? Indicators.macd(closes) : nil
        atr = settings.study == .atr
            ? Indicators.atr(high: candles.map { Double($0.highTicks) }, low: candles.map { Double($0.lowTicks) },
                             close: closes, period: 14)
            : none
    }

    /// Price overlays visible on the price pane (for scaling), in ticks.
    public func overlayValues(in range: Range<Int>) -> [Double] {
        var out: [Double] = []
        for series in [sma, fastEMA, slowEMA, vwap, bollinger?.upper ?? [], bollinger?.lower ?? []] {
            for i in range where i < series.count { if let v = series[i] { out.append(v) } }
        }
        return out
    }
}

/// Which candles are on screen.
public struct ChartViewport: Equatable, Sendable {
    /// Visible candle indices (into the full candle array).
    public let range: Range<Int>
    /// Slots across the width; the newest candle sits in the last slot when
    /// the chart is showing the latest data.
    public let slots: Int

    /// - Parameters:
    ///   - offsetFromLatest: candles scrolled back from the newest (0 = live).
    public init(candleCount: Int, visible: Int, offsetFromLatest: Int) {
        let slots = max(1, visible)
        let maxOffset = max(0, candleCount - 1)
        let offset = min(max(0, offsetFromLatest), maxOffset)
        let end = max(0, candleCount - offset)
        let start = max(0, end - slots)
        self.range = start..<end
        self.slots = slots
    }

    /// Slot (0-based, left to right) of a candle index.
    public func slot(of index: Int) -> Int { slots - (range.upperBound - index) }

    /// The candle index under an x position, or `nil` outside the candles.
    public func index(atX x: Double, width: Double) -> Int? {
        guard width > 0, !range.isEmpty else { return nil }
        let slot = Int((x / width * Double(slots)).rounded(.down))
        let index = range.upperBound - (slots - slot)
        return range.contains(index) ? index : nil
    }

    /// Centre x of a candle index.
    public func x(of index: Int, width: Double) -> Double {
        (Double(slot(of: index)) + 0.5) * width / Double(slots)
    }
}

/// Maps prices (ticks) to vertical positions and picks axis labels.
public struct PriceScale: Equatable, Sendable {
    public let lowTicks: Double
    public let highTicks: Double

    /// Fits `values` with a margin, never narrower than `minimumTicks`.
    public init(fitting values: [Double], marginFraction: Double = 0.06, minimumTicks: Double = 8) {
        guard let lo = values.min(), let hi = values.max() else {
            lowTicks = 0
            highTicks = minimumTicks
            return
        }
        var low = lo
        var high = hi
        if high - low < minimumTicks {
            let mid = (high + low) / 2
            low = mid - minimumTicks / 2
            high = mid + minimumTicks / 2
        }
        let margin = (high - low) * marginFraction
        lowTicks = low - margin
        highTicks = high + margin
    }

    public init(lowTicks: Double, highTicks: Double) {
        self.lowTicks = lowTicks
        self.highTicks = max(highTicks, lowTicks + 1e-9)
    }

    /// y within a pane of `height`; higher prices are higher on screen.
    public func y(_ ticks: Double, height: Double) -> Double {
        (highTicks - ticks) / (highTicks - lowTicks) * height
    }

    public func ticks(atY y: Double, height: Double) -> Double {
        highTicks - y / height * (highTicks - lowTicks)
    }

    /// Round label positions (in ticks) for about `count` labels, on
    /// multiples of 1, 2, 2.5 or 5 × 10ⁿ in price units, always whole ticks.
    public func labels(count: Int, tickSize: Double) -> [Double] {
        guard count > 0, tickSize > 0 else { return [] }
        let spanPrice = (highTicks - lowTicks) * tickSize
        let raw = spanPrice / Double(count)
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let step = [1, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? 10 * magnitude
        let stepTicks = max(1, (step / tickSize).rounded())
        var value = (lowTicks / stepTicks).rounded(.up) * stepTicks
        var out: [Double] = []
        while value <= highTicks && out.count < 50 {
            out.append(value)
            value += stepTicks
        }
        return out
    }
}
