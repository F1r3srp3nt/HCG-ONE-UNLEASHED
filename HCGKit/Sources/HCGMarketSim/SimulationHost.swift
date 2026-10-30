import Foundation
import HCGDomain
import Observation

/// Playback speeds offered by the simulation clock.
public enum SimulationSpeed: Double, CaseIterable, Sendable, Identifiable, Comparable {
    case quarter = 0.25
    case half = 0.5
    case normal = 1
    case double = 2
    case quadruple = 4
    case octuple = 8

    public var id: Double { rawValue }

    public var label: String {
        switch self {
        case .quarter: "0.25×"
        case .half: "0.5×"
        case .normal: "1×"
        case .double: "2×"
        case .quadruple: "4×"
        case .octuple: "8×"
        }
    }

    /// Wall-clock time between market updates (0.5 s at 1×, as in HCG ONE).
    public var interval: Duration { .milliseconds(Int((500 / rawValue).rounded())) }

    public var faster: SimulationSpeed? { Self.allCases.first { $0 > self } }
    public var slower: SimulationSpeed? { Self.allCases.last { $0 < self } }

    public static func < (lhs: SimulationSpeed, rhs: SimulationSpeed) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the clock waits on between updates. Injected so tests can run the
/// real playback loop without real time.
public protocol SimulationTicker: Sendable {
    func wait(for duration: Duration) async throws
}

public struct ContinuousTicker: SimulationTicker {
    public init() {}
    public func wait(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// The app's single simulation clock and the UI's only view of the market.
///
/// One playback loop advances every market together inside `SimulationEngine`
/// (an actor, off the main actor) and publishes the resulting immutable frame
/// here on the main actor. Every panel reads `frame`, so they always agree.
@MainActor
@Observable
public final class SimulationHost {
    public private(set) var frame: SimulationFrame
    public private(set) var isPlaying = false
    public private(set) var speed: SimulationSpeed
    /// Outcome of the most recent simulated order, for the ticket UI.
    public private(set) var lastOrderMessage: String?

    @ObservationIgnored private let engine: SimulationEngine
    @ObservationIgnored private let ticker: any SimulationTicker
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// A loop that was cancelled but may still be delivering its last frame.
    @ObservationIgnored private var finishingLoop: Task<Void, Never>?

    public init(seed: UInt64 = SimulationState.defaultSeed,
                speed: SimulationSpeed = .normal,
                ticker: any SimulationTicker = ContinuousTicker()) {
        let state = SimulationState(seed: seed)
        self.frame = state.frame()
        self.speed = speed
        self.ticker = ticker
        self.engine = SimulationEngine(state: state)
    }

    public func snapshot(_ symbol: MarketSymbol) -> MarketSnapshot { frame[symbol] }

    // MARK: Playback

    public func play() {
        guard !isPlaying else { return }
        isPlaying = true
        let previous = finishingLoop
        finishingLoop = nil
        loop = Task { [weak self] in
            await previous?.value
            await self?.runLoop()
        }
    }

    /// Stops the clock. A market update already in flight still delivers its
    /// frame, so the UI always shows the engine's true state.
    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        loop?.cancel()
        finishingLoop = loop
        loop = nil
    }

    /// Pauses and waits until the loop has fully stopped.
    public func pauseAndWait() async {
        pause()
        await finishingLoop?.value
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func setSpeed(_ newSpeed: SimulationSpeed) { speed = newSpeed }
    public func faster() { if let next = speed.faster { speed = next } }
    public func slower() { if let next = speed.slower { speed = next } }

    /// One manual update while paused.
    public func step() async {
        guard !isPlaying else { return }
        publish(await engine.advance())
    }

    public func reset(seed: UInt64 = SimulationState.defaultSeed) async {
        await pauseAndWait()
        lastOrderMessage = nil
        publish(await engine.reset(seed: seed))
    }

    public func load(_ scenario: MarketScenario) async {
        publish(await engine.load(scenario))
    }

    // MARK: Simulated orders

    public func submit(_ order: MarketOrder) async {
        let (result, newFrame) = await engine.submit(order)
        publish(newFrame)
        lastOrderMessage = Self.describe(result)
    }

    public func flatten(_ symbol: MarketSymbol) async {
        let (result, newFrame) = await engine.flatten(symbol)
        publish(newFrame)
        lastOrderMessage = Self.describe(result)
    }

    // MARK: Internals

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await ticker.wait(for: speed.interval)
            } catch {
                return // cancelled while waiting
            }
            if Task.isCancelled { return }
            publish(await engine.advance())
        }
    }

    /// Frames can arrive out of order when an order and a clock update race;
    /// only newer state is ever shown.
    private func publish(_ newFrame: SimulationFrame) {
        guard newFrame.revision > frame.revision else { return }
        frame = newFrame
    }

    private static func describe(_ result: Result<Fill, OrderRejection>) -> String {
        switch result {
        case .success(let fill):
            let price = PriceFormat.price(fill.averagePrice, decimals: fill.symbol.spec.priceDecimals)
            return "Simulated \(fill.side.label.lowercased()) \(fill.quantity) \(fill.symbol.ticker) filled at \(price)"
        case .failure(let rejection):
            return rejection.description
        }
    }
}
