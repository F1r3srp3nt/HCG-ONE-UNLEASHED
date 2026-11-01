import Foundation
import Testing
import HCGCharting
import HCGDomain
import HCGTrading
@testable import HCGMarketSim

@Suite("Charts on the simulated market")
struct ChartIntegrationTests {
    @Test("Every simulated trade lands in the charts, at its simulated time, in every timeframe")
    func chartsFollowTheTape() {
        var state = SimulationState(seed: 17)
        var printed = [MarketSymbol: Int]()
        for _ in 0..<900 {   // 15 simulated minutes
            state.advance()
            for symbol in MarketSymbol.allCases {
                printed[symbol, default: 0] += state.marketView(symbol).prints.reduce(0) { $0 + $1.size }
            }
        }
        for symbol in MarketSymbol.allCases {
            let history = state.chart(symbol)
            for timeframe in Timeframe.allCases {
                let candles = history[timeframe].candles
                #expect(candles.reduce(0) { $0 + $1.volume } == printed[symbol], "\(symbol) \(timeframe): volume")
                #expect(candles.last?.closeTicks == state.markets[symbol]?.lastTicks, "\(symbol) \(timeframe): close = last trade")
                #expect(zip(candles, candles.dropFirst()).allSatisfy { $0.start < $1.start })
                #expect(candles.allSatisfy { timeframe.bucketStart($0.start) == $0.start })
            }
            let m1 = history[.m1].candles
            #expect(m1.count == 15, "14:30–14:44 UTC")
            #expect(m1.first?.start == SimulatedClock.defaultStart)
            #expect(m1.allSatisfy { $0.buyVolume + $0.sellVolume == $0.volume })
        }
    }

    @Test("A prepared session opens at the session start with that much candle history")
    func preparedHistory() {
        let state = SimulationState.prepared(seed: 5, history: 7_200)   // 12:30–14:30 UTC
        #expect(state.time == SimulatedClock.defaultStart)
        #expect(state.account.fills.isEmpty && state.account.events.isEmpty, "the account takes no part")
        let history = state.chart(.nq)
        #expect(history[.m1].count == 120)
        #expect(history[.m1].candles.first?.start == SimulatedClock.defaultStart.addingTimeInterval(-7_200))
        #expect(history[.m5].count == 24)
        #expect(history[.h1].count == 3, "12:00, 13:00 and 14:00 candles")
        #expect(history[.h4].count == 2, "session-aligned 10:00–14:00 and 14:00–18:00 UTC candles")
        #expect(history[.d1].count == 1)

        // Same seed, same history: deterministic.
        #expect(SimulationState.prepared(seed: 5, history: 7_200) == state)
    }

    @Test("Charts round-trip through the session file; old files without charts still load")
    func persistence() throws {
        var state = SimulationState(seed: 2)
        for _ in 0..<130 { state.advance() }
        let data = try SessionPersistence.encoder.encode(state)
        #expect(try SessionPersistence.decoder.decode(SimulationState.self, from: data) == state)

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "chartStore")
        let old = try JSONSerialization.data(withJSONObject: json)
        var restored = try SessionPersistence.decoder.decode(SimulationState.self, from: old)
        #expect(restored.chart(.es)[.m1].count == 0, "an old session starts with empty charts")
        restored.advance()
        #expect(restored.chart(.es)[.m1].count == 1, "and builds them from then on")
    }

    @Test("Loading a scenario restarts that market's chart only")
    func scenarioRestartsChart() {
        var state = SimulationState(seed: 3)
        for _ in 0..<120 { state.advance() }
        let scenario = MarketScenario.catalog[0]
        state.load(scenario)
        #expect(state.chart(scenario.symbol)[.m1].count == 0)
        let other = MarketSymbol.allCases.first { $0 != scenario.symbol }!
        #expect(state.chart(other)[.m1].count == 2)
    }

    @Test("The host builds history before playback, and a reset rebuilds it")
    @MainActor
    func hostHistory() async {
        let host = SimulationHost(seed: 4, ticker: ImmediateTicker())
        host.play()                                   // requested before history exists
        #expect(host.isPlaying, "no history requested yet: plays immediately")
        await host.pauseAndWait()

        let fresh = SimulationHost(seed: 4, ticker: ImmediateTicker())
        await fresh.prepareHistory(updates: 600)
        #expect(fresh.frame.time == SimulatedClock.defaultStart)
        #expect(fresh.frame.charts[.es]?[.m1].count == 10)
        #expect(!fresh.isPreparingHistory)

        await fresh.step()
        await fresh.reset(seed: 9)
        #expect(fresh.frame.time == SimulatedClock.defaultStart, "a reset session starts with history again")
        #expect(fresh.frame.charts[.es]?[.m1].count == 10)
        #expect(fresh.frame.account.fills.isEmpty)

        await fresh.step()
        await fresh.prepareHistory(updates: 600)
        #expect(fresh.frame.time > SimulatedClock.defaultStart, "a running session keeps its own history")
    }
}
