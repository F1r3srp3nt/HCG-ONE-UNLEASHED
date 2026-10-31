import Foundation
import Testing
import HCGDomain
@testable import HCGTrading

// MARK: - Fixtures

/// A hand-built book: asks at `ask, ask+1, …`, bids at `bid, bid−1, …`,
/// every level `size` contracts, `depth` levels per side.
func book(_ symbol: MarketSymbol = .es, bid: Int64 = 21_920, ask: Int64? = nil, size: Int = 10,
          depth: Int = 10, sequence: Int) -> MarketView {
    let ask = ask ?? bid + 1
    return MarketView(
        symbol: symbol, sequence: sequence, time: Date(timeIntervalSince1970: 1_000_000 + Double(sequence)),
        bidTicks: bid, askTicks: ask, lastTicks: ask,
        bids: (0..<depth).map { PriceLevel(priceTicks: bid - Int64($0), size: size) },
        asks: (0..<depth).map { PriceLevel(priceTicks: ask + Int64($0), size: size) })
}

func quotes(_ views: MarketView...) -> [MarketSymbol: Quote] {
    var q: [MarketSymbol: Quote] = [:]
    for v in views { q[v.symbol] = Quote(bidTicks: v.bidTicks, askTicks: v.askTicks) }
    return q
}

/// Configuration with no costs (and, by default, no margin check), so P&L
/// assertions are exact. Buying power is tested separately with `.standard`.
func frictionless(slippage: Int = 0, maxOrder: Int = 100, maxPosition: Int = 50, buyingPower: Bool = false) -> AccountConfiguration {
    var c = AccountConfiguration.standard
    for s in MarketSymbol.allCases {
        c.costs[s] = InstrumentCosts(commissionPerContract: 0, feesPerContract: 0,
                                     initialMarginPerContract: c.costs(for: s).initialMarginPerContract)
    }
    c.slippageTicks = slippage
    c.risk = RiskLimits(maxOrderQuantity: maxOrder, maxPositionPerSymbol: maxPosition, enforceBuyingPower: buyingPower)
    return c
}

extension TradingAccount {
    @discardableResult
    mutating func submit(_ r: OrderRequest, _ v: MarketView) -> OrderResult {
        submit(r, market: v, quotes: quotes(v))
    }

    /// Every fill of every order stays within its quantity.
    func noOrderOverfilled() -> Bool {
        let byOrder = Dictionary(grouping: fills, by: \.orderID).mapValues { $0.reduce(0) { $0 + $1.quantity } }
        let all = openOrders + orderHistory
        return byOrder.allSatisfy { id, qty in all.first { $0.id == id }.map { qty <= $0.quantity } ?? true }
    }
}

let esTick = MarketSymbol.es.spec.tickValue // $12.50

// MARK: - Market orders

@Suite("Trading engine — market orders")
struct MarketOrderTests {
    @Test("Market buy fills at the ask and opens a long; costs reduce cash")
    func marketBuy() {
        var account = TradingAccount()
        let v = book(sequence: 1)
        let r = account.submit(.market(.buy, 3, .es, id: "a"), v)
        #expect(r.order.status == .filled)
        #expect(r.fills.count == 1)
        #expect(r.fills[0].price == v.ask)
        #expect(r.fills[0].liquidity == .taker)
        #expect(account.position(.es)?.quantity == 3)
        #expect(account.position(.es)?.averagePrice == v.ask)
        #expect(abs(account.commissionsPaid - 6) < 1e-9, "3 × $2.00 standard ES commission")
        #expect(abs(account.cash - (50_000 - 6)) < 1e-9)
    }

    @Test("Market sell fills at the bid")
    func marketSell() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(sequence: 1)
        let r = account.submit(.market(.sell, 2, .es, id: "a"), v)
        #expect(r.fills.first?.price == v.bid)
        #expect(account.position(.es)?.quantity == -2)
    }

    @Test("Large market orders walk the book to a volume-weighted price")
    func walksBook() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, size: 10, sequence: 1) // asks 21921×10, 21922×10, …
        let r = account.submit(.market(.buy, 25, .es, id: "a"), v)
        // 10 @ 21921 + 10 @ 21922 + 5 @ 21923 = 548,045 tick-contracts → 21,921.8 ticks
        let expected = MarketSymbol.es.spec.price(fractionalTicks: 548_045.0 / 25)
        #expect(abs(r.fills[0].price - expected) < 1e-9)
        #expect(r.order.filledQuantity == 25)
    }

    @Test("Configured slippage is added against the trader")
    func slippage() {
        var account = TradingAccount(configuration: frictionless(slippage: 2))
        let v = book(sequence: 1)
        let buy = account.submit(.market(.buy, 1, .es, id: "a"), v)
        let sell = account.submit(.market(.sell, 1, .es, id: "b"), v)
        #expect(buy.fills[0].price == MarketSymbol.es.spec.price(ticks: v.askTicks + 2))
        #expect(sell.fills[0].price == MarketSymbol.es.spec.price(ticks: v.bidTicks - 2))
    }

    @Test("Not enough depth: the available part fills, the remainder is cancelled")
    func partialMarketFill() {
        var account = TradingAccount(configuration: frictionless())
        let thin = book(size: 2, depth: 3, sequence: 1) // 6 contracts on the offer
        let r = account.submit(.market(.buy, 10, .es, id: "a"), thin)
        #expect(r.order.status == .cancelled)
        #expect(r.order.filledQuantity == 6)
        #expect(r.order.statusReason?.contains("liquidity") == true)
        #expect(account.position(.es)?.quantity == 6)
    }
}

// MARK: - Limit and stop orders

@Suite("Trading engine — limit and stop orders")
struct WorkingOrderTests {
    @Test("A resting buy limit fills at its price: partially on touch, fully on trade-through")
    func restingLimitBuy() {
        var account = TradingAccount(configuration: frictionless())
        let limitTicks: Int64 = 21_915
        let price = MarketSymbol.es.spec.price(ticks: limitTicks)
        let r = account.submit(.limit(.buy, 8, .es, at: price, id: "a"), book(bid: 21_920, sequence: 1))
        #expect(r.order.status == .working)
        #expect(r.fills.isEmpty)

        // Ask still above the limit: nothing.
        let r1 = account.process(market: book(bid: 21_917, sequence: 2))
        #expect(r1.isEmpty)
        // Ask touches the limit with 3 contracts shown: 3 fill (maker, at the limit).
        let touch = account.process(market: book(bid: 21_914, ask: 21_915, size: 3, sequence: 3))
        #expect(touch.map(\.quantity) == [3])
        #expect(touch.first?.price == price)
        #expect(touch.first?.liquidity == .maker)
        #expect(account.openOrders.first?.status == .partiallyFilled)
        // Ask trades through the limit: the remaining 5 fill at the limit, not better.
        let through = account.process(market: book(bid: 21_910, ask: 21_912, size: 1, sequence: 4))
        #expect(through.map(\.quantity) == [5])
        #expect(through.first?.price == price)
        #expect(account.position(.es)?.quantity == 8)
        #expect(account.openOrders.isEmpty)
        #expect(account.orderHistory.last?.status == .filled)
    }

    @Test("A marketable limit takes liquidity up to its price and rests the rest")
    func marketableLimit() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, size: 4, sequence: 1) // asks 21921×4, 21922×4, 21923×4 …
        let limit = MarketSymbol.es.spec.price(ticks: 21_922)
        let r = account.submit(.limit(.buy, 10, .es, at: limit, id: "a"), v)
        #expect(r.order.status == .partiallyFilled)
        #expect(r.order.filledQuantity == 8, "two levels at or below the limit")
        #expect(r.fills.first?.liquidity == .taker)
        #expect(account.openOrders.first?.remainingQuantity == 2)
    }

    @Test("A sell limit fills when the bid reaches it")
    func restingLimitSell() {
        var account = TradingAccount(configuration: frictionless())
        let price = MarketSymbol.es.spec.price(ticks: 21_925)
        account.submit(.limit(.sell, 2, .es, at: price, id: "a"), book(bid: 21_920, sequence: 1))
        let r2 = account.process(market: book(bid: 21_924, sequence: 2))
        #expect(r2.isEmpty)
        let fills = account.process(market: book(bid: 21_926, sequence: 3))
        #expect(fills.map(\.price) == [price])
        #expect(account.position(.es)?.quantity == -2)
    }

    @Test("Stops must be on the far side of the market, and trigger at market")
    func stops() {
        var account = TradingAccount(configuration: frictionless(slippage: 1))
        let v = book(bid: 21_920, sequence: 1) // ask 21921
        let spec = MarketSymbol.es.spec
        let r3 = account.submit(.stop(.buy, 1, .es, at: spec.price(ticks: 21_921), id: "bad-buy"), v)
        #expect(r3.order.status == .rejected)
        let r4 = account.submit(.stop(.sell, 1, .es, at: spec.price(ticks: 21_920), id: "bad-sell"), v)
        #expect(r4.order.status == .rejected)

        let stop = account.submit(.stop(.buy, 2, .es, at: spec.price(ticks: 21_925), id: "a"), v)
        #expect(stop.order.status == .working)
        let r5 = account.process(market: book(bid: 21_922, sequence: 2))
        #expect(r5.isEmpty) // ask 21923 < stop
        let fills = account.process(market: book(bid: 21_926, sequence: 3))      // ask 21927 ≥ stop
        #expect(fills.count == 1)
        #expect(fills[0].price == spec.price(ticks: 21_927 + 1), "fills at the ask plus 1 tick slippage")
        #expect(fills[0].liquidity == .taker)
        #expect(account.position(.es)?.quantity == 2)
    }

    @Test("Cancelling a working order never touches the position")
    func cancel() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(sequence: 1)
        account.submit(.market(.buy, 1, .es, id: "m"), v)
        let r = account.submit(.limit(.buy, 1, .es, at: MarketSymbol.es.spec.price(ticks: 21_900), id: "l"), v)
        let r6 = account.cancel(orderID: r.order.id, at: Stamp(sequence: 2, time: v.time))
        #expect(r6)
        #expect(account.order(id: r.order.id)?.status == .cancelled)
        #expect(account.position(.es)?.quantity == 1)
        let r7 = account.cancel(orderID: r.order.id, at: Stamp(sequence: 3, time: v.time))
        #expect(!r7, "already final")
        let r8 = account.process(market: book(bid: 21_890, sequence: 4))
        #expect(r8.isEmpty, "a cancelled order never fills")
    }
}

// MARK: - Brackets and protection

@Suite("Trading engine — brackets, stop-loss and take-profit")
struct BracketTests {
    @Test("Market entry with a bracket: take-profit fills, stop-loss is cancelled (OCO)")
    func bracketTakeProfit() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, sequence: 1) // entry at ask 21921
        let r = account.submit(.market(.buy, 2, .es, id: "a", bracket: BracketSpec(takeProfitTicks: 8, stopLossTicks: 4)), v)
        #expect(r.order.status == .filled)
        let children = account.openOrders.filter { $0.parentID == r.order.id }
        #expect(children.count == 2)
        #expect(children.allSatisfy { $0.status == .working && $0.quantity == 2 && $0.side == .sell })
        #expect(children.first { $0.role == .takeProfit }?.limitTicks == 21_929)
        #expect(children.first { $0.role == .stopLoss }?.stopTicks == 21_917)

        let fills = account.process(market: book(bid: 21_930, sequence: 2)) // bid crosses 21929
        #expect(fills.map(\.quantity) == [2])
        #expect(account.position(.es) == nil)
        #expect(account.openOrders.isEmpty, "the stop-loss was cancelled")
        #expect(account.orderHistory.contains { $0.role == .stopLoss && $0.status == .cancelled && $0.statusReason?.contains("OCO") == true })
        let trade = account.trades.last
        #expect(trade?.direction == .long)
        #expect(abs((trade?.grossPnL ?? 0) - 8 * esTick * 2) < 1e-6)
    }

    @Test("Stop-loss fills at market and cancels the take-profit")
    func bracketStopLoss() {
        var account = TradingAccount(configuration: frictionless())
        account.submit(.market(.sell, 1, .es, id: "a", bracket: BracketSpec(takeProfitTicks: 10, stopLossTicks: 3)),
                       book(bid: 21_920, sequence: 1)) // short at 21920; SL buy stop 21923, TP buy limit 21910
        let fills = account.process(market: book(bid: 21_923, sequence: 2)) // ask 21924 ≥ 21923
        #expect(fills.count == 1)
        #expect(account.position(.es) == nil)
        #expect(account.openOrders.isEmpty)
        #expect(account.realizedPnL < 0)
        #expect(abs(account.realizedPnL - (-4 * esTick)) < 1e-6, "short 21920, covered at the ask 21924")
    }

    @Test("Bracket orders on a limit entry wait as accepted, follow partial fills and die with the entry")
    func bracketOnLimitEntry() {
        var account = TradingAccount(configuration: frictionless())
        let spec = MarketSymbol.es.spec
        let entry = account.submit(.limit(.buy, 6, .es, at: spec.price(ticks: 21_915), id: "a",
                                          bracket: BracketSpec(takeProfitTicks: 5, stopLossTicks: 5)), book(sequence: 1))
        #expect(account.openOrders.filter { $0.parentID == entry.order.id }.allSatisfy { $0.status == .accepted })
        // Touch with 2 contracts: children activate for the 2 filled.
        account.process(market: book(bid: 21_914, ask: 21_915, size: 2, sequence: 2))
        let children = account.openOrders.filter { $0.parentID == entry.order.id }
        #expect(children.allSatisfy { $0.status == .working && $0.quantity == 2 })
        // Cancel the rest of the entry: the working children keep protecting the 2 contracts.
        let r9 = account.cancel(orderID: entry.order.id, at: Stamp(sequence: 3, time: Date()))
        #expect(r9)
        #expect(account.openOrders.filter { $0.parentID == entry.order.id }.count == 2)

        // A fresh limit entry cancelled before any fill takes its children with it.
        let other = account.submit(.limit(.buy, 1, .es, at: spec.price(ticks: 21_900), id: "b",
                                          bracket: BracketSpec(stopLossTicks: 4)), book(bid: 21_914, sequence: 4))
        account.cancel(orderID: other.order.id, at: Stamp(sequence: 5, time: Date()))
        #expect(!account.openOrders.contains { $0.parentID == other.order.id })
    }

    @Test("Position protection: validated, replaceable, and removed when the position closes")
    func protection() {
        var account = TradingAccount(configuration: frictionless())
        let spec = MarketSymbol.es.spec
        let v = book(bid: 21_920, sequence: 1)
        let r10 = account.setProtection(stopLoss: 1, takeProfit: nil, market: v)
        #expect(r10.isEmpty, "no position, nothing to protect")
        account.submit(.market(.buy, 3, .es, id: "a"), v)

        let bad = account.setProtection(stopLoss: spec.price(ticks: 21_925), takeProfit: spec.price(ticks: 21_915), market: v)
        #expect(bad.allSatisfy { $0.order.status == .rejected }, "stop above bid and target below bid are invalid for a long")

        let good = account.setProtection(stopLoss: spec.price(ticks: 21_910), takeProfit: spec.price(ticks: 21_940), market: v)
        #expect(good.allSatisfy { $0.order.status == .working })
        let replaced = account.setProtection(stopLoss: spec.price(ticks: 21_912), takeProfit: nil, market: v)
        #expect(replaced.count == 1)
        #expect(account.openOrders.filter(\.role.isReduceOnly).count == 1, "old protection replaced")

        account.closePosition(market: book(bid: 21_921, sequence: 2))
        #expect(account.position(.es) == nil)
        #expect(account.openOrders.isEmpty, "protection cancelled with the position")
    }

    @Test("New protection replaces a working bracket, so a position never carries two stops")
    func protectionReplacesBracket() {
        var account = TradingAccount(configuration: frictionless())
        let spec = MarketSymbol.es.spec
        let v = book(bid: 21_920, sequence: 1)
        account.submit(.market(.buy, 2, .es, id: "a", bracket: BracketSpec(takeProfitTicks: 8, stopLossTicks: 8)), v)
        #expect(account.openOrders.filter(\.role.isReduceOnly).count == 2)
        let r = account.setProtection(stopLoss: spec.price(ticks: 21_915), takeProfit: spec.price(ticks: 21_930), market: v)
        #expect(r.allSatisfy { $0.order.status == .working })
        let protective = account.openOrders.filter(\.role.isReduceOnly)
        #expect(protective.count == 2, "bracket stop and target replaced, not duplicated")
        #expect(Set(protective.compactMap { $0.stopTicks ?? $0.limitTicks }) == [21_915, 21_930])
        #expect(protective.allSatisfy { $0.quantity == 2 })

        let removed = account.setProtection(stopLoss: nil, takeProfit: nil, market: v)
        #expect(removed.isEmpty)
        #expect(account.openOrders.isEmpty, "passing no prices removes the protection")
        #expect(account.position(.es)?.quantity == 2)
    }

    @Test("An invalid replacement is rejected and the existing protection stays in place")
    func invalidProtectionKeepsExisting() {
        var account = TradingAccount(configuration: frictionless())
        let spec = MarketSymbol.es.spec
        let v = book(bid: 21_920, sequence: 1)
        account.submit(.market(.buy, 1, .es, id: "a"), v)
        account.setProtection(stopLoss: spec.price(ticks: 21_910), takeProfit: spec.price(ticks: 21_940), market: v)
        let before = account.openOrders.map(\.id)

        // Valid target, but the stop is above the bid for a long.
        let r = account.setProtection(stopLoss: spec.price(ticks: 21_925), takeProfit: spec.price(ticks: 21_950), market: v)
        #expect(r.count == 2 && r.allSatisfy { $0.order.status == .rejected })
        #expect(r.contains { $0.order.statusReason?.contains("other protective price") == true },
                "the valid half says why it was not placed")
        #expect(account.openOrders.map(\.id) == before, "the working stop and target were not cancelled")
        #expect(account.openOrders.allSatisfy { $0.status == .working })
    }

    @Test("Margin preview counts the new order on top of positions and working entries")
    func marginPreview() {
        var account = TradingAccount() // standard: ES intraday margin $500, CL $1,000
        let v = book(bid: 21_920, sequence: 1)
        #expect(account.marginRequirement(adding: .buy, quantity: 2, symbol: .es) == 1_000)
        account.submit(.market(.buy, 1, .es, id: "a"), v)
        #expect(account.marginRequirement() == 500)
        #expect(account.marginRequirement(adding: .buy, quantity: 1, symbol: .es) == 1_000)
        #expect(account.marginRequirement(adding: .sell, quantity: 1, symbol: .es) == 500, "a sell of 1 only flattens")
        #expect(account.marginRequirement(adding: .buy, quantity: 1, symbol: .cl) == 1_500, "500 ES + 1,000 CL")
    }
}

// MARK: - Accounting

@Suite("Trading engine — position accounting")
struct AccountingTests {
    @Test("Ten ticks of profit is worth 10 × the contract's tick value", arguments: MarketSymbol.allCases)
    func contractMultipliers(_ symbol: MarketSymbol) {
        var account = TradingAccount(configuration: frictionless())
        let start: Int64 = 50_000
        account.submit(.market(.buy, 1, symbol, id: "a"), book(symbol, bid: start - 1, ask: start, sequence: 1))
        account.submit(.market(.sell, 1, symbol, id: "b"), book(symbol, bid: start + 10, sequence: 2))
        #expect(abs(account.realizedPnL - 10 * symbol.spec.tickValue) < 1e-6)
        #expect(account.trades.count == 1)
    }

    @Test("Adding averages the entry; reducing realises P&L; reversing opens at the fill price")
    func addReduceReverse() {
        var account = TradingAccount(configuration: frictionless())
        let spec = MarketSymbol.es.spec
        account.submit(.market(.buy, 1, .es, id: "a"), book(bid: 21_919, ask: 21_920, sequence: 1))
        account.submit(.market(.buy, 1, .es, id: "b"), book(bid: 21_923, ask: 21_924, sequence: 2))
        #expect(account.position(.es)?.averagePrice == spec.price(ticks: 21_922))
        account.submit(.market(.sell, 3, .es, id: "c"), book(bid: 21_930, sequence: 3))
        #expect(abs(account.realizedPnL - 2 * 8 * esTick) < 1e-6, "2 contracts × 8 ticks")
        #expect(account.position(.es)?.quantity == -1)
        #expect(account.position(.es)?.averagePrice == spec.price(ticks: 21_930))
    }

    @Test("Unrealised P&L marks longs at the bid and shorts at the ask")
    func marks() {
        var long = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, sequence: 1)
        long.submit(.market(.buy, 1, .es, id: "a"), v)
        #expect(abs(long.unrealizedPnL(.es, quote: Quote(bidTicks: 21_920, askTicks: 21_921)) + esTick) < 1e-9)
        var short = TradingAccount(configuration: frictionless())
        short.submit(.market(.sell, 1, .es, id: "a"), v)
        #expect(abs(short.unrealizedPnL(.es, quote: Quote(bidTicks: 21_920, askTicks: 21_921)) + esTick) < 1e-9)
    }

    @Test("Commission and fees are charged per contract per fill and attributed to round trips")
    func commissions() {
        var c = AccountConfiguration.standard
        c.costs[.gc] = InstrumentCosts(commissionPerContract: 2.5, feesPerContract: 1.25, initialMarginPerContract: 10_000)
        var account = TradingAccount(configuration: c)
        account.submit(.market(.buy, 4, .gc, id: "a"), book(.gc, bid: 26_550, sequence: 1))
        account.submit(.market(.sell, 4, .gc, id: "b"), book(.gc, bid: 26_551, sequence: 2))
        #expect(abs(account.commissionsPaid - 20) < 1e-9)
        #expect(abs(account.feesPaid - 10) < 1e-9)
        let trade = account.trades.last
        #expect(abs((trade?.costs ?? 0) - 30) < 1e-9)
        #expect(abs((trade?.grossPnL ?? 1)) < 1e-9, "bought at the ask, sold at the same price: zero gross")
        #expect(abs((trade?.netPnL ?? 0) + 30) < 1e-9, "net = −costs")
        #expect(abs(account.cash - (50_000 - 30)) < 1e-9)
    }

    @Test("Cash identity holds: start + realised − commissions − fees")
    func cashIdentity() {
        var account = TradingAccount()
        for i in 1...40 {
            account.submit(.market(i % 3 == 0 ? .sell : .buy, 1 + i % 2, .nq, id: "o\(i)"),
                           book(.nq, bid: 79_400 + Int64(i % 7), sequence: i))
        }
        #expect(abs(account.cash - (50_000 + account.realizedPnL - account.commissionsPaid - account.feesPaid)) < 1e-9)
        let fromFills = account.fills.reduce(0) { $0 + $1.realizedPnL }
        #expect(abs(fromFills - account.realizedPnL) < 1e-6)
    }
}

// MARK: - Validation, risk and integrity

@Suite("Trading engine — validation, risk and integrity")
struct IntegrityTests {
    @Test("Invalid requests are rejected with a reason and change no position")
    func validation() {
        var account = TradingAccount(configuration: frictionless(maxOrder: 10))
        let v = book(sequence: 1)
        let cases: [OrderRequest] = [
            .market(.buy, 0, .es, id: "q0"),
            .market(.buy, 11, .es, id: "q11"),
            OrderRequest(clientOrderID: "nolimit", symbol: .es, side: .buy, type: .limit, quantity: 1),
            .limit(.buy, 1, .es, at: 5_480.10, id: "offtick"),
            .limit(.buy, 1, .es, at: .nan, id: "nan"),
            .stop(.buy, 1, .es, at: .infinity, id: "inf"),
            .market(.buy, 1, .es, id: "bracket", bracket: BracketSpec()),
            .market(.buy, 1, .es, id: "bracket0", bracket: BracketSpec(takeProfitTicks: 0)),
        ]
        for request in cases {
            let r = account.submit(request, v)
            #expect(r.order.status == .rejected, "\(request.clientOrderID) must be rejected")
            #expect(r.order.statusReason?.isEmpty == false)
        }
        #expect(account.positions.isEmpty)
        #expect(account.fills.isEmpty)
    }

    @Test("Position limits count working orders that could add exposure")
    func positionLimit() {
        var account = TradingAccount(configuration: frictionless(maxPosition: 5))
        let v = book(sequence: 1)
        let r11 = account.submit(.market(.buy, 3, .es, id: "a"), v)
        #expect(r11.order.status == .filled)
        let r12 = account.submit(.limit(.buy, 2, .es, at: MarketSymbol.es.spec.price(ticks: 21_900), id: "b"), v)
        #expect(r12.order.status == .working)
        let r13 = account.submit(.market(.buy, 1, .es, id: "c"), v)
        #expect(r13.order.status == .rejected, "3 + 2 working + 1 > 5")
        let r14 = account.submit(.market(.sell, 4, .es, id: "d"), v)
        #expect(r14.order.status == .filled, "reducing is allowed")
    }

    @Test("Orders beyond the simulated buying power are rejected")
    func buyingPower() {
        var configuration = frictionless(buyingPower: true) // $50,000
        configuration.costs[.es] = InstrumentCosts(commissionPerContract: 2, feesPerContract: 0, initialMarginPerContract: 15_000)
        var account = TradingAccount(configuration: configuration)
        let v = book(sequence: 1)
        let r15 = account.submit(.market(.buy, 3, .es, id: "a"), v)
        #expect(r15.order.status == .filled)
        let r = account.submit(.market(.buy, 1, .es, id: "b"), v)
        #expect(r.order.status == .rejected)
        #expect(r.order.statusReason?.contains("buying power") == true)
        #expect(account.buyingPower(quotes: quotes(v)) < 15_000)
    }

    @Test("Duplicate client order IDs and repeated market updates never execute twice")
    func duplicatePrevention() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(sequence: 1)
        let r16 = account.submit(.market(.buy, 1, .es, id: "same"), v)
        #expect(r16.order.status == .filled)
        let r17 = account.submit(.market(.buy, 1, .es, id: "same"), v)
        #expect(r17.order.status == .rejected)
        #expect(account.position(.es)?.quantity == 1)

        account.submit(.limit(.buy, 5, .es, at: MarketSymbol.es.spec.price(ticks: 21_915), id: "lim"), v)
        let touch = book(bid: 21_914, ask: 21_915, size: 2, sequence: 2)
        let r18 = account.process(market: touch)
        #expect(r18.map(\.quantity) == [2])
        let r19 = account.process(market: touch)
        #expect(r19.isEmpty, "the same update is processed once")
        let r20 = account.process(market: book(bid: 21_914, ask: 21_915, size: 2, sequence: 1))
        #expect(r20.isEmpty, "older updates are ignored")
        #expect(account.noOrderOverfilled())
    }

    @Test("Reset clears everything; settings validate; the starting balance applies at reset")
    func resetAndConfiguration() {
        var account = TradingAccount()
        account.submit(.market(.buy, 1, .es, id: "a"), book(sequence: 1))
        var c = AccountConfiguration.standard
        c.startingBalance = -5
        let r21 = account.updateConfiguration(c, at: Stamp(sequence: 2, time: Date()))
        #expect(!r21.isEmpty)
        c.startingBalance = 100_000
        let r22 = account.updateConfiguration(c, at: Stamp(sequence: 2, time: Date()))
        #expect(r22.isEmpty)
        #expect(account.startingBalance == 50_000, "unchanged until reset")
        account.reset(at: Stamp(sequence: 3, time: Date()))
        #expect(account.startingBalance == 100_000)
        #expect(account.positions.isEmpty && account.fills.isEmpty && account.openOrders.isEmpty)
        #expect(account.resetCount == 1)
        #expect(account.events.last?.kind == .accountReset)
    }

    @Test("The account round-trips through JSON exactly, open orders included")
    func codableRoundTrip() throws {
        var account = TradingAccount()
        let spec = MarketSymbol.cl.spec
        account.submit(.market(.buy, 2, .cl, id: "a", bracket: BracketSpec(takeProfitTicks: 20, stopLossTicks: 10)),
                       book(.cl, bid: 7_740, sequence: 1))
        account.submit(.limit(.sell, 1, .cl, at: spec.price(ticks: 7_800), id: "b"), book(.cl, bid: 7_741, sequence: 2))
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(TradingAccount.self, from: data)
        #expect(decoded == account)
        #expect(decoded.openOrders.count == 3)
    }

    @Test("The same requests and market updates always produce the same account")
    func determinism() {
        func run() -> TradingAccount {
            var a = TradingAccount()
            let spec = MarketSymbol.gc.spec
            for i in 1...300 {
                let v = book(.gc, bid: 26_550 + Int64((i * 7) % 23) - 11, size: 3 + i % 5, sequence: i)
                if i % 25 == 1 {
                    a.submit(.limit(i % 2 == 0 ? .buy : .sell, 2, .gc, at: spec.price(ticks: v.bidTicks + (i % 2 == 0 ? -3 : 4)),
                                    id: "l\(i)", bracket: BracketSpec(takeProfitTicks: 6, stopLossTicks: 4)), market: v, quotes: quotes(v))
                }
                if i % 40 == 7 { a.submit(.market(.buy, 1, .gc, id: "m\(i)"), market: v, quotes: quotes(v)) }
                a.process(market: v)
            }
            return a
        }
        let first = run()
        #expect(first == run())
        #expect(!first.fills.isEmpty)
        #expect(first.noOrderOverfilled())
    }
}
