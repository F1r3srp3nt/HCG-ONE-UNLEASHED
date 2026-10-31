import Foundation
import Testing
import HCGDomain
@testable import HCGTrading

/// `book(...)` with trades printed during the update.
func withPrints(_ v: MarketView, _ prints: [TradePrint]) -> MarketView {
    MarketView(symbol: v.symbol, sequence: v.sequence, time: v.time, bidTicks: v.bidTicks, askTicks: v.askTicks,
               lastTicks: v.lastTicks, bids: v.bids, asks: v.asks, prints: prints)
}

func sold(_ size: Int, at price: Int64) -> TradePrint { TradePrint(priceTicks: price, size: size, aggressor: .sell) }

// MARK: - Queue position (D-34)

@Suite("Order flow realism — queue position")
struct QueuePositionTests {
    let spec = MarketSymbol.es.spec

    @Test("A bid joining the best bid waits behind the displayed size, then fills from prints at its price")
    func joinTheBid() {
        var account = TradingAccount(configuration: frictionless())
        let r = account.submit(.limit(.buy, 2, .es, at: spec.price(ticks: 21_920), id: "a"), book(bid: 21_920, size: 10, sequence: 1))
        #expect(r.order.status == .working)
        #expect(account.openOrders.first?.queueAhead == 10, "behind the 10 contracts shown at 21920")

        account.process(market: withPrints(book(bid: 21_920, size: 10, sequence: 2), [sold(6, at: 21_920)]))
        #expect(account.position(.es) == nil, "6 of the 10 ahead traded")
        #expect(account.openOrders.first?.queueAhead == 4)

        account.process(market: withPrints(book(bid: 21_920, size: 10, sequence: 3), [sold(5, at: 21_920)]))
        #expect(account.position(.es)?.quantity == 1, "4 cleared the queue, 1 filled us")
        #expect(account.fills.last?.liquidity == .maker)
        #expect(account.fills.last?.price == spec.price(ticks: 21_920))

        account.process(market: withPrints(book(bid: 21_920, size: 10, sequence: 4), [sold(3, at: 21_920)]))
        #expect(account.position(.es)?.quantity == 2)
        #expect(account.openOrders.isEmpty)
    }

    @Test("Your own earlier orders at the same price are ahead of you (FIFO)")
    func ownOrdersAreAhead() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, size: 10, sequence: 1)
        account.submit(.limit(.buy, 3, .es, at: spec.price(ticks: 21_920), id: "first"), v)
        account.submit(.limit(.buy, 3, .es, at: spec.price(ticks: 21_920), id: "second"), v)
        #expect(account.openOrders.map(\.queueAhead) == [10, 13])

        account.process(market: withPrints(book(bid: 21_920, size: 10, sequence: 2), [sold(12, at: 21_920)]))
        #expect(account.openOrders.map(\.filledQuantity) == [2, 0])
        account.process(market: withPrints(book(bid: 21_920, size: 10, sequence: 3), [sold(4, at: 21_920)]))
        #expect(account.position(.es)?.quantity == 6, "1 more for the first order, then 3 for the second")
        #expect(account.noOrderOverfilled())
    }

    @Test("Improving on the best price puts you at the front")
    func insideTheSpread() {
        var account = TradingAccount(configuration: frictionless())
        account.submit(.limit(.buy, 2, .es, at: spec.price(ticks: 21_921), id: "a"), book(bid: 21_920, ask: 21_923, sequence: 1))
        #expect(account.openOrders.first?.queueAhead == 0)
        account.process(market: withPrints(book(bid: 21_920, ask: 21_923, sequence: 2), [sold(2, at: 21_921)]))
        #expect(account.position(.es)?.quantity == 2)
    }

    @Test("Size leaving the displayed level shortens the queue; a print through the price fills completely")
    func shrinkingQueueAndTradeThrough() {
        var account = TradingAccount(configuration: frictionless())
        account.submit(.limit(.buy, 5, .es, at: spec.price(ticks: 21_920), id: "a"), book(bid: 21_920, size: 10, sequence: 1))
        account.process(market: book(bid: 21_920, size: 4, sequence: 2))
        #expect(account.openOrders.first?.queueAhead == 4, "only 4 remain displayed ahead")
        #expect(account.position(.es) == nil)

        account.process(market: withPrints(book(bid: 21_920, size: 4, sequence: 3), [sold(1, at: 21_919)]))
        #expect(account.position(.es)?.quantity == 5, "a trade below the bid means every bid at 21920 was filled")
    }

    @Test("Touch alone no longer fills a bid: the offer must reach it or trades must print there")
    func touchWithoutTrades() {
        var account = TradingAccount(configuration: frictionless())
        account.submit(.limit(.buy, 1, .es, at: spec.price(ticks: 21_920), id: "a"), book(bid: 21_920, size: 10, sequence: 1))
        account.process(market: book(bid: 21_920, size: 10, sequence: 2))
        #expect(account.position(.es) == nil, "sitting at the bid with no trades does not fill")
    }

    @Test("A price beyond the visible depth joins the queue when it comes into view")
    func beyondVisibleDepth() {
        var account = TradingAccount(configuration: frictionless())
        account.submit(.limit(.buy, 1, .es, at: spec.price(ticks: 21_900), id: "a"), book(bid: 21_920, depth: 10, sequence: 1))
        #expect(account.openOrders.first?.queueAhead == nil, "21900 is not among the 10 visible bid levels")
        account.process(market: book(bid: 21_905, size: 7, depth: 10, sequence: 2))
        #expect(account.openOrders.first?.queueAhead == 7)
    }

    @Test("A preview estimate matches the queue the order gets")
    func previewEstimate() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, size: 10, sequence: 1)
        #expect(account.estimatedQueue(side: .buy, limitTicks: 21_919, market: v) == 10)
        #expect(account.estimatedQueue(side: .sell, limitTicks: 21_921, market: v) == 10)
        #expect(account.estimatedQueue(side: .buy, limitTicks: 21_850, market: v) == nil)
        account.submit(.limit(.buy, 2, .es, at: spec.price(ticks: 21_919), id: "a"), v)
        #expect(account.estimatedQueue(side: .buy, limitTicks: 21_919, market: v) == 12)
    }
}

// MARK: - Shared liquidity within an update (D-33c)

@Suite("Order flow realism — shared liquidity")
struct SharedLiquidityTests {
    @Test("Two market orders in the same update cannot both take the same contracts")
    func marketOrdersShareTheBook() {
        var account = TradingAccount(configuration: frictionless())
        let v = book(bid: 21_920, size: 10, sequence: 1) // asks 21921 ×10, 21922 ×10, …
        let first = account.submit(.market(.buy, 8, .es, id: "a"), v)
        let second = account.submit(.market(.buy, 8, .es, id: "b"), v)
        let spec = MarketSymbol.es.spec
        #expect(first.fills.first?.price == spec.price(ticks: 21_921))
        #expect(second.fills.first?.price == spec.price(fractionalTicks: (2 * 21_921 + 6 * 21_922) / 8.0),
                "2 left at 21921, then 6 at 21922")

        let later = account.submit(.market(.buy, 8, .es, id: "c"), book(bid: 21_920, size: 10, sequence: 2))
        #expect(later.fills.first?.price == spec.price(ticks: 21_921), "a new update shows fresh liquidity")
    }
}

// MARK: - Account risk rules (D-35)

@Suite("Account risk rules")
struct RiskRuleTests {
    let spec = MarketSymbol.es.spec

    private func config(daily: Double? = nil, drawdown: Double? = nil, liquidate: Bool = false,
                        esMargin: Double? = nil) -> AccountConfiguration {
        var c = frictionless()
        c.risk.dailyLossLimit = daily
        c.risk.trailingDrawdown = drawdown
        c.risk.liquidateOnMarginShortfall = liquidate
        if let esMargin {
            c.costs[.es] = InstrumentCosts(commissionPerContract: 0, feesPerContract: 0, initialMarginPerContract: esMargin)
        }
        return c
    }

    @Test("The daily loss limit closes everything, locks entries for the session, and unlocks at the next")
    func dailyLossLimit() {
        var account = TradingAccount(configuration: config(daily: 100))
        let v1 = book(bid: 21_920, sequence: 1)
        account.submit(.market(.buy, 2, .es, id: "a"), v1)                              // long 2 at 21921
        account.submit(.limit(.buy, 1, .es, at: spec.price(ticks: 21_900), id: "w"), v1)
        account.enforceRisk(markets: [.es: v1])                                          // session starts: −$25
        #expect(account.tradingLock == nil)

        let v2 = book(bid: 21_915, sequence: 2)                                          // −$150 total, −$125 today
        let locked = account.enforceRisk(markets: [.es: v2])
        #expect(locked)
        #expect(account.position(.es) == nil, "position closed")
        #expect(account.openOrders.isEmpty, "working orders cancelled")
        #expect(account.tradingLock?.rule == .dailyLoss)
        #expect(account.events.contains { $0.kind == .tradingLocked })

        let blocked = account.submit(.market(.buy, 1, .es, id: "b"), book(bid: 21_915, sequence: 3))
        #expect(blocked.order.status == .rejected)
        #expect(blocked.order.statusReason?.contains("locked") == true)

        let nextSession = book(bid: 21_915, sequence: 3 + 86_400)                        // one simulated day later
        account.enforceRisk(markets: [.es: nextSession])
        #expect(account.tradingLock == nil)
        let resumed = account.submit(.market(.buy, 1, .es, id: "c"), nextSession)
        #expect(resumed.order.status == .filled)
    }

    @Test("The trailing drawdown floor follows the equity high, stops at the starting balance, and locks until reset")
    func trailingDrawdown() {
        var account = TradingAccount(configuration: config(drawdown: 1_000))
        let v1 = book(bid: 21_920, sequence: 1)
        account.submit(.market(.buy, 1, .es, id: "a"), v1)                               // long 1 at 21921
        account.enforceRisk(markets: [.es: v1])
        #expect(account.riskStatus(quotes: quotes(v1)).drawdownFloor == 49_000)

        account.enforceRisk(markets: [.es: book(bid: 22_001, sequence: 2)])              // +$1,000
        #expect(account.riskStatus(quotes: quotes(book(bid: 22_001, sequence: 2))).drawdownFloor == 50_000)
        account.enforceRisk(markets: [.es: book(bid: 22_041, sequence: 3)])              // +$1,500
        #expect(account.riskStatus(quotes: quotes(book(bid: 22_041, sequence: 3))).drawdownFloor == 50_000,
                "the floor stops trailing at the starting balance")

        account.enforceRisk(markets: [.es: book(bid: 21_921, sequence: 4)])              // back to $50,000
        #expect(account.position(.es) == nil)
        #expect(account.tradingLock?.rule == .trailingDrawdown)
        #expect(account.tradingLock?.untilSessionDay == nil)

        account.enforceRisk(markets: [.es: book(bid: 21_921, sequence: 5 + 86_400)])
        #expect(account.tradingLock != nil, "a new session does not unlock a drawdown breach")
        account.reset(at: Stamp(sequence: 6, time: Date()))
        #expect(account.tradingLock == nil)
    }

    @Test("Equity below the margin of the open positions liquidates them without locking")
    func marginLiquidation() {
        var account = TradingAccount(configuration: config(liquidate: true, esMargin: 15_000))
        let v1 = book(bid: 21_920, sequence: 1)
        account.submit(.market(.buy, 3, .es, id: "a"), v1)                               // margin $45,000
        account.enforceRisk(markets: [.es: v1])
        #expect(account.position(.es)?.quantity == 3)

        let down = book(bid: 21_781, sequence: 2)                                        // −$5,250 → equity $44,750
        let liquidated = account.enforceRisk(markets: [.es: down])
        #expect(liquidated)
        #expect(account.position(.es) == nil)
        #expect(account.tradingLock == nil)
        #expect(account.events.contains { $0.kind == .liquidation })
    }

    @Test("Rules that are off never act")
    func rulesOff() {
        var account = TradingAccount(configuration: config())
        account.submit(.market(.buy, 3, .es, id: "a"), book(bid: 21_920, sequence: 1))
        let acted = account.enforceRisk(markets: [.es: book(bid: 21_000, sequence: 2)])
        #expect(!acted)
        #expect(account.position(.es)?.quantity == 3)
    }

    @Test("Sessions saved before the risk rules existed load with the rules off")
    func oldConfigurationDecodes() throws {
        let json = #"{"maxOrderQuantity":10,"maxPositionPerSymbol":5,"enforceBuyingPower":true}"#
        let limits = try JSONDecoder().decode(RiskLimits.self, from: Data(json.utf8))
        #expect(limits.dailyLossLimit == nil && limits.trailingDrawdown == nil && !limits.liquidateOnMarginShortfall)
        #expect(limits.maxOrderQuantity == 10)
    }

    @Test("The default account is a $50,000 evaluation-style account with intraday margins")
    func defaults() {
        let c = AccountConfiguration.standard
        #expect(c.startingBalance == 50_000)
        #expect(c.risk == .evaluation)
        #expect(c.risk.maxPositionPerSymbol == 5 && c.risk.dailyLossLimit == 1_000 && c.risk.trailingDrawdown == 2_000)
        #expect(c.costs(for: .es).initialMarginPerContract == 500)
        #expect(c.validationErrors().isEmpty)
        var bad = c
        bad.risk.dailyLossLimit = 0
        #expect(!bad.validationErrors().isEmpty)
    }
}
