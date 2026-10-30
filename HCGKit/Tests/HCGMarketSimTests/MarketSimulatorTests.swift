import Foundation
import Testing
import HCGDomain
@testable import HCGMarketSim

extension MarketScenario: CustomTestStringConvertible {
    public var testDescription: String { id }
}

/// Asserts every book and quote invariant on one snapshot.
func expectValid(_ snapshot: MarketSnapshot, profile: SimulationProfile,
                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(snapshot.bidTicks < snapshot.askTicks, "bid must be below ask", sourceLocation: sourceLocation)
    #expect(snapshot.bids.count == profile.bookDepth, sourceLocation: sourceLocation)
    #expect(snapshot.asks.count == profile.bookDepth, sourceLocation: sourceLocation)
    #expect(snapshot.bids.first?.priceTicks == snapshot.bidTicks, sourceLocation: sourceLocation)
    #expect(snapshot.asks.first?.priceTicks == snapshot.askTicks, sourceLocation: sourceLocation)
    #expect(snapshot.spreadTicks >= profile.baseSpreadTicks, sourceLocation: sourceLocation)
    #expect(snapshot.spreadTicks <= profile.maxSpreadTicks, sourceLocation: sourceLocation)
    #expect(zip(snapshot.bids, snapshot.bids.dropFirst()).allSatisfy { $0.priceTicks - 1 == $1.priceTicks },
            "bids strictly descending, one tick apart", sourceLocation: sourceLocation)
    #expect(zip(snapshot.asks, snapshot.asks.dropFirst()).allSatisfy { $0.priceTicks + 1 == $1.priceTicks },
            "asks strictly ascending, one tick apart", sourceLocation: sourceLocation)
    #expect(snapshot.bids.allSatisfy { $0.size >= 1 }, sourceLocation: sourceLocation)
    #expect(snapshot.asks.allSatisfy { $0.size >= 1 }, sourceLocation: sourceLocation)
    #expect(snapshot.bid > 0 && snapshot.bid.isFinite && snapshot.ask.isFinite, sourceLocation: sourceLocation)
}

@Suite("Market simulator — order book")
struct OrderBookTests {
    @Test("Bid stays below ask on every update", arguments: MarketSymbol.allCases)
    func bidBelowAsk(_ symbol: MarketSymbol) {
        var market = MarketSimulator(symbol: symbol, seed: 11)
        for _ in 0..<2_000 {
            market.advance()
            let s = market.snapshot(frameSequence: market.marketStep)
            #expect(s.bidTicks < s.askTicks)
        }
    }

    @Test("Spread equals ask − bid in ticks and in price", arguments: MarketSymbol.allCases)
    func spreadCalculation(_ symbol: MarketSymbol) {
        var market = MarketSimulator(symbol: symbol, seed: 5)
        for _ in 0..<500 { market.advance() }
        let s = market.snapshot(frameSequence: 0)
        #expect(s.spreadTicks == Int(s.askTicks - s.bidTicks))
        #expect(abs(s.spread - (s.ask - s.bid)) < s.spec.tickSize * 1e-6)
        #expect(abs(s.spread - Double(s.spreadTicks) * s.spec.tickSize) < 1e-9)
    }

    @Test("Book levels are ordered best-first and contiguous", arguments: MarketSymbol.allCases)
    func priceOrdering(_ symbol: MarketSymbol) {
        var market = MarketSimulator(symbol: symbol, seed: 99)
        for _ in 0..<1_000 {
            market.advance()
            #expect(market.bookViolations().isEmpty, "\(market.bookViolations())")
        }
    }

    @Test("Both book sides stay non-empty with valid sizes", arguments: MarketSymbol.allCases)
    func nonEmptySides(_ symbol: MarketSymbol) {
        var market = MarketSimulator(symbol: symbol, seed: 3)
        for _ in 0..<1_000 {
            market.advance()
            let s = market.snapshot(frameSequence: 0)
            expectValid(s, profile: market.profile)
        }
    }

    /// Regression for the HCG ONE defect: the iOS book shift widened the GC
    /// spread on every price move (0.10 → 3.50 after 20 moves → 54.70 after 400).
    /// In a calm free market the simulated GC spread must stay at exactly one
    /// 0.10 tick — not merely "small".
    @Test("GC spread stays at one 0.10 tick in a calm market (iOS regression)")
    func gcSpreadRegression() {
        var market = MarketSimulator(symbol: .gc, seed: SimulationState.defaultSeed)
        let startTicks = market.snapshot(frameSequence: 0).lastTicks
        var moved = false
        for _ in 0..<10_000 {
            market.advance()
            let s = market.snapshot(frameSequence: 0)
            #expect(s.spreadTicks == 1)
            #expect(abs(s.spread - 0.10) < 1e-9)
            if s.lastTicks != startTicks { moved = true }
        }
        #expect(moved, "price must actually move for the regression to be meaningful")
    }

    @Test("Stress widens the spread within limits and it decays back to base")
    func spreadWidensAndRecovers() {
        guard let news = MarketScenario.find("news-volatility") else {
            Issue.record("news-volatility scenario missing")
            return
        }
        var market = MarketSimulator(symbol: news.symbol, seed: 1)
        market.load(news)
        var widest = 0
        for _ in 0..<news.totalTicks {
            market.advance()
            let s = market.snapshot(frameSequence: 0)
            widest = max(widest, s.spreadTicks)
            expectValid(s, profile: market.profile)
        }
        #expect(widest > market.profile.baseSpreadTicks, "a news scenario should widen the spread")
        #expect(widest <= market.profile.maxSpreadTicks)
        // After the scenario the market calms (volatility 1.2) and the spread decays.
        for _ in 0..<300 { market.advance() }
        #expect(market.snapshot(frameSequence: 0).spreadTicks == market.profile.baseSpreadTicks)
    }

    @Test("Strong negative drift moves price down (aggressor direction fix)")
    func driftDirection() {
        let down = MarketScenario(
            id: "test-down", title: "Down", symbol: .es, level: .beginner, summary: "", observe: [],
            phases: [ScenarioPhase(ticks: 200, drift: -0.5, aggressorBias: -0.7, vol: 1.2)],
            debrief: [], concept: "")
        let up = MarketScenario(
            id: "test-up", title: "Up", symbol: .es, level: .beginner, summary: "", observe: [],
            phases: [ScenarioPhase(ticks: 200, drift: 0.5, aggressorBias: 0.7, vol: 1.2)],
            debrief: [], concept: "")
        for seed: UInt64 in [1, 2, 3] {
            var falling = MarketSimulator(symbol: .es, seed: seed)
            falling.load(down, seed: seed)
            var rising = MarketSimulator(symbol: .es, seed: seed)
            rising.load(up, seed: seed)
            let start = falling.snapshot(frameSequence: 0).lastTicks
            for _ in 0..<200 {
                falling.advance()
                rising.advance()
            }
            #expect(falling.snapshot(frameSequence: 0).lastTicks < start - 20)
            #expect(rising.snapshot(frameSequence: 0).lastTicks > start + 20)
        }
    }

    @Test("Tape, bars, VWAP and delta are projections of the same trades")
    func projectionsAgree() {
        var market = MarketSimulator(symbol: .nq, seed: 21)
        for _ in 0..<300 { market.advance() }
        let s = market.snapshot(frameSequence: 0)
        #expect(s.recentTrades.last?.priceTicks == s.lastTicks)
        #expect(s.bars.last?.closeTicks == s.lastTicks || s.bars.last?.volume == 0)
        #expect(s.totalVolume > 0)
        #expect(s.vwap != nil)
        #expect(s.bars.allSatisfy { $0.lowTicks <= $0.highTicks })
    }
}

@Suite("Market simulator — determinism and scenarios")
struct DeterminismTests {
    @Test("Same seed produces the identical market", arguments: MarketSymbol.allCases)
    func fixedSeedDeterminism(_ symbol: MarketSymbol) {
        var a = MarketSimulator(symbol: symbol, seed: 42)
        var b = MarketSimulator(symbol: symbol, seed: 42)
        for _ in 0..<1_500 {
            a.advance()
            b.advance()
        }
        #expect(a == b)
        #expect(a.snapshot(frameSequence: 7) == b.snapshot(frameSequence: 7))
    }

    @Test("Different seeds produce different markets")
    func differentSeedsDiverge() {
        var a = MarketSimulator(symbol: .gc, seed: 1)
        var b = MarketSimulator(symbol: .gc, seed: 2)
        for _ in 0..<200 {
            a.advance()
            b.advance()
        }
        #expect(a.snapshot(frameSequence: 0) != b.snapshot(frameSequence: 0))
    }

    @Test("Every scenario replays identically", arguments: MarketScenario.catalog)
    func scenarioReplay(_ scenario: MarketScenario) {
        func run() -> [MarketSnapshot] {
            var market = MarketSimulator(symbol: scenario.symbol, seed: 0)
            market.load(scenario)
            var frames: [MarketSnapshot] = []
            for _ in 0..<(scenario.totalTicks + 20) {
                market.advance()
                frames.append(market.snapshot(frameSequence: 0))
            }
            return frames
        }
        let first = run()
        let second = run()
        #expect(first == second)
        #expect(first.last?.scenarioComplete == true)
        #expect(first.last?.scenarioID == scenario.id)
        for frame in first {
            expectValid(frame, profile: .standard(for: scenario.symbol))
        }
    }

    @Test("Scenario catalog is well-formed")
    func catalogIsWellFormed() {
        let catalog = MarketScenario.catalog
        #expect(catalog.count == 10)
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        for scenario in catalog {
            #expect(!scenario.phases.isEmpty)
            #expect(scenario.phases.allSatisfy { $0.ticks > 0 })
            #expect(!scenario.observe.isEmpty && !scenario.debrief.isEmpty)
        }
    }

    @Test("Reset restores the opening state of the seed")
    func resetRestoresSession() {
        var market = MarketSimulator(symbol: .cl, seed: 8)
        let opening = market
        for _ in 0..<100 { market.advance() }
        market.reset(seed: 8)
        #expect(market == opening)
    }
}

@Suite("Simulation state — one clock")
struct SimulationStateTests {
    @Test("All markets in a frame share the same clock value")
    func marketsShareTheClock() {
        var state = SimulationState(seed: 77)
        for _ in 0..<250 { state.advance() }
        let frame = state.frame()
        #expect(frame.sequence == 250)
        for symbol in MarketSymbol.allCases {
            #expect(frame[symbol].frameSequence == frame.sequence)
            #expect(frame[symbol].marketStep == 250)
        }
    }

    @Test("Chart and DOM models derived from one frame agree")
    func panelsDoNotDiverge() {
        var state = SimulationState(seed: 31)
        for step in 0..<400 {
            state.advance()
            guard step % 20 == 0 else { continue }
            let frame = state.frame()
            for symbol in MarketSymbol.allCases {
                let snapshot = frame[symbol]
                let ladder = DepthLadder(snapshot: snapshot)
                let series = PriceSeries(snapshot: snapshot)
                #expect(ladder.frameSequence == series.frameSequence)
                #expect(ladder.frameSequence == frame.sequence)
                #expect(snapshot.spec.price(ticks: ladder.bestBidTicks) == series.bid)
                #expect(snapshot.spec.price(ticks: ladder.bestAskTicks) == series.ask)
                #expect(snapshot.spec.price(ticks: ladder.lastTicks) == series.last)
                #expect(ladder.spreadTicks == snapshot.spreadTicks)
                #expect(series.candles.last?.close == snapshot.last || series.candles.last?.volume == 0)
                #expect(series.priceRange.contains(series.bid) && series.priceRange.contains(series.ask))
                #expect(ladder.rows.filter(\.isBestBid).count == 1)
                #expect(ladder.rows.filter(\.isBestAsk).count == 1)
                #expect(ladder.rows.filter(\.isInsideSpread).count == ladder.spreadTicks - 1)
            }
        }
    }

    @Test("Loading a scenario affects only its market and keeps the shared clock")
    func scenarioLoadIsolated() {
        var a = SimulationState(seed: 5)
        var b = SimulationState(seed: 5)
        for _ in 0..<50 {
            a.advance()
            b.advance()
        }
        guard let scenario = MarketScenario.find("sweep-reversal") else {
            Issue.record("sweep-reversal scenario missing")
            return
        }
        a.load(scenario)
        for _ in 0..<40 {
            a.advance()
            b.advance()
        }
        let fa = a.frame()
        let fb = b.frame()
        #expect(fa.sequence == fb.sequence)
        #expect(fa[.gc] != fb[.gc])
        #expect(fa[.gc].scenarioID == "sweep-reversal")
        #expect(fa[.nq] == fb[.nq])
        #expect(fa[.es] == fb[.es])
        #expect(fa[.cl] == fb[.cl])
    }

    /// Soak test: 10,000 clock updates across all four markets while cycling
    /// through every scenario. Every invariant is checked on every update.
    @Test("10,000-update soak keeps every market valid")
    func soak() {
        var state = SimulationState(seed: 2026)
        let catalog = MarketScenario.catalog
        var violations = 0
        for step in 0..<10_000 {
            if step % 250 == 0 { state.load(catalog[(step / 250) % catalog.count]) }
            state.advance()
            for symbol in MarketSymbol.allCases {
                guard let market = state.markets[symbol] else { continue }
                let problems = market.bookViolations()
                if !problems.isEmpty {
                    violations += 1
                    if violations <= 5 { Issue.record("step \(step) \(symbol): \(problems)") }
                }
                let s = market.snapshot(frameSequence: state.sequence)
                if !(s.bidTicks < s.askTicks && s.bid > 0 && s.last.isFinite) { violations += 1 }
            }
        }
        #expect(violations == 0)
        #expect(state.sequence == 10_000)
    }

    /// Prolonged execution: 50,000 updates of all four markets. Checks the
    /// invariants on every update, that every buffer stays bounded (no
    /// unbounded memory growth), and that prices stay positive and finite.
    /// Also reports the measured cost per update.
    @Test("50,000-update run keeps markets valid with bounded memory")
    func prolongedRunIsStable() {
        var state = SimulationState(seed: 4242)
        let clock = ContinuousClock()
        var problems = 0
        let start = clock.now
        for _ in 0..<50_000 {
            state.advance()
            for market in state.markets.values where !market.bookViolations().isEmpty { problems += 1 }
        }
        let elapsed = clock.now - start
        #expect(problems == 0)
        for (symbol, market) in state.markets {
            #expect(market.tape.count <= MarketSimulator.tapeLimit, "\(symbol) tape bounded")
            #expect(market.bars.count <= MarketSimulator.barLimit, "\(symbol) bars bounded")
            let s = market.snapshot(frameSequence: state.sequence)
            #expect(s.recentTrades.count <= MarketSimulator.snapshotTrades)
            #expect(s.last > 0 && s.last.isFinite && s.bid > 0 && s.ask.isFinite)
        }
        print("[measure] 50,000 updates × 4 markets (with invariant checks): \(elapsed), \(elapsed / 50_000) per update")
    }

    @Test("Account history stays bounded under sustained order entry")
    func fillHistoryBounded() throws {
        var state = SimulationState(seed: 9)
        for i in 0..<1_000 {
            state.advance()
            try state.submit(MarketOrder(symbol: .es, side: i.isMultiple(of: 2) ? .buy : .sell, quantity: 1))
        }
        #expect(state.account.fills.count == SimulatedAccount.fillHistoryLimit)
        #expect(state.account.position(.es) == nil, "alternating buys and sells end flat")
    }
}
