import Foundation
import HCGDomain

/// One executed trade on the simulated tape. The aggressor consumed the
/// opposite side: a buy lifts the offer, a sell hits the bid.
public struct TapeTrade: Hashable, Sendable, Identifiable {
    public enum Aggressor: String, Hashable, Sendable { case buy, sell }

    public let id: Int
    /// Market update in which the trade printed.
    public let marketStep: Int
    public let priceTicks: Int64
    public let size: Int
    public let aggressor: Aggressor
}

/// One price bar (OHLC in ticks) with its executed volume and delta.
public struct PriceBar: Hashable, Sendable, Identifiable {
    public let index: Int
    public let openTicks: Int64
    public internal(set) var highTicks: Int64
    public internal(set) var lowTicks: Int64
    public internal(set) var closeTicks: Int64
    /// Contracts traded inside the bar.
    public internal(set) var volume: Int
    /// Aggressive buy volume − aggressive sell volume inside the bar.
    public internal(set) var delta: Int

    public var id: Int { index }

    init(index: Int, openTicks: Int64) {
        self.index = index
        self.openTicks = openTicks
        self.highTicks = openTicks
        self.lowTicks = openTicks
        self.closeTicks = openTicks
        self.volume = 0
        self.delta = 0
    }
}

/// Immutable picture of one simulated market at one moment.
///
/// Every panel (chart, DOM, header, ticket) renders from the same snapshot of
/// the same frame, so they cannot disagree about price, bid, ask or spread.
public struct MarketSnapshot: Sendable, Equatable {
    public let symbol: MarketSymbol
    public let spec: InstrumentSpec
    /// Global simulation clock value of the frame this snapshot belongs to.
    public let frameSequence: Int
    /// Updates of this market since its session (or scenario) started.
    public let marketStep: Int

    public let lastTicks: Int64
    public let bidTicks: Int64
    public let askTicks: Int64
    public let sessionOpenTicks: Int64
    /// Best-first, strictly descending.
    public let bids: [BookLevel]
    /// Best-first, strictly ascending.
    public let asks: [BookLevel]
    public let bars: [PriceBar]
    /// Most recent trades, newest last.
    public let recentTrades: [TapeTrade]
    /// Session VWAP in ticks (fractional), `nil` before the first trade.
    public let vwapTicks: Double?
    public let cumulativeDelta: Int
    public let totalVolume: Int

    public let scenarioID: String?
    public let scenarioPhase: Int?
    public let scenarioPhaseCount: Int
    public let scenarioComplete: Bool

    // MARK: Derived values

    public var spreadTicks: Int { Int(askTicks - bidTicks) }
    public var last: Double { spec.price(ticks: lastTicks) }
    public var bid: Double { spec.price(ticks: bidTicks) }
    public var ask: Double { spec.price(ticks: askTicks) }
    public var spread: Double { Double(spreadTicks) * spec.tickSize }
    public var sessionOpen: Double { spec.price(ticks: sessionOpenTicks) }
    public var changeTicks: Int64 { lastTicks - sessionOpenTicks }
    public var change: Double { spec.price(ticks: changeTicks) }
    public var vwap: Double? { vwapTicks.map { $0 * spec.tickSize } }
    public var isScenarioRunning: Bool { scenarioID != nil && !scenarioComplete }
}
