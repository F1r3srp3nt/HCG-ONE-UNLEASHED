import Foundation
import Testing
import HCGDomain
@testable import HCGMarketSim

@Suite("Simulated broker")
struct SimulatedBrokerTests {
    private func snapshot(_ symbol: MarketSymbol = .gc, steps: Int = 50, seed: UInt64 = 9) -> MarketSnapshot {
        var market = MarketSimulator(symbol: symbol, seed: seed)
        for _ in 0..<steps { market.advance() }
        return market.snapshot(frameSequence: steps)
    }

    @Test("A market buy fills at the ask and opens a long")
    func marketBuyFillsAtAsk() throws {
        let s = snapshot()
        var account = SimulatedAccount()
        let quantity = min(3, s.asks[0].size)
        let fill = try account.execute(MarketOrder(symbol: .gc, side: .buy, quantity: quantity),
                                       against: s, commissionPerContract: 2.5)
        #expect(abs(fill.averagePrice - s.ask) < 1e-9)
        #expect(account.position(.gc)?.quantity == quantity)
        #expect(abs(account.commissionsPaid - 2.5 * Double(quantity)) < 1e-9)
        #expect(abs(account.cash - (50_000 - 2.5 * Double(quantity))) < 1e-9)
    }

    @Test("Large orders walk the book to a volume-weighted price")
    func walksTheBook() throws {
        // Find (deterministically) a book whose best ask is smaller than the
        // order cap, so the order must consume a second level.
        let candidate = (UInt64(1)...200).lazy
            .map { self.snapshot(seed: $0) }
            .first { $0.asks[0].size < MarketOrder.maximumQuantity }
        let s = try #require(candidate)
        let first = s.asks[0]
        let second = s.asks[1]
        let quantity = first.size + 1
        var account = SimulatedAccount()
        let fill = try account.execute(MarketOrder(symbol: .gc, side: .buy, quantity: quantity),
                                       against: s, commissionPerContract: 0)
        let expectedTicks = (Double(first.priceTicks) * Double(first.size) + Double(second.priceTicks)) / Double(quantity)
        #expect(abs(fill.averagePrice - expectedTicks * s.spec.tickSize) < 1e-9)
        #expect(fill.averagePrice > s.ask)
    }

    @Test("Round trip realises (exit − entry) × quantity × point value")
    func roundTripPnL() throws {
        var market = MarketSimulator(symbol: .es, seed: 4)
        for _ in 0..<30 { market.advance() }
        var account = SimulatedAccount()
        let entry = market.snapshot(frameSequence: 0)
        let buy = try account.execute(MarketOrder(symbol: .es, side: .buy, quantity: 2), against: entry, commissionPerContract: 2)
        for _ in 0..<60 { market.advance() }
        let exit = market.snapshot(frameSequence: 0)
        let sell = try account.flatten(against: exit, commissionPerContract: 2)
        let expected = (sell.averagePrice - buy.averagePrice) * 2 * MarketSymbol.es.spec.pointValue
        #expect(abs(sell.realizedPnL - expected) < 1e-6)
        #expect(account.position(.es) == nil)
        #expect(abs(account.cash - (50_000 + expected - 8)) < 1e-6)
    }

    @Test("Selling more than the long reverses into a short at the fill price")
    func reversal() throws {
        let s = snapshot(.cl)
        var account = SimulatedAccount()
        try account.execute(MarketOrder(symbol: .cl, side: .buy, quantity: 1), against: s, commissionPerContract: 0)
        let fill = try account.execute(MarketOrder(symbol: .cl, side: .sell, quantity: 3), against: s, commissionPerContract: 0)
        #expect(account.position(.cl)?.quantity == -2)
        #expect(abs((account.position(.cl)?.averagePrice ?? 0) - fill.averagePrice) < 1e-9)
    }

    @Test("Invalid orders are rejected without changing the account")
    func rejections() {
        let s = snapshot()
        var account = SimulatedAccount()
        #expect(throws: OrderRejection.invalidQuantity) {
            try account.execute(MarketOrder(symbol: .gc, side: .buy, quantity: 0), against: s, commissionPerContract: 1)
        }
        #expect(throws: OrderRejection.invalidQuantity) {
            try account.execute(MarketOrder(symbol: .gc, side: .buy, quantity: MarketOrder.maximumQuantity + 1),
                                against: s, commissionPerContract: 1)
        }
        #expect(throws: OrderRejection.noOpenPosition) {
            try account.flatten(against: s, commissionPerContract: 1)
        }
        #expect(account == SimulatedAccount())
    }

    @Test("Unrealised P&L marks longs at the bid and shorts at the ask")
    func unrealisedMarks() throws {
        let s = snapshot(.nq)
        var long = SimulatedAccount()
        try long.execute(MarketOrder(symbol: .nq, side: .buy, quantity: 1), against: s, commissionPerContract: 0)
        // Bought at the ask, marked at the bid: down exactly one spread.
        #expect(abs(long.unrealizedPnL(s) + s.spread * s.spec.pointValue) < 1e-9)
        var short = SimulatedAccount()
        try short.execute(MarketOrder(symbol: .nq, side: .sell, quantity: 1), against: s, commissionPerContract: 0)
        #expect(abs(short.unrealizedPnL(s) + s.spread * s.spec.pointValue) < 1e-9)
    }
}

/// A ticker that never sleeps, so the real playback loop runs as fast as the
/// main actor allows.
struct ImmediateTicker: SimulationTicker {
    func wait(for duration: Duration) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

@MainActor
@Suite("Simulation host — playback")
struct SimulationHostTests {
    /// Waits (bounded) until `condition` holds, yielding to the playback loop.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<20_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    @Test("Pause stops the clock and resume continues it")
    func pauseAndResume() async {
        let host = SimulationHost(seed: 12, ticker: ImmediateTicker())
        #expect(!host.isPlaying)
        host.play()
        #expect(host.isPlaying)
        #expect(await waitUntil { host.frame.sequence >= 25 })

        await host.pauseAndWait()
        #expect(!host.isPlaying)
        let paused = host.frame.sequence
        for _ in 0..<500 { await Task.yield() }
        #expect(host.frame.sequence == paused, "no updates while paused")

        host.play()
        #expect(await waitUntil { host.frame.sequence >= paused + 25 })
        await host.pauseAndWait()
        let resumed = host.frame.sequence
        #expect(resumed >= paused + 25)
    }

    @Test("Playback with pauses reproduces an uninterrupted run exactly")
    func pausedRunMatchesContinuousRun() async {
        let host = SimulationHost(seed: 3, ticker: ImmediateTicker())
        for _ in 0..<3 {
            host.play()
            _ = await waitUntil { host.frame.sequence >= 40 }
            await host.pauseAndWait()
        }
        var reference = SimulationState(seed: 3)
        for _ in 0..<host.frame.sequence { reference.advance() }
        #expect(host.frame == reference.frame())
    }

    @Test("Manual steps advance exactly one update while paused")
    func manualStep() async {
        let host = SimulationHost(seed: 1, ticker: ImmediateTicker())
        await host.step()
        await host.step()
        #expect(host.frame.sequence == 2)
        var reference = SimulationState(seed: 1)
        reference.advance()
        reference.advance()
        #expect(host.frame == reference.frame())
    }

    @Test("Speed control is bounded")
    func speedBounds() {
        let host = SimulationHost(ticker: ImmediateTicker())
        #expect(host.speed == .normal)
        for _ in 0..<10 { host.faster() }
        #expect(host.speed == .octuple)
        for _ in 0..<10 { host.slower() }
        #expect(host.speed == .quarter)
        #expect(SimulationSpeed.normal.interval == .milliseconds(500))
        #expect(SimulationSpeed.octuple.interval == .milliseconds(63))
    }

    @Test("Orders and resets publish through the same frame")
    func ordersPublishFrames() async {
        let host = SimulationHost(seed: 6, ticker: ImmediateTicker())
        await host.submit(MarketOrder(symbol: .gc, side: .buy, quantity: 1))
        #expect(host.frame.account.position(.gc)?.quantity == 1)
        #expect(host.lastOrderMessage?.hasPrefix("Simulated buy 1 GC") == true)
        await host.flatten(.gc)
        #expect(host.frame.account.position(.gc) == nil)
        await host.submit(MarketOrder(symbol: .gc, side: .buy, quantity: 0))
        #expect(host.lastOrderMessage == OrderRejection.invalidQuantity.description)

        let revisionBefore = host.frame.revision
        await host.reset(seed: 6)
        #expect(host.frame.sequence == 0)
        #expect(host.frame.revision > revisionBefore)
        #expect(host.frame.account.fills.isEmpty)
    }
}
