import Foundation
import HCGDomain

/// One resting price level as the trading engine sees it.
public struct PriceLevel: Hashable, Sendable {
    public let priceTicks: Int64
    public let size: Int

    public init(priceTicks: Int64, size: Int) {
        self.priceTicks = priceTicks
        self.size = size
    }
}

/// The market state the trading engine executes against.
///
/// This is the engine's only input about the market, which keeps the engine
/// independent of where quotes come from (EVERYTHING IS INTERCHANGEABLE). In
/// HCG ONE UNLEASHED it is always produced by the simulated market.
public struct MarketView: Sendable {
    public let symbol: MarketSymbol
    public let spec: InstrumentSpec
    /// Monotonic market-update counter; each update is processed at most once.
    public let sequence: Int
    /// Simulated time of the update.
    public let time: Date
    public let bidTicks: Int64
    public let askTicks: Int64
    public let lastTicks: Int64
    /// Best first (descending prices).
    public let bids: [PriceLevel]
    /// Best first (ascending prices).
    public let asks: [PriceLevel]

    public init(symbol: MarketSymbol, sequence: Int, time: Date, bidTicks: Int64, askTicks: Int64,
                lastTicks: Int64, bids: [PriceLevel], asks: [PriceLevel]) {
        self.symbol = symbol
        self.spec = symbol.spec
        self.sequence = sequence
        self.time = time
        self.bidTicks = bidTicks
        self.askTicks = askTicks
        self.lastTicks = lastTicks
        self.bids = bids
        self.asks = asks
    }

    public var bid: Double { spec.price(ticks: bidTicks) }
    public var ask: Double { spec.price(ticks: askTicks) }
}

/// Best bid and ask of one market, for marking positions.
public struct Quote: Sendable, Hashable {
    public let bidTicks: Int64
    public let askTicks: Int64

    public init(bidTicks: Int64, askTicks: Int64) {
        self.bidTicks = bidTicks
        self.askTicks = askTicks
    }
}
