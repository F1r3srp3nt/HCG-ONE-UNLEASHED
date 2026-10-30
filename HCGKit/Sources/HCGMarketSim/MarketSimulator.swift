import Foundation
import HCGDomain

// Ported from HCG-One@b4f0e29: ios-hcg/HCGONE/TradingLab/MarketEngine.swift.
//
// Changes from the iOS engine (see docs/M1_IMPLEMENTATION_REPORT.md §4):
// - prices are whole ticks (Int64), so book arithmetic is exact;
// - the order book keeps both sides contiguous around one quote, fixing the
//   spread that widened on every price move;
// - the spread is modelled explicitly: a per-instrument base that widens
//   under liquidity pulls and volatility and decays back;
// - an aggressor's price impact follows its side (a sell moves price down);
//   the iOS sign test pushed sells up whenever drift was not positive;
// - no wall-clock time, no `Int.random`: everything derives from the seed;
// - no main actor, no UI framework: a plain value type.

/// One simulated futures market. A value type: copying it forks the market.
///
/// Every update executes trades against the resting book; the tape, bars,
/// VWAP and cumulative delta are projections of those same trades.
public struct MarketSimulator: Sendable, Equatable {
    public let symbol: MarketSymbol
    public let spec: InstrumentSpec
    public let profile: SimulationProfile
    public private(set) var seed: UInt64

    public private(set) var marketStep = 0
    public private(set) var lastTicks: Int64
    public private(set) var sessionOpenTicks: Int64

    private var rng: SeededRNG
    private(set) var book: OrderBook
    private var extraSpreadTicks = 0

    private(set) var tape: [TapeTrade] = []
    private(set) var bars: [PriceBar] = []
    private var barUpdatesLeft = 0
    private var tradeCounter = 0
    private var barCounter = 0
    private var vwapNumerator = 0.0
    private var vwapDenominator = 0
    private var cumulativeDelta = 0
    private var totalVolume = 0

    // Flow regime (free market defaults, or the current scenario phase).
    private var drift = 0.0
    private var aggressorBias = 0.0
    private var volatility = 1.0
    private var replenishRate = 0.35

    // Scenario scripting.
    public private(set) var scenario: MarketScenario?
    private var phaseIndex = 0
    private var phaseUpdatesLeft = 0
    private var pendingEvents: [ScenarioEvent] = []
    public private(set) var scenarioComplete = false

    static let tapeLimit = 200
    static let barLimit = 160
    static let snapshotTrades = 40

    public init(symbol: MarketSymbol, seed: UInt64, profile: SimulationProfile? = nil) {
        let profile = profile ?? .standard(for: symbol)
        let spec = symbol.spec
        let startTicks = spec.ticks(price: profile.sessionStartPrice)
        var rng = SeededRNG(seed: seed)
        self.symbol = symbol
        self.spec = spec
        self.profile = profile
        self.seed = seed
        self.lastTicks = startTicks
        self.sessionOpenTicks = startTicks
        self.book = OrderBook(bestBid: startTicks - Int64(profile.baseSpreadTicks), spreadTicks: profile.baseSpreadTicks,
                              depth: profile.bookDepth, restingSize: profile.restingSize, rng: &rng)
        self.rng = rng
        openBar()
    }

    // MARK: Session control

    /// Starts a fresh free-market session with `seed`.
    public mutating func reset(seed: UInt64) {
        self = MarketSimulator(symbol: symbol, seed: seed, profile: profile)
    }

    /// Starts a scripted scenario. The default seed makes every replay identical.
    public mutating func load(_ scenario: MarketScenario, seed: UInt64? = nil) {
        reset(seed: seed ?? scenario.defaultSeed)
        self.scenario = scenario
        beginPhase(0)
    }

    // MARK: Update

    /// Advances the market by one update.
    public mutating func advance() {
        progressScenario()

        let trades = rng.range(2, 7)
        for _ in 0..<trades { executeOneTrade() }

        book.replenish(typicalSize: typicalSize, rate: replenishRate)
        updateSpread()

        marketStep += 1
        barUpdatesLeft -= 1
        if barUpdatesLeft <= 0 { openBar() }
    }

    // MARK: Snapshot

    public func snapshot(frameSequence: Int) -> MarketSnapshot {
        MarketSnapshot(
            symbol: symbol,
            spec: spec,
            frameSequence: frameSequence,
            marketStep: marketStep,
            lastTicks: lastTicks,
            bidTicks: book.bestBid,
            askTicks: book.bestAsk,
            sessionOpenTicks: sessionOpenTicks,
            bids: book.bids,
            asks: book.asks,
            bars: bars,
            recentTrades: Array(tape.suffix(Self.snapshotTrades)),
            vwapTicks: vwapDenominator > 0 ? vwapNumerator / Double(vwapDenominator) : nil,
            cumulativeDelta: cumulativeDelta,
            totalVolume: totalVolume,
            scenarioID: scenario?.id,
            scenarioPhase: scenario == nil ? nil : phaseIndex,
            scenarioPhaseCount: scenario?.phases.count ?? 0,
            scenarioComplete: scenarioComplete
        )
    }

    /// Book invariant violations; empty when the market is valid.
    public func bookViolations() -> [String] {
        var problems = book.violations()
        let spread = book.spreadTicks
        if spread < profile.baseSpreadTicks || spread > profile.maxSpreadTicks {
            problems.append("spread \(spread) outside \(profile.baseSpreadTicks)...\(profile.maxSpreadTicks)")
        }
        return problems
    }

    // MARK: Trades

    private var typicalSize: Int { (profile.restingSize.lowerBound + profile.restingSize.upperBound) / 2 }

    private mutating func executeOneTrade() {
        // Aggressor choice: scenario bias + drift + small noise (iOS model).
        let pBuy = 0.5 + aggressorBias * 0.35 + drift * 0.10 + rng.next() * 0.06 - 0.03
        let isBuy = rng.next() < min(0.95, max(0.05, pBuy))

        // Price impact: with a probability tied to drift and volatility the
        // quote moves 1–3 ticks in the aggressor's direction. An aggressor
        // leaning against the prevailing drift is often absorbed, and price
        // follows the drift instead.
        let moveProbability = min(0.85, 0.22 + abs(drift) * 0.30 + volatility * 0.12)
        if rng.next() < moveProbability {
            var move = rng.next() < 0.82 ? 1 : 2
            if volatility > 2, rng.next() < 0.25 { move += 1 }
            var direction = isBuy ? 1 : -1
            if Double(direction) * drift < 0, rng.next() < 0.5 { direction = -direction }
            shiftQuote(by: move * direction)
        }

        // Aggressive size: mostly small, occasionally a large sweep.
        var size = rng.range(1, 18)
        if rng.next() < 0.07 { size += rng.range(30, 140) }

        // Execute at the best opposite level; a depleted level lifts or drops the quote.
        if isBuy {
            let price = book.bestAsk
            let depleted = book.consumeBest(.offer, size: size)
            record(TapeTrade(id: tradeCounter, marketStep: marketStep, priceTicks: price, size: size, aggressor: .buy))
            if depleted { shiftQuote(by: 1) }
        } else {
            let price = book.bestBid
            let depleted = book.consumeBest(.bid, size: size)
            record(TapeTrade(id: tradeCounter, marketStep: marketStep, priceTicks: price, size: size, aggressor: .sell))
            if depleted { shiftQuote(by: -1) }
        }
        tradeCounter += 1
    }

    private mutating func shiftQuote(by ticks: Int) {
        book.shift(by: ticks, restingSize: profile.restingSize, rng: &rng)
    }

    private mutating func record(_ trade: TapeTrade) {
        tape.append(trade)
        if tape.count > Self.tapeLimit { tape.removeFirst(tape.count - Self.tapeLimit) }

        lastTicks = trade.priceTicks
        let signed = trade.aggressor == .buy ? trade.size : -trade.size
        cumulativeDelta += signed
        totalVolume += trade.size
        vwapNumerator += Double(trade.priceTicks) * Double(trade.size)
        vwapDenominator += trade.size

        let i = bars.count - 1
        bars[i].highTicks = max(bars[i].highTicks, trade.priceTicks)
        bars[i].lowTicks = min(bars[i].lowTicks, trade.priceTicks)
        bars[i].closeTicks = trade.priceTicks
        bars[i].volume += trade.size
        bars[i].delta += signed
    }

    private mutating func openBar() {
        bars.append(PriceBar(index: barCounter, openTicks: lastTicks))
        barCounter += 1
        if bars.count > Self.barLimit { bars.removeFirst(bars.count - Self.barLimit) }
        barUpdatesLeft = profile.updatesPerBar
    }

    // MARK: Spread

    /// Widening pressure grows with volatility above a calm regime; the extra
    /// spread decays back to the instrument's base when conditions normalise.
    private mutating func updateSpread() {
        let pressure = max(0, volatility - 1.5) * 0.12 * profile.spreadSensitivity
        if pressure > 0, rng.next() < pressure {
            extraSpreadTicks = min(profile.maxExtraSpreadTicks, extraSpreadTicks + 1)
        } else if extraSpreadTicks > 0, rng.next() < 0.3 {
            extraSpreadTicks -= 1
        }
        applySpread()
    }

    private mutating func widenSpread(by ticks: Int) {
        extraSpreadTicks = min(profile.maxExtraSpreadTicks, extraSpreadTicks + ticks)
        applySpread()
    }

    /// Re-centres the book when the target spread differs from the current one.
    /// Widening alternates between the bid and the offer side.
    private mutating func applySpread() {
        let target = profile.baseSpreadTicks + extraSpreadTicks
        let current = book.spreadTicks
        guard target != current else { return }
        // Either the bid moves (by −difference) or the offer does (bid stays).
        let difference = target - current
        let bidMove = rng.next() < 0.5 ? -difference : 0
        book.reprice(bestBid: book.bestBid + Int64(bidMove), spreadTicks: target,
                     restingSize: profile.restingSize, rng: &rng)
    }

    // MARK: Scenario

    private mutating func beginPhase(_ index: Int) {
        guard let scenario, index < scenario.phases.count else {
            scenarioComplete = scenario != nil
            return
        }
        phaseIndex = index
        let phase = scenario.phases[index]
        phaseUpdatesLeft = phase.ticks
        drift = phase.drift
        aggressorBias = phase.aggressorBias
        volatility = phase.vol
        replenishRate = phase.replenish
        pendingEvents = phase.events
    }

    private mutating func progressScenario() {
        guard let scenario, !scenarioComplete else { return }
        if !pendingEvents.isEmpty, marketStep % 2 == 0 {
            apply(pendingEvents.removeFirst())
        }
        phaseUpdatesLeft -= 1
        if phaseUpdatesLeft <= 0 {
            if phaseIndex + 1 < scenario.phases.count {
                beginPhase(phaseIndex + 1)
            } else {
                scenarioComplete = true
                // Drift dies out; the market keeps breathing afterwards.
                drift = 0
                aggressorBias = 0
                volatility = 1.2
                replenishRate = 0.35
            }
        }
    }

    private mutating func apply(_ event: ScenarioEvent) {
        switch event {
        case .absorptionWall(let side, let ticksFromMid, let size):
            book.setSize(size, side: side, levelsFromBest: ticksFromMid)
        case .sweep(let side, let levels):
            for _ in 0..<max(0, levels) {
                if side == .bid {
                    book.setSize(max(1, book.bids[0].size / 6), side: .bid, levelsFromBest: 0)
                    shiftQuote(by: -1)
                } else {
                    book.setSize(max(1, book.asks[0].size / 6), side: .offer, levelsFromBest: 0)
                    shiftQuote(by: 1)
                }
            }
        case .liquidityPull(let side):
            book.thin(side, divisor: 3)
            widenSpread(by: 1)
        case .volatilityBurst:
            volatility = max(volatility, 2.4)
            widenSpread(by: 1)
        case .calm:
            volatility = min(volatility, 1.0)
        }
    }
}
