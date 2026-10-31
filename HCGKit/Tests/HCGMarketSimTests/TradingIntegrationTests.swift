import Foundation
import Testing
import HCGDomain
import HCGTrading
@testable import HCGMarketSim

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hcg-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Trading on the simulated market")
struct TradingIntegrationTests {
    @Test("A resting limit order fills at its limit price when the simulated market reaches it")
    func limitFillsOnSimulatedMarket() throws {
        var state = SimulationState(seed: 21)
        for _ in 0..<20 { state.advance() }
        let spec = MarketSymbol.gc.spec
        let ask = state.snapshot(.gc).askTicks
        // The market is deterministic and unaffected by orders, so a copy run
        // forward shows a future offer below today's ask to rest the bid at.
        var future = state
        var low = ask
        for _ in 0..<20_000 where low >= ask {
            future.advance()
            low = min(low, future.snapshot(.gc).askTicks)
        }
        try #require(low < ask, "the simulated GC market must trade below the current ask within 20,000 updates")

        let result = state.submit(.limit(.buy, 1, .gc, at: spec.price(ticks: low), id: "lim"))
        #expect(result.order.status == .working)
        var steps = 0
        while state.account.position(.gc) == nil && steps < 20_000 {
            state.advance()
            steps += 1
        }
        let fill = state.account.fills.last
        #expect(fill?.price == spec.price(ticks: low), "filled at the limit after \(steps) updates")
        #expect(fill?.liquidity == .maker)
        #expect(state.account.position(.gc)?.quantity == 1)
    }

    @Test("The engine sees exactly the trades the simulated market printed in the latest update")
    func printsMatchTheTape() {
        var state = SimulationState(seed: 8)
        for _ in 0..<50 { state.advance() }
        for symbol in MarketSymbol.allCases {
            let market = state.markets[symbol]!
            let expected = market.tape.filter { $0.marketStep == market.marketStep - 1 }
            let prints = state.marketView(symbol).prints
            #expect(!prints.isEmpty, "every update prints 2–6 trades")
            #expect(prints.map(\.size) == expected.map(\.size))
            #expect(prints.map(\.priceTicks) == expected.map(\.priceTicks))
        }
    }

    @Test("A frame's market view matches the engine's view of the book")
    func frameMarketView() {
        var state = SimulationState(seed: 12)
        for _ in 0..<25 { state.advance() }
        let frame = state.frame()
        for symbol in MarketSymbol.allCases {
            let a = frame.marketView(symbol)
            let b = state.marketView(symbol)
            #expect(a.bidTicks == b.bidTicks && a.askTicks == b.askTicks && a.sequence == b.sequence)
            #expect(a.bids == b.bids && a.asks == b.asks)
        }
    }

    @Test("Joining the bid on the simulated market fills only after the queue ahead has traded")
    func queueOnTheSimulatedMarket() throws {
        var configuration = AccountConfiguration.standard
        configuration.risk = RiskLimits()
        var state = SimulationState(seed: 31, account: TradingAccount(configuration: configuration))
        for _ in 0..<30 { state.advance() }
        let bid = state.snapshot(.es).bidTicks
        let result = state.submit(.limit(.buy, 1, .es, at: MarketSymbol.es.spec.price(ticks: bid), id: "join"))
        let queue = try #require(result.order.queueAhead)
        #expect(queue > 0, "the simulated book shows size at the best bid")

        var steps = 0
        while state.account.position(.es) == nil && steps < 5_000 {
            let aheadBefore = state.account.openOrders.first?.queueAhead
            state.advance()
            steps += 1
            guard state.account.position(.es) != nil else { continue }
            // The update that filled us: the market reached through our price,
            // or more was sold at our price than was queued ahead of us.
            let view = state.marketView(.es)
            let soldAtBid = view.prints.filter { $0.priceTicks == bid && $0.aggressor == .sell }.reduce(0) { $0 + $1.size }
            let reached = view.prints.contains { $0.priceTicks < bid || ($0.priceTicks == bid && $0.aggressor == .buy) }
                || view.askTicks <= bid
            #expect(reached || (aheadBefore.map { soldAtBid > $0 } ?? false),
                    "filled after \(steps) updates: \(soldAtBid) sold at the bid vs \(String(describing: aheadBefore)) ahead")
        }
        #expect(state.account.position(.es)?.quantity == 1)
    }

    @Test("Simulated orders never change the simulated market (D-33)")
    func ordersDoNotMoveTheMarket() {
        var quiet = SimulationState(seed: 21)
        var trading = SimulationState(seed: 21)
        for i in 0..<2_000 {
            quiet.advance()
            trading.advance()
            if i % 50 == 0 {
                trading.submit(.market(i.isMultiple(of: 100) ? .buy : .sell, 3, .gc, id: "o\(i)"))
                trading.submit(.limit(.buy, 1, .es, at: MarketSymbol.es.spec.price(ticks: trading.snapshot(.es).bidTicks - 2), id: "l\(i)"))
            }
        }
        for symbol in MarketSymbol.allCases {
            #expect(quiet.markets[symbol] == trading.markets[symbol], "\(symbol) market path must be identical")
        }
        #expect(!trading.account.fills.isEmpty)
    }

    @Test("Simulated time advances deterministically with the clock")
    func simulatedTime() {
        var state = SimulationState(seed: 1)
        #expect(state.time == SimulatedClock.defaultStart)
        for _ in 0..<90 { state.advance() }
        #expect(state.time == SimulatedClock.defaultStart.addingTimeInterval(90))
        #expect(state.frame().time == state.time)
        state.submit(.market(.buy, 1, .es, id: "t"))
        #expect(state.account.fills.last?.time == state.time)
        #expect(state.account.fills.last?.sequence == 90)
    }

    @Test("The whole session (markets, scenario, orders, positions) round-trips through JSON")
    func sessionRoundTrip() throws {
        var state = SimulationState(seed: 77)
        state.load(MarketScenario.catalog[0])
        for i in 0..<300 {
            state.advance()
            if i == 50 { state.submit(.market(.buy, 2, .gc, id: "a", bracket: BracketSpec(takeProfitTicks: 30, stopLossTicks: 30))) }
            if i == 80 { state.submit(.stop(.sell, 1, .nq, at: MarketSymbol.nq.spec.price(ticks: state.snapshot(.nq).bidTicks - 40), id: "b")) }
        }
        let data = try SessionPersistence.encoder.encode(state)
        let decoded = try SessionPersistence.decoder.decode(SimulationState.self, from: data)
        #expect(decoded == state)
        // A restored session continues exactly like the original.
        var original = state
        var restored = decoded
        for _ in 0..<200 {
            original.advance()
            restored.advance()
        }
        #expect(original == restored)
    }

    @Test("Saving and loading a session file restores the account exactly")
    func persistenceRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionPersistence(directory: directory)
        if case .fresh = persistence.load() {} else { Issue.record("an empty directory must load fresh") }

        var state = SimulationState(seed: 5)
        for _ in 0..<40 { state.advance() }
        state.submit(.market(.sell, 1, .cl, id: "x"))
        try persistence.save(state, savedAt: Date())

        guard case .restored(let loaded, _) = persistence.load() else {
            Issue.record("expected a restored session")
            return
        }
        #expect(loaded == state)
        #expect(loaded.account.position(.cl)?.quantity == -1)
    }

    @Test("An unreadable session file is kept aside and a fresh session starts")
    func corruptFileRecovery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionPersistence(directory: directory)
        try Data("{ not json".utf8).write(to: persistence.fileURL)
        guard case .recovered(let backup, let reason) = persistence.load() else {
            Issue.record("expected recovery")
            return
        }
        #expect(!reason.isEmpty)
        #expect(backup.map { FileManager.default.fileExists(atPath: $0.path) } == true, "the bad file is kept, not deleted")
        #expect(!FileManager.default.fileExists(atPath: persistence.fileURL.path))
    }

    @Test("A session written by a newer app version is not loaded")
    func newerSchemaIsRejected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionPersistence(directory: directory)
        try persistence.save(SimulationState(seed: 1), savedAt: Date())
        var json = try String(contentsOf: persistence.fileURL, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        try json.write(to: persistence.fileURL, atomically: true, encoding: .utf8)
        guard case .recovered = persistence.load() else {
            Issue.record("a newer schema must not be loaded")
            return
        }
    }

    @Test("The host autosaves after an order and a new host restores it")
    @MainActor
    func hostAutosaveAndRestore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionPersistence(directory: directory)

        let host = SimulationHost(seed: 3, ticker: ImmediateTicker(), persistence: persistence,
                                  autosaveInterval: .milliseconds(20), marketSaveInterval: .seconds(3_600))
        await host.step()
        await host.submit(.market(.buy, 2, .es, id: "persist"))
        var saved = false
        for _ in 0..<500 {
            if case .restored(let s, _) = persistence.load(), s.account.position(.es)?.quantity == 2 { saved = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(saved, "the account change was saved without an explicit save call")

        await host.submit(.limit(.buy, 1, .es, at: MarketSymbol.es.spec.price(ticks: host.frame[.es].bidTicks - 20), id: "rest"))
        await host.saveNow()
        let expected = host.frame.account

        let relaunched = SimulationHost(seed: 3, ticker: ImmediateTicker(), persistence: persistence)
        #expect(relaunched.frame.account == expected)
        #expect(relaunched.frame.account.openOrders.count == 1)
        #expect(relaunched.restoreNotice?.hasPrefix("Restored") == true)
    }

    /// Prolonged trading: 20,000 updates with a deterministic mix of market,
    /// limit, stop and bracket orders across all markets. Checks the account
    /// invariants throughout.
    @Test("20,000-update trading soak keeps the account consistent")
    func tradingSoak() {
        var configuration = AccountConfiguration.standard
        configuration.startingBalance = 5_000_000
        configuration.risk = RiskLimits() // 100 / 50 contracts, no lock rules: the soak checks consistency, not risk
        var state = SimulationState(seed: 404, account: TradingAccount(configuration: configuration))
        var rng = SeededRNG(seed: 99)
        for i in 0..<20_000 {
            state.advance()
            guard i % 7 == 0 else { continue }
            let symbol = MarketSymbol.allCases[rng.int(4)]
            let s = state.snapshot(symbol)
            let side: OrderSide = rng.next() < 0.5 ? .buy : .sell
            let qty = rng.range(1, 3)
            let spec = symbol.spec
            switch rng.int(5) {
            case 0: state.submit(.market(side, qty, symbol, id: "m\(i)"))
            case 1:
                let ticks = side == .buy ? s.bidTicks - Int64(rng.range(0, 6)) : s.askTicks + Int64(rng.range(0, 6))
                state.submit(.limit(side, qty, symbol, at: spec.price(ticks: ticks), id: "l\(i)",
                                    bracket: BracketSpec(takeProfitTicks: rng.range(4, 20), stopLossTicks: rng.range(4, 20))))
            case 2:
                let ticks = side == .buy ? s.askTicks + Int64(rng.range(1, 8)) : s.bidTicks - Int64(rng.range(1, 8))
                state.submit(.stop(side, qty, symbol, at: spec.price(ticks: ticks), id: "s\(i)"))
            case 3: if let o = state.account.openOrders.first { state.cancel(orderID: o.id) }
            default: if rng.next() < 0.3 { state.closePosition(symbol) }
            }
        }
        let a = state.account
        #expect(abs(a.cash - (a.startingBalance + a.realizedPnL - a.commissionsPaid - a.feesPaid)) < 1e-6)
        #expect(a.fills.count > 500, "the soak actually traded (\(a.fills.count) fills)")
        #expect(a.fills.count <= TradingAccount.fillLimit && a.orderHistory.count <= TradingAccount.orderHistoryLimit)
        #expect(a.openOrders.allSatisfy { $0.isOpen && $0.filledQuantity <= $0.quantity })
        #expect((a.openOrders + a.orderHistory).allSatisfy { $0.filledQuantity <= $0.quantity }, "no order overfilled")
        for (symbol, p) in a.positions {
            #expect(p.quantity != 0 && abs(p.quantity) <= configuration.risk.maxPositionPerSymbol, "\(symbol)")
        }
        // Reduce-only orders never point the wrong way.
        for o in a.openOrders where o.role.isReduceOnly && o.status != .accepted {
            #expect(a.position(o.symbol).map { $0.side != o.side } == true)
        }
    }
}
