import Foundation
import HCGCharting
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
    /// Candles for every timeframe, per market, built from the simulated trades.
    public let charts: [MarketSymbol: ChartHistory]

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

    public var riskStatus: RiskStatus { account.riskStatus(quotes: quotes) }

    /// The engine's view of one market's book in this frame, for previews
    /// such as the queue estimate (no prints: those belong to execution).
    public func marketView(_ symbol: MarketSymbol) -> MarketView {
        let s = self[symbol]
        return MarketView(symbol: symbol, sequence: sequence, time: time,
                          bidTicks: s.bidTicks, askTicks: s.askTicks, lastTicks: s.lastTicks,
                          bids: s.bids.map { PriceLevel(priceTicks: $0.priceTicks, size: $0.size) },
                          asks: s.asks.map { PriceLevel(priceTicks: $0.priceTicks, size: $0.size) })
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
    /// Candles per market. Optional so sessions saved before charts existed
    /// still load (they start with empty charts).
    private var chartStore: [MarketSymbol: ChartHistory]?

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
        self.chartStore = Self.emptyCharts()
    }

    static func emptyCharts() -> [MarketSymbol: ChartHistory] {
        Dictionary(uniqueKeysWithValues: MarketSymbol.allCases.map { ($0, ChartHistory()) })
    }

    /// A fresh session whose markets have already run for `history`
    /// simulated seconds, ending at `sessionStart`, so charts open with
    /// candles. The account takes no part in the history.
    public static func prepared(seed: UInt64 = SimulationState.defaultSeed,
                                account: TradingAccount = TradingAccount(),
                                history: Int,
                                sessionStart: Date = SimulatedClock.defaultStart) -> SimulationState {
        let updates = max(0, history)
        var state = SimulationState(seed: seed, account: account,
                                    clock: SimulatedClock(start: sessionStart.addingTimeInterval(-Double(updates))))
        for _ in 0..<updates { state.advanceMarkets() }
        return state
    }

    public func chart(_ symbol: MarketSymbol) -> ChartHistory {
        chartStore?[symbol] ?? ChartHistory()
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
        advanceMarkets()
        for symbol in MarketSymbol.allCases where account.hasOpenOrders(symbol) {
            account.process(market: marketView(symbol))
        }
        enforceRisk()
    }

    /// Moves every market one update and adds its trades to the charts.
    mutating func advanceMarkets() {
        for symbol in MarketSymbol.allCases { markets[symbol]?.advance() }
        sequence += 1
        revision += 1
        feedCharts()
    }

    /// The update covers the simulated second before `time`; its trades are
    /// spread evenly across that second, in the order they printed.
    private mutating func feedCharts() {
        if chartStore == nil { chartStore = Self.emptyCharts() }
        let updateStart = clock.time(at: sequence - 1)
        for symbol in MarketSymbol.allCases {
            let trades = latestTrades(symbol)
            guard !trades.isEmpty else { continue }
            let step = clock.secondsPerUpdate / Double(trades.count + 1)
            for (i, trade) in trades.enumerated() {
                // Mutated in place: no copy of the stored candles per trade.
                chartStore?[symbol, default: ChartHistory()].add(
                    TradeEvent(time: updateStart.addingTimeInterval(step * Double(i + 1)),
                               priceTicks: trade.priceTicks, size: trade.size,
                               aggressor: trade.aggressor == .buy ? .buy : .sell))
            }
        }
    }

    /// Trades of a market's latest update (recorded before its step counter advanced).
    private func latestTrades(_ symbol: MarketSymbol) -> [TapeTrade] {
        guard let market = markets[symbol] else { return [] }
        let step = market.marketStep - 1
        return Array(market.tape.reversed().prefix { $0.marketStep == step }.reversed())
    }

    /// Applies the account's risk rules (daily loss, trailing drawdown,
    /// margin liquidation) against the current markets.
    private mutating func enforceRisk() {
        guard account.needsRiskCheck(at: time) else { return }
        var views: [MarketSymbol: MarketView] = [:]
        for symbol in MarketSymbol.allCases { views[symbol] = marketView(symbol) }
        account.enforceRisk(markets: views)
    }

    /// Restarts every market with a new seed and resets the account.
    /// With `history` > 0 the new markets first run that many simulated
    /// seconds, ending at the session start (see `prepared`).
    public mutating func resetSession(seed newSeed: UInt64, configuration: AccountConfiguration? = nil, history: Int = 0) {
        let nextRevision = revision + 1
        var account = account
        if history > 0 {
            account.reset(configuration: configuration, at: Stamp(sequence: history, time: SimulatedClock.defaultStart))
            self = SimulationState.prepared(seed: newSeed, account: account, history: history)
        } else {
            account.reset(configuration: configuration, at: Stamp(sequence: 0, time: clock.time(at: 0)))
            self = SimulationState(seed: newSeed, account: account, clock: clock)
        }
        revision = max(revision, nextRevision)
    }

    /// Replaces an untouched session's markets with ones that have run
    /// `history` simulated seconds; the account is kept as it is.
    mutating func prepareHistory(_ history: Int) {
        let nextRevision = revision + 1
        self = SimulationState.prepared(seed: seed, account: account, history: history)
        revision = max(revision, nextRevision)
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
        // The scenario restarts this market's price path, so its chart restarts too.
        var charts = chartStore ?? Self.emptyCharts()
        charts[scenario.symbol] = ChartHistory()
        chartStore = charts
        revision += 1
    }

    // MARK: Trading commands

    @discardableResult
    public mutating func submit(_ request: OrderRequest) -> OrderResult {
        let result = account.submit(request, market: marketView(request.symbol), quotes: quotes())
        enforceRisk()
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
        enforceRisk()
        revision += 1
        return result
    }

    /// Cancels every order and closes every position.
    public mutating func flattenAll() {
        account.cancelAll(at: stamp)
        for symbol in MarketSymbol.allCases where account.position(symbol) != nil {
            account.closePosition(market: marketView(symbol))
        }
        enforceRisk()
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
        let prints = latestTrades(symbol).map {
            TradePrint(priceTicks: $0.priceTicks, size: $0.size, aggressor: $0.aggressor == .buy ? .buy : .sell)
        }
        return MarketView(symbol: symbol, sequence: sequence, time: time,
                          bidTicks: book.bestBid, askTicks: book.bestAsk, lastTicks: market.lastTicks,
                          bids: book.bids.map { PriceLevel(priceTicks: $0.priceTicks, size: $0.size) },
                          asks: book.asks.map { PriceLevel(priceTicks: $0.priceTicks, size: $0.size) },
                          prints: prints)
    }

    public func quotes() -> [MarketSymbol: Quote] {
        markets.mapValues { Quote(bidTicks: $0.book.bestBid, askTicks: $0.book.bestAsk) }
    }

    public func frame() -> SimulationFrame {
        var snapshots: [MarketSymbol: MarketSnapshot] = [:]
        for (symbol, market) in markets { snapshots[symbol] = market.snapshot(frameSequence: sequence) }
        return SimulationFrame(sequence: sequence, revision: revision, time: time, markets: snapshots, account: account,
                               charts: chartStore ?? Self.emptyCharts())
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

    public func resetSession(seed: UInt64, configuration: AccountConfiguration?, history: Int = 0) -> SimulationFrame {
        state.resetSession(seed: seed, configuration: configuration, history: history)
        return state.frame()
    }

    /// Gives an untouched session `history` simulated seconds of market
    /// history (see `SimulationState.prepared`).
    public func prepareHistory(_ history: Int) -> SimulationFrame {
        state.prepareHistory(history)
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
