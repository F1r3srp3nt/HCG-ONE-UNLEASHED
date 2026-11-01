import Foundation

/// The side that crossed the spread in a trade.
public enum TradeSide: String, Codable, Sendable {
    /// Lifted the offer (buyer-initiated).
    case buy
    /// Hit the bid (seller-initiated).
    case sell
}

/// One timestamped trade: the raw input of every chart.
public struct TradeEvent: Hashable, Sendable {
    public let time: Date
    public let priceTicks: Int64
    public let size: Int
    public let aggressor: TradeSide

    public init(time: Date, priceTicks: Int64, size: Int, aggressor: TradeSide) {
        self.time = time
        self.priceTicks = priceTicks
        self.size = size
        self.aggressor = aggressor
    }
}

/// One candle. Prices are in whole ticks of the instrument.
public struct Candle: Codable, Hashable, Sendable, Identifiable {
    /// Start of the candle's period (see `Timeframe.bucketStart`).
    public let start: Date
    public internal(set) var openTicks: Int64
    public internal(set) var highTicks: Int64
    public internal(set) var lowTicks: Int64
    public internal(set) var closeTicks: Int64
    public internal(set) var volume: Int
    /// Volume of buyer-initiated trades.
    public internal(set) var buyVolume: Int
    /// Volume of seller-initiated trades.
    public internal(set) var sellVolume: Int
    public internal(set) var trades: Int
    /// Σ price × size, in ticks, for exact trade-based VWAP.
    public internal(set) var notionalTicks: Double
    /// Seconds since 1970 of the last trade in the candle (orders the close
    /// correctly when trades arrive out of order). Stored as a number, not a
    /// `Date`, so sub-second times survive ISO 8601 session files exactly.
    public internal(set) var lastTradeSeconds: Double
    /// Seconds since 1970 of the first trade (orders the open).
    public internal(set) var firstTradeSeconds: Double

    public var id: Date { start }
    /// Buy volume − sell volume.
    public var delta: Int { buyVolume - sellVolume }
    /// Volume-weighted average price of this candle, in ticks.
    public var vwapTicks: Double { volume > 0 ? notionalTicks / Double(volume) : Double(closeTicks) }
    public var isUp: Bool { closeTicks >= openTicks }

    public init(start: Date, first trade: TradeEvent) {
        self.start = start
        openTicks = trade.priceTicks
        highTicks = trade.priceTicks
        lowTicks = trade.priceTicks
        closeTicks = trade.priceTicks
        volume = 0
        buyVolume = 0
        sellVolume = 0
        trades = 0
        notionalTicks = 0
        lastTradeSeconds = trade.time.timeIntervalSince1970
        firstTradeSeconds = trade.time.timeIntervalSince1970
        add(trade)
    }

    /// Exact candle values, for tests and fixtures.
    public init(start: Date, openTicks: Int64, highTicks: Int64, lowTicks: Int64, closeTicks: Int64,
                volume: Int, buyVolume: Int = 0, sellVolume: Int = 0, trades: Int = 1, notionalTicks: Double? = nil) {
        self.start = start
        self.openTicks = openTicks
        self.highTicks = highTicks
        self.lowTicks = lowTicks
        self.closeTicks = closeTicks
        self.volume = volume
        self.buyVolume = buyVolume
        self.sellVolume = sellVolume
        self.trades = trades
        self.notionalTicks = notionalTicks ?? Double(closeTicks) * Double(volume)
        lastTradeSeconds = start.timeIntervalSince1970
        firstTradeSeconds = start.timeIntervalSince1970
    }

    mutating func add(_ trade: TradeEvent) {
        highTicks = max(highTicks, trade.priceTicks)
        lowTicks = min(lowTicks, trade.priceTicks)
        let seconds = trade.time.timeIntervalSince1970
        if seconds >= lastTradeSeconds {
            closeTicks = trade.priceTicks
            lastTradeSeconds = seconds
        }
        if seconds < firstTradeSeconds {
            openTicks = trade.priceTicks
            firstTradeSeconds = seconds
        }
        volume += trade.size
        if trade.aggressor == .buy { buyVolume += trade.size } else { sellVolume += trade.size }
        trades += 1
        notionalTicks += Double(trade.priceTicks) * Double(trade.size)
    }
}

/// Candles of one timeframe, built from trades.
///
/// Closed candles and the forming candle are stored apart, so a trade only
/// changes `forming`, and the `closed` array changes only when a candle
/// closes. Frames that share the array then stay cheap to copy.
public struct CandleSeries: Codable, Hashable, Sendable {
    public let timeframe: Timeframe
    /// Most candles kept; the oldest closed candles are dropped first.
    public let limit: Int
    public private(set) var closed: [Candle] = []
    public private(set) var forming: Candle?
    /// Trades older than the kept history, which could not be placed.
    public private(set) var droppedTrades = 0

    public init(timeframe: Timeframe, limit: Int = 400) {
        self.timeframe = timeframe
        self.limit = max(2, limit)
    }

    /// Closed candles followed by the forming one, oldest first.
    public var candles: [Candle] { forming.map { closed + [$0] } ?? closed }
    public var count: Int { closed.count + (forming == nil ? 0 : 1) }

    /// Adds a trade to the candle its time belongs to. Trades normally
    /// arrive in time order; a late trade is merged into its candle if that
    /// candle is still kept.
    public mutating func add(_ trade: TradeEvent) {
        guard trade.size > 0 else { return }
        let start = timeframe.bucketStart(trade.time)
        guard let current = forming?.start else {
            forming = Candle(start: start, first: trade)
            return
        }
        if start == current {
            forming?.add(trade)   // in place: no candle copy per trade
        } else if start > current {
            if let finished = forming { closed.append(finished) }
            if closed.count > limit - 1 { closed.removeFirst(closed.count - (limit - 1)) }
            forming = Candle(start: start, first: trade)
        } else {
            mergeLate(trade, start: start)
        }
    }

    private mutating func mergeLate(_ trade: TradeEvent, start: Date) {
        // Binary search the closed candles (sorted by start).
        var low = 0
        var high = closed.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if closed[mid].start == start {
                closed[mid].add(trade)
                return
            }
            if closed[mid].start < start { low = mid + 1 } else { high = mid - 1 }
        }
        // A period with no candle yet gets one, as long as the history has
        // room or the period is newer than the oldest kept candle. Only
        // trades older than a full history are dropped.
        let hasRoom = closed.count < limit - 1
        if hasRoom || (closed.first.map { start > $0.start } ?? true) {
            closed.insert(Candle(start: start, first: trade), at: low)
            if closed.count > limit - 1 { closed.removeFirst(closed.count - (limit - 1)) }
        } else {
            droppedTrades += 1
        }
    }
}

/// Every timeframe of one market.
public struct ChartHistory: Codable, Hashable, Sendable {
    /// One series per timeframe, in `Timeframe.allCases` order (an array,
    /// not a dictionary, so each trade updates the series in place cheaply).
    public private(set) var all: [CandleSeries]

    public init(limit: Int = 400) {
        all = Timeframe.allCases.map { CandleSeries(timeframe: $0, limit: limit) }
    }

    public subscript(timeframe: Timeframe) -> CandleSeries {
        all[Self.index(timeframe)]
    }

    public mutating func add(_ trade: TradeEvent) {
        for i in all.indices { all[i].add(trade) }
    }

    private static func index(_ timeframe: Timeframe) -> Int {
        Timeframe.allCases.firstIndex(of: timeframe)!
    }
}
