import Foundation
import HCGDomain
import HCGTrading
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
///
/// When given a `SessionPersistence`, the host restores the saved session at
/// launch and saves it in the background: soon after any account change, and
/// at most every `marketSaveInterval` for market-only changes. Call
/// `saveNow()` before the app quits.
@MainActor
@Observable
public final class SimulationHost {
    public private(set) var frame: SimulationFrame
    /// The account, republished only when it changes (orders, fills, resets),
    /// so order and history views do not re-render on every market update.
    public private(set) var account: TradingAccount
    public private(set) var isPlaying = false
    public private(set) var speed: SimulationSpeed
    /// Outcome of the most recent simulated order action, for the ticket UI.
    public private(set) var lastOrderMessage: String?
    /// Shown once after launch: restored session, or recovery from an unreadable file.
    public private(set) var restoreNotice: String?
    /// Last save failure, if any (saving is retried on the next change).
    public private(set) var lastSaveError: String?

    @ObservationIgnored private let engine: SimulationEngine
    @ObservationIgnored private let ticker: any SimulationTicker
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// A loop that was cancelled but may still be delivering its last frame.
    @ObservationIgnored private var finishingLoop: Task<Void, Never>?

    @ObservationIgnored private let writer: SessionWriter?
    @ObservationIgnored private var autosave: Task<Void, Never>?
    @ObservationIgnored private let autosaveInterval: Duration
    @ObservationIgnored private let marketSaveInterval: Duration
    @ObservationIgnored private var savedAccountRevision: Int
    @ObservationIgnored private var savedRevision: Int
    @ObservationIgnored private var lastSave = ContinuousClock.now

    /// - Parameters:
    ///   - persistence: where to load and save the session; `nil` keeps
    ///     everything in memory (tests, previews).
    public init(seed: UInt64 = SimulationState.defaultSeed,
                speed: SimulationSpeed = .normal,
                ticker: any SimulationTicker = ContinuousTicker(),
                persistence: SessionPersistence? = nil,
                autosaveInterval: Duration = .seconds(1),
                marketSaveInterval: Duration = .seconds(30)) {
        var state = SimulationState(seed: seed)
        var notice: String?
        if let persistence {
            switch persistence.load() {
            case .fresh:
                break
            case .restored(let saved, let savedAt):
                state = saved
                notice = "Restored your simulated session (saved \(savedAt.formatted(date: .abbreviated, time: .shortened)))."
            case .recovered(let backup, let reason):
                notice = "\(reason) A new simulated session was started." + (backup.map { " The old file was kept as \($0.lastPathComponent)." } ?? "")
            }
        }
        self.frame = state.frame()
        self.account = state.account
        self.speed = speed
        self.ticker = ticker
        self.engine = SimulationEngine(state: state)
        self.restoreNotice = notice
        self.writer = persistence.map(SessionWriter.init(persistence:))
        self.autosaveInterval = autosaveInterval
        self.marketSaveInterval = marketSaveInterval
        self.savedAccountRevision = state.account.revision
        self.savedRevision = state.revision
        if writer != nil { startAutosave() }
    }

    public func snapshot(_ symbol: MarketSymbol) -> MarketSnapshot { frame[symbol] }

    public func dismissRestoreNotice() { restoreNotice = nil }

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

    /// Changes the playback speed. While playing, the pending wait is
    /// restarted so the new speed applies immediately.
    public func setSpeed(_ newSpeed: SimulationSpeed) {
        guard newSpeed != speed else { return }
        speed = newSpeed
        if isPlaying {
            pause()
            play()
        }
    }

    public func faster() { if let next = speed.faster { setSpeed(next) } }
    public func slower() { if let next = speed.slower { setSpeed(next) } }

    /// One manual update while paused.
    public func step() async {
        guard !isPlaying else { return }
        publish(await engine.advance())
    }

    /// Restarts every market **and** resets the simulated account. Playback
    /// resumes if it was running.
    public func reset(seed: UInt64 = SimulationState.defaultSeed, configuration: AccountConfiguration? = nil) async {
        let wasPlaying = isPlaying
        await pauseAndWait()
        lastOrderMessage = nil
        publish(await engine.resetSession(seed: seed, configuration: configuration))
        if wasPlaying { play() }
    }

    public func load(_ scenario: MarketScenario) async {
        publish(await engine.load(scenario))
    }

    // MARK: Simulated trading

    @discardableResult
    public func submit(_ request: OrderRequest) async -> OrderResult {
        let (result, newFrame) = await engine.submit(request)
        publish(newFrame)
        lastOrderMessage = Self.describe(result, account: newFrame.account)
        return result
    }

    @discardableResult
    public func cancel(orderID: Int) async -> Bool {
        let (cancelled, newFrame) = await engine.cancel(orderID: orderID)
        publish(newFrame)
        lastOrderMessage = cancelled ? "Simulated order #\(orderID) cancelled." : "Order #\(orderID) is no longer open."
        return cancelled
    }

    public func cancelAll(symbol: MarketSymbol? = nil) async {
        publish(await engine.cancelAll(symbol: symbol))
        lastOrderMessage = symbol.map { "All simulated \($0.ticker) orders cancelled." } ?? "All simulated orders cancelled."
    }

    /// Closes the position in `symbol` at market.
    public func closePosition(_ symbol: MarketSymbol) async {
        let (result, newFrame) = await engine.closePosition(symbol)
        publish(newFrame)
        lastOrderMessage = result.map { Self.describe($0, account: newFrame.account) }
            ?? "There is no open simulated \(symbol.ticker) position."
    }

    /// Previous name kept for the Order Flow ticket.
    public func flatten(_ symbol: MarketSymbol) async { await closePosition(symbol) }

    /// Cancels every order and closes every position.
    public func flattenAll() async {
        publish(await engine.flattenAll())
        lastOrderMessage = "All simulated orders cancelled and positions closed."
    }

    @discardableResult
    public func setProtection(_ symbol: MarketSymbol, stopLoss: Double?, takeProfit: Double?) async -> [OrderResult] {
        let (results, newFrame) = await engine.setProtection(symbol, stopLoss: stopLoss, takeProfit: takeProfit)
        publish(newFrame)
        if newFrame.account.position(symbol) == nil {
            lastOrderMessage = "There is no open simulated \(symbol.ticker) position to protect."
        } else if results.isEmpty {
            lastOrderMessage = "Simulated \(symbol.ticker) stop-loss and take-profit removed."
        } else {
            lastOrderMessage = results.map { Self.describe($0, account: newFrame.account) }.joined(separator: " ")
        }
        return results
    }

    /// Resets only the simulated account (markets keep running).
    public func resetAccount(configuration: AccountConfiguration? = nil) async {
        publish(await engine.resetAccount(configuration: configuration))
        lastOrderMessage = "Simulated account reset."
    }

    /// Applies new costs, slippage and risk limits. Returns validation errors.
    @discardableResult
    public func updateConfiguration(_ configuration: AccountConfiguration) async -> [String] {
        let (errors, newFrame) = await engine.updateConfiguration(configuration)
        publish(newFrame)
        return errors
    }

    // MARK: Persistence

    /// Saves the session now (call before quitting).
    public func saveNow() async {
        guard let writer else { return }
        let state = await engine.exportState()
        do {
            try await writer.save(state, savedAt: Date())
            savedAccountRevision = state.account.revision
            savedRevision = state.revision
            lastSave = ContinuousClock.now
            lastSaveError = nil
        } catch {
            lastSaveError = "The simulated session could not be saved: \(error.localizedDescription)"
        }
    }

    private func startAutosave() {
        autosave = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.autosaveInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await self.saveIfNeeded()
            }
        }
    }

    /// Account changes are saved promptly; market-only changes at most every
    /// `marketSaveInterval`, so a running simulation does not write constantly.
    private func saveIfNeeded() async {
        let accountChanged = frame.account.revision != savedAccountRevision
        let marketChanged = frame.revision != savedRevision
        let marketDue = ContinuousClock.now - lastSave >= marketSaveInterval
        if accountChanged || (marketChanged && marketDue) {
            await saveNow()
        }
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
        if newFrame.account.revision != account.revision {
            account = newFrame.account
        }
    }

    static func describe(_ result: OrderResult, account: TradingAccount) -> String {
        let order = result.order
        let spec = order.symbol.spec
        let name = account.describe(order)
        switch order.status {
        case .rejected:
            return "Rejected: \(order.statusReason ?? "invalid order")"
        case .filled:
            let price = order.averageFillPrice.map { PriceFormat.price($0, decimals: spec.priceDecimals + 1) } ?? "—"
            return "Simulated \(name) filled at \(price)."
        case .partiallyFilled:
            return "Simulated \(name): \(order.filledQuantity) filled, \(order.remainingQuantity) working."
        case .working, .accepted:
            return "Simulated \(name) is working."
        case .cancelled:
            let filled = order.filledQuantity > 0 ? " after \(order.filledQuantity) filled" : ""
            return "Simulated \(name) cancelled\(filled): \(order.statusReason ?? "")"
        }
    }
}
