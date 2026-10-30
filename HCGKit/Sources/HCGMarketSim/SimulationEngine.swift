import Foundation
import HCGDomain

/// Everything the UI needs from one moment of the simulation, produced by a
/// single clock: every market snapshot in a frame carries the same
/// `sequence`, so connected panels can never drift apart.
public struct SimulationFrame: Sendable, Equatable {
    /// Number of clock updates since the session started.
    public let sequence: Int
    /// Monotonic counter of every state change (updates, orders, resets).
    /// Used to discard out-of-order deliveries.
    public let revision: Int
    public let markets: [MarketSymbol: MarketSnapshot]
    public let account: SimulatedAccount

    public subscript(symbol: MarketSymbol) -> MarketSnapshot {
        guard let snapshot = markets[symbol] else {
            preconditionFailure("SimulationFrame has no market for \(symbol)")
        }
        return snapshot
    }

    public var equity: Double { account.equity(markets) }
}

/// The complete, synchronous simulation state: all markets plus the account,
/// advanced in lockstep by one clock. A value type — deterministic and
/// directly testable. `SimulationEngine` serialises access to it off the main actor.
public struct SimulationState: Sendable, Equatable {
    public static let defaultSeed: UInt64 = 2026_10_13

    public private(set) var sequence = 0
    public private(set) var revision = 0
    public private(set) var seed: UInt64
    public private(set) var markets: [MarketSymbol: MarketSimulator]
    public private(set) var account: SimulatedAccount

    public init(seed: UInt64 = SimulationState.defaultSeed, startingBalance: Double = 50_000) {
        self.seed = seed
        var markets: [MarketSymbol: MarketSimulator] = [:]
        for symbol in MarketSymbol.allCases {
            markets[symbol] = MarketSimulator(symbol: symbol, seed: Self.marketSeed(seed, symbol))
        }
        self.markets = markets
        self.account = SimulatedAccount(startingBalance: startingBalance)
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

    /// Advances every market by one update.
    public mutating func advance() {
        for symbol in MarketSymbol.allCases { markets[symbol]?.advance() }
        sequence += 1
        revision += 1
    }

    /// Restarts every market with a new seed and a fresh account.
    public mutating func reset(seed: UInt64) {
        let nextRevision = revision + 1
        self = SimulationState(seed: seed, startingBalance: account.startingBalance)
        revision = nextRevision
    }

    /// Loads a scripted scenario into its market; other markets continue.
    public mutating func load(_ scenario: MarketScenario, seed: UInt64? = nil) {
        markets[scenario.symbol]?.load(scenario, seed: seed)
        revision += 1
    }

    @discardableResult
    public mutating func submit(_ order: MarketOrder) throws(OrderRejection) -> Fill {
        let snapshot = snapshot(order.symbol)
        let fill = try account.execute(order, against: snapshot,
                                       commissionPerContract: commission(order.symbol))
        revision += 1
        return fill
    }

    @discardableResult
    public mutating func flatten(_ symbol: MarketSymbol) throws(OrderRejection) -> Fill {
        let fill = try account.flatten(against: snapshot(symbol), commissionPerContract: commission(symbol))
        revision += 1
        return fill
    }

    public func snapshot(_ symbol: MarketSymbol) -> MarketSnapshot {
        guard let market = markets[symbol] else { preconditionFailure("No market for \(symbol)") }
        return market.snapshot(frameSequence: sequence)
    }

    public func frame() -> SimulationFrame {
        var snapshots: [MarketSymbol: MarketSnapshot] = [:]
        for (symbol, market) in markets { snapshots[symbol] = market.snapshot(frameSequence: sequence) }
        return SimulationFrame(sequence: sequence, revision: revision, markets: snapshots, account: account)
    }

    private func commission(_ symbol: MarketSymbol) -> Double {
        markets[symbol]?.profile.commissionPerContract ?? 0
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

    public func advance(steps: Int = 1) -> SimulationFrame {
        for _ in 0..<max(0, steps) { state.advance() }
        return state.frame()
    }

    public func reset(seed: UInt64) -> SimulationFrame {
        state.reset(seed: seed)
        return state.frame()
    }

    public func load(_ scenario: MarketScenario) -> SimulationFrame {
        state.load(scenario)
        return state.frame()
    }

    public func submit(_ order: MarketOrder) -> (Result<Fill, OrderRejection>, SimulationFrame) {
        let result = Result { () throws(OrderRejection) -> Fill in try state.submit(order) }
        return (result, state.frame())
    }

    public func flatten(_ symbol: MarketSymbol) -> (Result<Fill, OrderRejection>, SimulationFrame) {
        let result = Result { () throws(OrderRejection) -> Fill in try state.flatten(symbol) }
        return (result, state.frame())
    }
}
