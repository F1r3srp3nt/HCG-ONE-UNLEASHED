import Foundation
import HCGDomain

/// Price ladder for the DOM panel, derived purely from one snapshot.
///
/// Rows run from the highest ask down to the lowest bid, including any empty
/// prices inside the spread when it is wider than one tick.
public struct DepthLadder: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let priceTicks: Int64
        public let price: Double
        public let bidSize: Int?
        public let askSize: Int?
        public let isBestBid: Bool
        public let isBestAsk: Bool
        public let isLast: Bool

        public var id: Int64 { priceTicks }
        /// A price inside the spread with no resting orders.
        public var isInsideSpread: Bool { bidSize == nil && askSize == nil }
    }

    public let symbol: MarketSymbol
    public let frameSequence: Int
    public let rows: [Row]
    public let bestBidTicks: Int64
    public let bestAskTicks: Int64
    public let lastTicks: Int64
    public let spreadTicks: Int
    /// Largest resting size among visible rows (for size bars), at least 1.
    public let maxVisibleSize: Int

    public init(snapshot: MarketSnapshot, levelsPerSide: Int = 12) {
        let count = max(1, levelsPerSide)
        let asks = snapshot.asks.prefix(count)
        let bids = snapshot.bids.prefix(count)
        var askSizes: [Int64: Int] = [:]
        for level in asks { askSizes[level.priceTicks] = level.size }
        var bidSizes: [Int64: Int] = [:]
        for level in bids { bidSizes[level.priceTicks] = level.size }

        let top = asks.last?.priceTicks ?? snapshot.askTicks
        let bottom = bids.last?.priceTicks ?? snapshot.bidTicks
        var rows: [Row] = []
        rows.reserveCapacity(Int(top - bottom) + 1)
        var price = top
        while price >= bottom {
            rows.append(Row(
                priceTicks: price,
                price: snapshot.spec.price(ticks: price),
                bidSize: bidSizes[price],
                askSize: askSizes[price],
                isBestBid: price == snapshot.bidTicks,
                isBestAsk: price == snapshot.askTicks,
                isLast: price == snapshot.lastTicks))
            price -= 1
        }

        self.symbol = snapshot.symbol
        self.frameSequence = snapshot.frameSequence
        self.rows = rows
        self.bestBidTicks = snapshot.bidTicks
        self.bestAskTicks = snapshot.askTicks
        self.lastTicks = snapshot.lastTicks
        self.spreadTicks = snapshot.spreadTicks
        self.maxVisibleSize = max(1, (asks.map(\.size) + bids.map(\.size)).max() ?? 1)
    }
}

/// Candles and reference lines for the chart panel, derived from one snapshot.
public struct PriceSeries: Sendable, Equatable {
    public struct Candle: Sendable, Equatable, Identifiable {
        public let index: Int
        public let open: Double
        public let high: Double
        public let low: Double
        public let close: Double
        public let volume: Int

        public var id: Int { index }
        public var isUp: Bool { close >= open }
    }

    public let symbol: MarketSymbol
    public let frameSequence: Int
    public let candles: [Candle]
    public let last: Double
    public let bid: Double
    public let ask: Double
    public let vwap: Double?
    /// Padded price range covering candles, bid, ask and VWAP.
    public let priceRange: ClosedRange<Double>

    public init(snapshot: MarketSnapshot, maxCandles: Int = 90) {
        let spec = snapshot.spec
        let candles = snapshot.bars.suffix(max(1, maxCandles)).map { bar in
            Candle(index: bar.index,
                   open: spec.price(ticks: bar.openTicks),
                   high: spec.price(ticks: bar.highTicks),
                   low: spec.price(ticks: bar.lowTicks),
                   close: spec.price(ticks: bar.closeTicks),
                   volume: bar.volume)
        }
        var low = min(candles.map(\.low).min() ?? snapshot.bid, snapshot.bid)
        var high = max(candles.map(\.high).max() ?? snapshot.ask, snapshot.ask)
        if let vwap = snapshot.vwap {
            low = min(low, vwap)
            high = max(high, vwap)
        }
        let padding = max((high - low) * 0.08, spec.tickSize * 4)

        self.symbol = snapshot.symbol
        self.frameSequence = snapshot.frameSequence
        self.candles = Array(candles)
        self.last = snapshot.last
        self.bid = snapshot.bid
        self.ask = snapshot.ask
        self.vwap = snapshot.vwap
        self.priceRange = (low - padding)...(high + padding)
    }
}
