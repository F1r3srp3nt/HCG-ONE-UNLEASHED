import Foundation
import HCGDomain
import HCGTrading

/// Deterministic simulated time: update `n` happens at `start + n × secondsPerUpdate`.
/// It never reads the wall clock, so replays and saved sessions are exact.
public struct SimulatedClock: Codable, Hashable, Sendable {
    /// Monday 5 January 2026, 14:30 UTC (09:30 New York): the simulated session open.
    public static let defaultStart = Date(timeIntervalSince1970: 1_767_623_400)

    public var start: Date
    public var secondsPerUpdate: Double

    public init(start: Date = SimulatedClock.defaultStart, secondsPerUpdate: Double = 1) {
        self.start = start
        self.secondsPerUpdate = max(0.001, secondsPerUpdate)
    }

    public func time(at sequence: Int) -> Date {
        start.addingTimeInterval(Double(sequence) * secondsPerUpdate)
    }
}

/// Everything the UI needs from one moment of the simulation, produced by a
/// single clock: every market snapshot in a frame carries the same
/// `sequence`, so connected panels can never drift apart.
public struct SimulationFrame: Sendable, Equatable {
    /// Number of clock updates since the session started.
    public let sequence: Int
    /// Monotonic counter of every state change (updates, orders, resets).
    /// Used to discard out-of-order deliveries.
    public let revision: Int
    /// Simulated time of this frame.
    public let time: Date
    public let markets: [MarketSymbol: MarketSnapshot]
    public let account: TradingAccount

    public subscript(symbol: MarketSymbol) -> MarketSnapshot {
        guard let snapshot = markets[symbol] else {
            preconditionFailure("SimulationFrame has no market for \(symbol)")
        }
        return snapshot
    }

    public var quotes: [MarketSymbol: Quote] {
        markets.mapValues { Quote(bidTicks: $0.bidTicks, askTicks: $0.askTicks) }
    }

    public var equity: Double { account.equity(quotes: quotes) }
    public var buyingPower: Double { account.buyingPower(quotes: quotes) }
    public var unrealizedPnL: Double { account.unrealizedPnL(quotes: quotes) }

    public func unrealizedPnL(_ symbol: MarketSymbol) -> Double {
        guard let snapshot = markets[symbol] else { return 0 }
        return account.unrealizedPnL(symbol, quote: Quote(bidTicks: snapshot.bidTicks, askTicks: snapshot.askTicks))
    }
}

/// The complete, synchronous simulation state: all markets plus the trading
/// account, advanced in lockstep by one clock. A value type — deterministic,
/// directly testable and `Codable` for saving the session.
/// `SimulationEngine` serialises access to it off the main actor.
public struct SimulationState: Sendable, Equatable, Codable {
    public static let defaultSeed: UInt64 = 2026_10_13

    public private(set) var sequence = 0
    public private(set) var revision = 0
    public private(set) var seed: UInt64
    public private(set) var clock: SimulatedClock
    public private(set) var markets: [MarketSymbol: MarketSimulator]
    public private(set) var account: TradingAccount

    public init(seed: UInt64 = SimulationState.defaultSeed,
                account: TradingAccount = TradingAccount(),
                clock: SimulatedClock = SimulatedClock()) {
        self.seed = seed
        self.clock = clock
        var markets: [MarketSymbol: MarketSimulator] = [:]
        for symbol in MarketSymbol.allCases {
            markets[symbol] = MarketSimulator(symbol: symbol, seed: Self.marketSeed(seed, symbol))
        }
        self.markets = markets
        self.account = account
    }

    /// Stable per-market seed derived from the session seed.
    static func marketSeed(_ seed: UInt64, _ symbol: MarketSymbol) -> UInt64 {
        let salt: UInt64 = switch symbol {
        case .gc: 0x4743
        case .nq: 0x4E51
        case .es: 0x4553
        case .cl: 0x434C
        }
        return seed &* 0x9E37_79B9 &+ salt
    }

    public var time: Date { clock.time(at: sequence) }
    public var stamp: Stamp { Stamp(sequence: sequence, time: time) }

    /// Advances every market by one update, then lets the account execute
    /// working orders the new market state reached.
    public mutating func advance() {
        for symbol in MarketSymbol.allCases { markets[symbol]?.advance() }
        sequence += 1
        revision += 1
        for symbol in MarketSymbol.allCases where account.hasOpenOrders(symbol) {
            account.process(market: marketView(symbol))
        }
    }

    /// Restarts every market with a new seed and resets the account.
    public mutating func resetSession(seed newSeed: UInt64, configuration: AccountConfiguration? = nil) {
        let nextRevision = revision + 1
        var account = account
        account.reset(configuration: configuration, at: Stamp(sequence: 0, time: clock.time(at: 0)))
        self = SimulationState(seed: newSeed, account: account, clock: clock)
        revision = nextRevision
    }

    /// Restarts every market with a new seed. The account is kept.
    public mutating func resetMarkets(seed newSeed: UInt64) {
        let nextRevision = revision + 1
        self = SimulationState(seed: newSeed, account: account, clock: clock)
        revision = nextRevision
    }

    /// Loads a scripted scenario into its market; other markets continue.
    public mutating func load(_ scenario: MarketScenario, seed: UInt64? = nil) {
        markets[scenario.symbol]?.load(scenario, seed: seed)
        revision += 1
    }

    // MARK: Trading commands

    @discardableResult
    public mutating func submit(_ request: OrderRequest) -> OrderResult {
        let result = account.submit(request, market: marketView(request.symbol), quotes: quotes())
        revision += 1
        return result
    }

    @discardableResult
    public mutating func cancel(orderID: Int) -> Bool {
        let cancelled = account.cancel(orderID: orderID, at: stamp)
        if cancelled { revision += 1 }
        return cancelled
    }

    public mutating func cancelAll(symbol: MarketSymbol? = nil) {
        account.cancelAll(symbol: symbol, at: stamp)
        revision += 1
    }

    @discardableResult
    public mutating func closePosition(_ symbol: MarketSymbol) -> OrderResult? {
        let result = account.closePosition(market: marketView(symbol))
        revision += 1
        return result
    }

    /// Cancels every order and closes every position.
    public mutating func flattenAll() {
        account.cancelAll(at: stamp)
        for symbol in MarketSymbol.allCases where account.position(symbol) != nil {
            account.closePosition(market: marketView(symbol))
        }
        revision += 1
    }

    @discardableResult
    public mutating func setProtection(_ symbol: MarketSymbol, stopLoss: Double?, takeProfit: Double?) -> [OrderResult] {
        let results = account.setProtection(stopLoss: stopLoss, takeProfit: takeProfit, market: marketView(symbol))
        revision += 1
        return results
    }

    public mutating func resetAccount(configuration: AccountConfiguration? = nil) {
        account.reset(configuration: configuration, at: stamp)
        revision += 1
    }

    @discardableResult
    public mutating func updateConfiguration(_ configuration: AccountConfiguration) -> [String] {
        let errors = account.updateConfiguration(configuration, at: stamp)
        revision += 1
        return errors
    }

    // MARK: Views

    public func snapshot(_ symbol: MarketSymbol) -> MarketSnapshot {
        guard let market = markets[symbol] else { preconditionFailure("No market for \(symbol)") }
        return market.snapshot(frameSequence: sequence)
    }

    /// What the trading engine sees of one market right now.
    public func marketView(_ symbol: MarketSymbol) -> MarketView {
        guard let market = markets[symbol] else { preconditionFailure("No market for \(symbol)") }
        let book = market.book
        return MarketView(symbol: symbol, sequence: sequence, time: time,
                          bidTicks: book.bestBid, askTicks: book.bestAsk, lastTicks: market.lastTicks,
                          bids: book.bids.map { PriceLevel(priceTicks: $0.priceTicks, size: $0.size) },
                          asks: book.asks.map { PriceLevel(priceTicks: $0.priceTicks, size: $0.size) })
    }

    public func quotes() -> [MarketSymbol: Quote] {
        markets.mapValues { Quote(bidTicks: $0.book.bestBid, askTicks: $0.book.bestAsk) }
    }

    public func frame() -> SimulationFrame {
        var snapshots: [MarketSymbol: MarketSnapshot] = [:]
        for (symbol, market) in markets { snapshots[symbol] = market.snapshot(frameSequence: sequence) }
        return SimulationFrame(sequence: sequence, revision: revision, time: time, markets: snapshots, account: account)
    }
}

/// Serialises access to `SimulationState` off the main actor. The UI never
/// touches mutable simulation state; it receives immutable frames.
public actor SimulationEngine {
    private var state: SimulationState

    public init(state: SimulationState) {
        self.state = state
    }

    public func frame() -> SimulationFrame { state.frame() }

    /// The full state, for saving the session.
    public func exportState() -> SimulationState { state }

    public func advance(steps: Int = 1) -> SimulationFrame {
        for _ in 0..<max(0, steps) { state.advance() }
        return state.frame()
    }

    public func resetMarkets(seed: UInt64) -> SimulationFrame {
        state.resetMarkets(seed: seed)
        return state.frame()
    }

    public func resetSession(seed: UInt64, configuration: AccountConfiguration?) -> SimulationFrame {
        state.resetSession(seed: seed, configuration: configuration)
        return state.frame()
    }

    public func load(_ scenario: MarketScenario) -> SimulationFrame {
        state.load(scenario)
        return state.frame()
    }

    public func submit(_ request: OrderRequest) -> (OrderResult, SimulationFrame) {
        let result = state.submit(request)
        return (result, state.frame())
    }

    public func cancel(orderID: Int) -> (Bool, SimulationFrame) {
        let cancelled = state.cancel(orderID: orderID)
        return (cancelled, state.frame())
    }

    public func cancelAll(symbol: MarketSymbol?) -> SimulationFrame {
        state.cancelAll(symbol: symbol)
        return state.frame()
    }

    public func closePosition(_ symbol: MarketSymbol) -> (OrderResult?, SimulationFrame) {
        let result = state.closePosition(symbol)
        return (result, state.frame())
    }

    public func flattenAll() -> SimulationFrame {
        state.flattenAll()
        return state.frame()
    }

    public func setProtection(_ symbol: MarketSymbol, stopLoss: Double?, takeProfit: Double?) -> ([OrderResult], SimulationFrame) {
        let results = state.setProtection(symbol, stopLoss: stopLoss, takeProfit: takeProfit)
        return (results, state.frame())
    }

    public func resetAccount(configuration: AccountConfiguration?) -> SimulationFrame {
        state.resetAccount(configuration: configuration)
        return state.frame()
    }

    public func updateConfiguration(_ configuration: AccountConfiguration) -> ([String], SimulationFrame) {
        let errors = state.updateConfiguration(configuration)
        return (errors, state.frame())
    }
}
