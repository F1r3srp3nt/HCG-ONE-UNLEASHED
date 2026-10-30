import Foundation
import HCGDomain

/// Sequence and simulated time at which an account change happened.
public struct Stamp: Codable, Hashable, Sendable {
    public let sequence: Int
    public let time: Date

    public init(sequence: Int, time: Date) {
        self.sequence = sequence
        self.time = time
    }
}

/// The simulated paper-trading account and its deterministic execution engine.
///
/// A value type: every change goes through a `mutating` method, so the whole
/// account (orders, positions, history) can be copied, compared, persisted
/// and replayed exactly. It contains no clocks, randomness or I/O.
///
/// Execution rules (documented in docs/TRADING_ENGINE.md):
/// - market orders and triggered stops take liquidity: they walk the opposite
///   side of the book best-first, then add the configured slippage ticks;
/// - a limit order that is marketable when submitted takes liquidity up to
///   its limit price; the rest rests and fills at its limit price when the
///   opposite best price touches it (up to the size shown there) or trades
///   through it (fully);
/// - take-profit and stop-loss orders are reduce-only and OCO;
/// - every market update is processed at most once per market.
public struct TradingAccount: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public static let orderHistoryLimit = 2_000
    public static let fillLimit = 5_000
    public static let tradeLimit = 5_000
    public static let eventLimit = 500
    static let clientIDMemory = 2_000

    /// Settings for new fills and the next reset.
    public private(set) var configuration: AccountConfiguration
    /// Balance this account started with (fixed until the next reset).
    public private(set) var startingBalance: Double
    public private(set) var realizedPnL = 0.0
    public private(set) var commissionsPaid = 0.0
    public private(set) var feesPaid = 0.0
    public private(set) var positions: [MarketSymbol: Position] = [:]
    /// Accepted, working and partially filled orders, by ascending id.
    public private(set) var openOrders: [Order] = []
    /// Final orders (filled, cancelled, rejected), oldest first, bounded.
    public private(set) var orderHistory: [Order] = []
    public private(set) var fills: [Fill] = []
    public private(set) var trades: [TradeRecord] = []
    public private(set) var events: [AccountEvent] = []
    /// Incremented on every change; used to decide when to save.
    public private(set) var revision = 0
    public private(set) var resetCount = 0

    private var nextOrderID = 1
    private var nextFillID = 1
    private var nextTradeID = 1
    private var nextEventID = 1
    private var nextOCOGroup = 1
    private var recentClientIDs: [String] = []
    private var lastProcessedSequence: [MarketSymbol: Int] = [:]
    private var lastStamp = Stamp(sequence: 0, time: Date(timeIntervalSince1970: 0))

    public init(configuration: AccountConfiguration = .standard) {
        self.configuration = configuration
        self.startingBalance = configuration.startingBalance
    }

    // MARK: - Account values

    /// Starting balance + realised P&L − commissions − fees.
    public var cash: Double { startingBalance + realizedPnL - commissionsPaid - feesPaid }

    public func position(_ symbol: MarketSymbol) -> Position? {
        guard let p = positions[symbol], !p.isFlat else { return nil }
        return p
    }

    /// Unrealised P&L, marking longs at the bid and shorts at the ask.
    public func unrealizedPnL(_ symbol: MarketSymbol, quote: Quote) -> Double {
        guard let p = position(symbol) else { return 0 }
        let spec = symbol.spec
        let mark = spec.price(ticks: p.isLong ? quote.bidTicks : quote.askTicks)
        return Double(p.quantity) * (mark - p.averagePrice) * spec.pointValue
    }

    public func unrealizedPnL(quotes: [MarketSymbol: Quote]) -> Double {
        positions.keys.reduce(0) { sum, symbol in
            guard let quote = quotes[symbol] else { return sum }
            return sum + unrealizedPnL(symbol, quote: quote)
        }
    }

    public func equity(quotes: [MarketSymbol: Quote]) -> Double {
        cash + unrealizedPnL(quotes: quotes)
    }

    /// Margin for open positions plus the worst case of working entry orders.
    public func marginRequirement() -> Double {
        MarketSymbol.allCases.reduce(0) { sum, symbol in
            sum + Double(worstCaseExposure(symbol)) * configuration.costs(for: symbol).initialMarginPerContract
        }
    }

    /// Pre-trade preview: the margin requirement if an entry order of this
    /// side and size were added to the working orders.
    public func marginRequirement(adding side: OrderSide, quantity: Int, symbol: MarketSymbol) -> Double {
        MarketSymbol.allCases.reduce(0) { sum, s in
            let extra = s == symbol ? (side: side, quantity: max(0, quantity)) : nil
            return sum + Double(worstCaseExposure(s, adding: extra)) * configuration.costs(for: s).initialMarginPerContract
        }
    }

    /// Equity not tied up by `marginRequirement()`.
    public func buyingPower(quotes: [MarketSymbol: Quote]) -> Double {
        equity(quotes: quotes) - marginRequirement()
    }

    public func openOrders(for symbol: MarketSymbol) -> [Order] {
        openOrders.filter { $0.symbol == symbol }
    }

    public func hasOpenOrders(_ symbol: MarketSymbol) -> Bool {
        openOrders.contains { $0.symbol == symbol }
    }

    public func order(id: Int) -> Order? {
        openOrders.first { $0.id == id } ?? orderHistory.last { $0.id == id }
    }

    /// Contracts the position could reach if every working entry order on one
    /// side filled (reduce-only orders never add exposure).
    func worstCaseExposure(_ symbol: MarketSymbol, adding extra: (side: OrderSide, quantity: Int)? = nil) -> Int {
        let q = positions[symbol]?.quantity ?? 0
        var buys = 0
        var sells = 0
        for o in openOrders where o.symbol == symbol && o.role == .entry && o.status != .accepted {
            if o.side == .buy { buys += o.remainingQuantity } else { sells += o.remainingQuantity }
        }
        if let extra {
            if extra.side == .buy { buys += extra.quantity } else { sells += extra.quantity }
        }
        return max(abs(q + buys), abs(q - sells))
    }

    // MARK: - Commands

    /// Validates and submits an order. Market and marketable limit orders
    /// execute immediately against `market`; others start working.
    @discardableResult
    public mutating func submit(_ request: OrderRequest, market: MarketView, quotes: [MarketSymbol: Quote]) -> OrderResult {
        let stamp = Stamp(sequence: market.sequence, time: market.time)
        lastStamp = stamp
        let spec = request.symbol.spec

        func reject(_ reason: String) -> OrderResult {
            let order = makeOrder(request, role: .entry, status: .rejected, stamp: stamp,
                                  limitTicks: request.limitPrice.flatMap { Self.safeTicks($0, spec) },
                                  stopTicks: request.stopPrice.flatMap { Self.safeTicks($0, spec) }, reason: reason)
            archive(order)
            log(.orderRejected, order, "\(describe(order)) rejected: \(reason)", stamp)
            revision += 1
            return OrderResult(order: order, fills: [])
        }

        if recentClientIDs.contains(request.clientOrderID) {
            return reject("Duplicate order (the same order was already submitted).")
        }
        remember(request.clientOrderID)

        if let problem = validate(request, market: market, quotes: quotes) { return reject(problem) }

        let limitTicks = request.limitPrice.flatMap { Self.safeTicks($0, spec) }
        let stopTicks = request.stopPrice.flatMap { Self.safeTicks($0, spec) }
        let order = makeOrder(request, role: .entry, status: .working, stamp: stamp,
                              limitTicks: limitTicks, stopTicks: stopTicks, reason: nil)
        openOrders.append(order)
        // Liquidity in this update may be consumed now; never process the
        // same update again for this market (no duplicate execution).
        lastProcessedSequence[request.symbol] = max(lastProcessedSequence[request.symbol] ?? Int.min, market.sequence)
        log(.orderAccepted, order, "\(describe(order)) accepted", stamp)

        // Bracket children wait (accepted) until the entry fills.
        if let bracket = request.bracket {
            let group = nextOCOGroup
            nextOCOGroup += 1
            if bracket.takeProfitTicks != nil {
                appendChild(of: order, role: .takeProfit, group: group, stamp: stamp)
            }
            if bracket.stopLossTicks != nil {
                appendChild(of: order, role: .stopLoss, group: group, stamp: stamp)
            }
        }

        var produced: [Fill] = []
        switch request.type {
        case .market:
            produced = executeTaker(orderID: order.id, market: market, limitTicks: nil)
            finishMarketOrder(orderID: order.id, stamp: stamp)
        case .limit:
            let marketable = request.side == .buy ? market.askTicks <= (limitTicks ?? 0) : market.bidTicks >= (limitTicks ?? .max)
            if marketable {
                produced = executeTaker(orderID: order.id, market: market, limitTicks: limitTicks)
            }
            if let current = openOrders.first(where: { $0.id == order.id }), current.status == .working {
                log(.orderWorking, current, "\(describe(current)) working", stamp)
            }
        case .stop:
            log(.orderWorking, order, "\(describe(order)) working", stamp)
        }

        revision += 1
        let stored = self.order(id: order.id) ?? order
        return OrderResult(order: stored, fills: produced)
    }

    /// Cancels an open order. Cancelling an entry also cancels its bracket
    /// orders that have not started working. Returns `false` if it was not open.
    @discardableResult
    public mutating func cancel(orderID: Int, at stamp: Stamp, reason: String = "Cancelled by user") -> Bool {
        guard openOrders.contains(where: { $0.id == orderID }) else { return false }
        lastStamp = stamp
        close(orderID: orderID, as: .cancelled, reason: reason, stamp: stamp)
        cancelPendingChildren(of: orderID, stamp: stamp)
        revision += 1
        return true
    }

    /// Cancels every open order, optionally for one market only.
    public mutating func cancelAll(symbol: MarketSymbol? = nil, at stamp: Stamp) {
        let ids = openOrders.filter { symbol == nil || $0.symbol == symbol }.map(\.id)
        for id in ids where openOrders.contains(where: { $0.id == id }) {
            close(orderID: id, as: .cancelled, reason: "Cancelled by user", stamp: stamp)
        }
        if !ids.isEmpty { revision += 1 }
    }

    /// Closes the whole position in `market.symbol` with a market order.
    @discardableResult
    public mutating func closePosition(market: MarketView) -> OrderResult? {
        guard let p = position(market.symbol) else { return nil }
        let stamp = Stamp(sequence: market.sequence, time: market.time)
        lastStamp = stamp
        let request = OrderRequest(clientOrderID: "close-\(nextOrderID)", symbol: market.symbol,
                                   side: p.isLong ? .sell : .buy, type: .market, quantity: abs(p.quantity))
        let order = makeOrder(request, role: .close, status: .working, stamp: stamp,
                              limitTicks: nil, stopTicks: nil, reason: nil)
        openOrders.append(order)
        log(.orderAccepted, order, "\(describe(order)) accepted", stamp)
        let produced = executeTaker(orderID: order.id, market: market, limitTicks: nil)
        finishMarketOrder(orderID: order.id, stamp: stamp)
        revision += 1
        return OrderResult(order: self.order(id: order.id) ?? order, fills: produced)
    }

    /// Attaches (or replaces) a stop-loss and/or take-profit to the open
    /// position in `market.symbol`, as reduce-only OCO orders sized to the
    /// current position. Passing `nil` for both removes the protection.
    ///
    /// The new prices are validated first. If either is invalid, both are
    /// rejected and the protection already working is kept, so a mistyped
    /// price never leaves the position unprotected.
    @discardableResult
    public mutating func setProtection(stopLoss: Double?, takeProfit: Double?, market: MarketView) -> [OrderResult] {
        let stamp = Stamp(sequence: market.sequence, time: market.time)
        lastStamp = stamp
        let symbol = market.symbol
        let spec = symbol.spec
        guard let p = position(symbol) else { return [] }
        let exitSide: OrderSide = p.isLong ? .sell : .buy

        func problem(_ role: OrderRole, _ price: Double) -> String? {
            guard let ticks = Self.safeTicks(price, spec), Self.isOnTick(price, spec) else {
                return "Price must be a multiple of the \(PriceFormat.price(spec.tickSize, decimals: spec.priceDecimals)) tick."
            }
            if role == .stopLoss {
                if exitSide == .sell, ticks >= market.bidTicks { return "A sell stop must be below the current bid." }
                if exitSide == .buy, ticks <= market.askTicks { return "A buy stop must be above the current ask." }
            } else {
                if exitSide == .sell, ticks <= market.bidTicks { return "A sell take-profit must be above the current bid." }
                if exitSide == .buy, ticks >= market.askTicks { return "A buy take-profit must be below the current ask." }
            }
            return nil
        }
        var requested: [(role: OrderRole, price: Double)] = []
        if let stopLoss { requested.append((.stopLoss, stopLoss)) }
        if let takeProfit { requested.append((.takeProfit, takeProfit)) }
        let problems = requested.map { problem($0.role, $0.price) }
        let allValid = problems.allSatisfy { $0 == nil }

        if allValid {
            // Replaces every active stop-loss and take-profit on the position,
            // including bracket orders already working. Bracket orders still
            // waiting for their entry to fill (`accepted`) are left alone.
            for o in openOrders where o.symbol == symbol && (o.role == .stopLoss || o.role == .takeProfit) && o.status != .accepted {
                close(orderID: o.id, as: .cancelled, reason: "Replaced by new protection", stamp: stamp)
            }
        }

        var results: [OrderResult] = []
        let group = nextOCOGroup
        nextOCOGroup += 1
        for (item, itemProblem) in zip(requested, problems) {
            let type: OrderType = item.role == .takeProfit ? .limit : .stop
            let request = OrderRequest(clientOrderID: "protect-\(nextOrderID)", symbol: symbol, side: exitSide,
                                       type: type, quantity: abs(p.quantity),
                                       limitPrice: type == .limit ? item.price : nil, stopPrice: type == .stop ? item.price : nil)
            let ticks = Self.safeTicks(item.price, spec) ?? 0
            let reason = itemProblem ?? (allValid ? nil : "Not placed because the other protective price was invalid.")
            let order = makeOrder(request, role: item.role, status: reason == nil ? .working : .rejected, stamp: stamp,
                                  limitTicks: type == .limit ? ticks : nil, stopTicks: type == .stop ? ticks : nil,
                                  reason: reason, ocoGroup: group)
            if let reason {
                archive(order)
                log(.orderRejected, order, "\(describe(order)) rejected: \(reason)", stamp)
            } else {
                openOrders.append(order)
                log(.orderWorking, order, "\(describe(order)) working", stamp)
            }
            results.append(OrderResult(order: order, fills: []))
        }
        revision += 1
        return results
    }

    /// Processes one market update: working limit and stop orders that the
    /// market reached are filled. Each update is processed at most once.
    @discardableResult
    public mutating func process(market: MarketView) -> [Fill] {
        let symbol = market.symbol
        guard market.sequence > (lastProcessedSequence[symbol] ?? Int.min) else { return [] }
        lastProcessedSequence[symbol] = market.sequence
        let stamp = Stamp(sequence: market.sequence, time: market.time)
        lastStamp = stamp

        var produced: [Fill] = []
        let candidates = openOrders.filter { $0.symbol == symbol && ($0.status == .working || $0.status == .partiallyFilled) }.map(\.id)
        for id in candidates {
            guard let order = openOrders.first(where: { $0.id == id }),
                  order.status == .working || order.status == .partiallyFilled else { continue }
            switch order.type {
            case .market:
                continue // market orders never rest
            case .limit:
                guard let limit = order.limitTicks else { continue }
                if order.side == .buy, market.askTicks <= limit {
                    let available = market.askTicks < limit ? order.remainingQuantity : (market.asks.first?.size ?? 0)
                    produced += executeMaker(orderID: id, quantity: available, priceTicks: limit, market: market)
                } else if order.side == .sell, market.bidTicks >= limit {
                    let available = market.bidTicks > limit ? order.remainingQuantity : (market.bids.first?.size ?? 0)
                    produced += executeMaker(orderID: id, quantity: available, priceTicks: limit, market: market)
                }
            case .stop:
                guard let stop = order.stopTicks else { continue }
                let triggered = order.side == .buy ? market.askTicks >= stop : market.bidTicks <= stop
                if triggered {
                    produced += executeTaker(orderID: id, market: market, limitTicks: nil)
                    finishMarketOrder(orderID: id, stamp: stamp)
                }
            }
        }
        if !produced.isEmpty { revision += 1 }
        return produced
    }

    /// Starts over with a fresh account. History is cleared.
    public mutating func reset(configuration newConfiguration: AccountConfiguration? = nil, at stamp: Stamp) {
        let resets = resetCount + 1
        let nextRevision = revision + 1
        self = TradingAccount(configuration: newConfiguration ?? configuration)
        resetCount = resets
        revision = nextRevision
        lastStamp = stamp
        log(.accountReset, nil, "Simulated account reset to \(PriceFormat.money(startingBalance, currency: "USD"))", stamp)
    }

    /// Changes costs, slippage and risk limits for future orders and fills.
    /// The starting balance takes effect at the next reset.
    /// Returns validation errors; nothing changes if there are any.
    @discardableResult
    public mutating func updateConfiguration(_ newConfiguration: AccountConfiguration, at stamp: Stamp) -> [String] {
        let errors = newConfiguration.validationErrors()
        guard errors.isEmpty else { return errors }
        configuration = newConfiguration
        lastStamp = stamp
        log(.configurationChanged, nil, "Account settings updated", stamp)
        revision += 1
        return []
    }

    // MARK: - Validation

    /// Whole ticks for a price, or `nil` for prices that are not finite,
    /// not positive or absurdly large (avoids integer-conversion traps).
    static func safeTicks(_ price: Double, _ spec: InstrumentSpec) -> Int64? {
        guard price.isFinite, price > 0, price < 1e9 else { return nil }
        return spec.ticks(price: price)
    }

    static func isOnTick(_ price: Double, _ spec: InstrumentSpec) -> Bool {
        guard let ticks = safeTicks(price, spec) else { return false }
        return abs(spec.price(ticks: ticks) - price) <= spec.tickSize * 1e-6
    }

    private func validate(_ request: OrderRequest, market: MarketView, quotes: [MarketSymbol: Quote]) -> String? {
        let spec = request.symbol.spec
        let tick = PriceFormat.price(spec.tickSize, decimals: spec.priceDecimals)
        guard request.symbol == market.symbol else { return "Market data does not match the order's instrument." }
        guard (1...configuration.risk.maxOrderQuantity).contains(request.quantity) else {
            return "Quantity must be between 1 and \(configuration.risk.maxOrderQuantity) contracts."
        }
        switch request.type {
        case .market:
            if request.limitPrice != nil || request.stopPrice != nil { return "Market orders take no limit or stop price." }
        case .limit:
            guard let price = request.limitPrice else { return "Enter a limit price." }
            guard Self.isOnTick(price, spec) else { return "Limit price must be a positive multiple of the \(tick) tick." }
        case .stop:
            guard let price = request.stopPrice else { return "Enter a stop price." }
            guard Self.isOnTick(price, spec), let ticks = Self.safeTicks(price, spec) else {
                return "Stop price must be a positive multiple of the \(tick) tick."
            }
            if request.side == .buy, ticks <= market.askTicks { return "A buy stop must be above the current ask (\(PriceFormat.price(market.ask, decimals: spec.priceDecimals)))." }
            if request.side == .sell, ticks >= market.bidTicks { return "A sell stop must be below the current bid (\(PriceFormat.price(market.bid, decimals: spec.priceDecimals)))." }
        }
        if let bracket = request.bracket {
            if bracket.takeProfitTicks == nil && bracket.stopLossTicks == nil { return "A bracket needs a take-profit or a stop-loss." }
            if let tp = bracket.takeProfitTicks, tp < 1 { return "Take-profit distance must be at least 1 tick." }
            if let sl = bracket.stopLossTicks, sl < 1 { return "Stop-loss distance must be at least 1 tick." }
        }
        let exposure = worstCaseExposure(request.symbol, adding: (request.side, request.quantity))
        if exposure > configuration.risk.maxPositionPerSymbol {
            return "This order could take the \(request.symbol.ticker) position to \(exposure) contracts; the limit is \(configuration.risk.maxPositionPerSymbol)."
        }
        if configuration.risk.enforceBuyingPower {
            let current = worstCaseExposure(request.symbol)
            let added = max(0, exposure - current)
            let required = Double(added) * configuration.costs(for: request.symbol).initialMarginPerContract
            if required > 0, required > buyingPower(quotes: quotes) {
                return "Insufficient simulated buying power: \(PriceFormat.money(required, currency: "USD")) margin required, \(PriceFormat.money(max(0, buyingPower(quotes: quotes)), currency: "USD")) available."
            }
        }
        return nil
    }

    // MARK: - Execution

    /// Takes liquidity from the opposite side of the book, best price first,
    /// up to `limitTicks` (marketable limits). Applies slippage. Returns the fill.
    private mutating func executeTaker(orderID: Int, market: MarketView, limitTicks: Int64?) -> [Fill] {
        guard let order = openOrders.first(where: { $0.id == orderID }) else { return [] }
        let wanted = allowedQuantity(order)
        guard wanted > 0 else {
            close(orderID: orderID, as: .cancelled, reason: "Position already closed", stamp: Stamp(sequence: market.sequence, time: market.time))
            return []
        }
        let levels = order.side == .buy ? market.asks : market.bids
        var remaining = wanted
        var notionalTicks = 0.0
        for level in levels where remaining > 0 {
            if let limitTicks {
                if order.side == .buy, level.priceTicks > limitTicks { break }
                if order.side == .sell, level.priceTicks < limitTicks { break }
            }
            let take = min(remaining, level.size)
            notionalTicks += Double(level.priceTicks) * Double(take)
            remaining -= take
        }
        let quantity = wanted - remaining
        guard quantity > 0 else { return [] }
        var priceTicks = notionalTicks / Double(quantity)
        priceTicks += Double(order.side.sign * configuration.slippageTicks)
        if let limitTicks {
            priceTicks = order.side == .buy ? min(priceTicks, Double(limitTicks)) : max(priceTicks, Double(limitTicks))
        }
        let fill = applyFill(orderID: orderID, quantity: quantity, price: market.spec.price(fractionalTicks: priceTicks),
                             liquidity: .taker, market: market)
        return [fill]
    }

    /// Fills a resting limit order at its own price.
    private mutating func executeMaker(orderID: Int, quantity: Int, priceTicks: Int64, market: MarketView) -> [Fill] {
        guard let order = openOrders.first(where: { $0.id == orderID }) else { return [] }
        let allowed = allowedQuantity(order)
        guard allowed > 0 else {
            close(orderID: orderID, as: .cancelled, reason: "Position already closed", stamp: Stamp(sequence: market.sequence, time: market.time))
            return []
        }
        let quantity = min(quantity, allowed)
        guard quantity > 0 else { return [] }
        return [applyFill(orderID: orderID, quantity: quantity, price: market.spec.price(ticks: priceTicks),
                          liquidity: .maker, market: market)]
    }

    /// Remaining quantity an order may fill now. Reduce-only orders are
    /// limited to the opposite position; an order may never overfill.
    private func allowedQuantity(_ order: Order) -> Int {
        guard order.role.isReduceOnly else { return order.remainingQuantity }
        guard let p = position(order.symbol), p.side != order.side else { return 0 }
        return min(order.remainingQuantity, abs(p.quantity))
    }

    /// Market orders and triggered stops never rest: any unfilled remainder
    /// (no visible liquidity) is cancelled.
    private mutating func finishMarketOrder(orderID: Int, stamp: Stamp) {
        guard let order = openOrders.first(where: { $0.id == orderID }) else { return }
        if order.remainingQuantity > 0 {
            close(orderID: orderID, as: .cancelled,
                  reason: order.filledQuantity > 0 ? "Remainder cancelled: not enough simulated liquidity" : "Not enough simulated liquidity",
                  stamp: stamp)
        }
    }

    @discardableResult
    private mutating func applyFill(orderID: Int, quantity: Int, price: Double, liquidity: Liquidity, market: MarketView) -> Fill {
        let stamp = Stamp(sequence: market.sequence, time: market.time)
        guard let index = openOrders.firstIndex(where: { $0.id == orderID }) else {
            preconditionFailure("applyFill on an order that is not open")
        }
        let order = openOrders[index]
        let symbol = order.symbol
        let spec = symbol.spec
        let costs = configuration.costs(for: symbol)
        let commission = Double(quantity) * costs.commissionPerContract
        let fees = Double(quantity) * costs.feesPerContract
        let realized = updatePosition(symbol: symbol, side: order.side, quantity: quantity, price: price,
                                      costs: commission + fees, pointValue: spec.pointValue, stamp: stamp)

        realizedPnL += realized
        commissionsPaid += commission
        feesPaid += fees

        var updated = order
        let previous = Double(updated.filledQuantity) * (updated.averageFillPrice ?? 0)
        updated.filledQuantity += quantity
        updated.averageFillPrice = (previous + price * Double(quantity)) / Double(updated.filledQuantity)
        updated.updatedSequence = stamp.sequence
        updated.updatedAt = stamp.time
        updated.status = updated.remainingQuantity == 0 ? .filled : .partiallyFilled
        openOrders[index] = updated

        let fill = Fill(id: nextFillID, orderID: orderID, symbol: symbol, side: order.side, quantity: quantity,
                        price: price, commission: commission, fees: fees, liquidity: liquidity,
                        realizedPnL: realized, sequence: stamp.sequence, time: stamp.time)
        nextFillID += 1
        fills.append(fill)
        if fills.count > Self.fillLimit { fills.removeFirst(fills.count - Self.fillLimit) }

        let priceText = PriceFormat.price(price, decimals: spec.priceDecimals + 1)
        if updated.status == .filled {
            log(.orderFilled, updated, "\(describe(updated)) filled at \(priceText)", stamp)
            openOrders.remove(at: index)
            archive(updated)
        } else {
            log(.orderPartiallyFilled, updated, "\(describe(updated)): \(quantity) filled at \(priceText), \(updated.remainingQuantity) remaining", stamp)
        }

        if updated.role == .entry { activateChildren(of: updated, stamp: stamp) }
        reconcileProtectiveOrders(symbol: symbol, filledOrder: updated, stamp: stamp)
        return fill
    }

    /// Updates the position and returns the gross P&L realised by this fill.
    private mutating func updatePosition(symbol: MarketSymbol, side: OrderSide, quantity: Int, price: Double,
                                         costs: Double, pointValue: Double, stamp: Stamp) -> Double {
        let signed = side.sign * quantity
        var p = positions[symbol] ?? Position(symbol: symbol, quantity: 0, averagePrice: 0, openCosts: 0,
                                              openedSequence: stamp.sequence, openedAt: stamp.time)
        if p.isFlat || (p.quantity > 0) == (signed > 0) {
            let total = abs(p.quantity) + quantity
            if p.isFlat {
                p.openedSequence = stamp.sequence
                p.openedAt = stamp.time
            }
            p.averagePrice = (p.averagePrice * Double(abs(p.quantity)) + price * Double(quantity)) / Double(total)
            p.quantity += signed
            p.openCosts += costs
            positions[symbol] = p
            return 0
        }

        let closing = min(abs(p.quantity), quantity)
        let direction = p.quantity > 0 ? 1.0 : -1.0
        let gross = direction * (price - p.averagePrice) * Double(closing) * pointValue
        let entryCosts = p.openCosts * Double(closing) / Double(abs(p.quantity))
        let exitCosts = costs * Double(closing) / Double(quantity)
        trades.append(TradeRecord(id: nextTradeID, symbol: symbol, direction: p.quantity > 0 ? .long : .short,
                                  quantity: closing, entryPrice: p.averagePrice, exitPrice: price,
                                  entryTime: p.openedAt, exitTime: stamp.time, grossPnL: gross,
                                  costs: entryCosts + exitCosts))
        nextTradeID += 1
        if trades.count > Self.tradeLimit { trades.removeFirst(trades.count - Self.tradeLimit) }

        let newQuantity = p.quantity + signed
        if newQuantity == 0 {
            positions[symbol] = nil
        } else if (newQuantity > 0) != (p.quantity > 0) {
            // Reversed: the remainder opens a new position at this price.
            let opened = quantity - closing
            positions[symbol] = Position(symbol: symbol, quantity: newQuantity, averagePrice: price,
                                         openCosts: costs * Double(opened) / Double(quantity),
                                         openedSequence: stamp.sequence, openedAt: stamp.time)
        } else {
            p.quantity = newQuantity
            p.openCosts -= entryCosts
            positions[symbol] = p
        }
        return gross
    }

    // MARK: - Brackets and OCO

    private mutating func appendChild(of parent: Order, role: OrderRole, group: Int, stamp: Stamp) {
        let request = OrderRequest(clientOrderID: "\(parent.clientOrderID)-\(role.rawValue)", symbol: parent.symbol,
                                   side: parent.side.opposite, type: role == .takeProfit ? .limit : .stop,
                                   quantity: parent.quantity)
        let child = makeOrder(request, role: role, status: .accepted, stamp: stamp, limitTicks: nil, stopTicks: nil,
                              reason: "Waits for the entry to fill", parentID: parent.id, ocoGroup: group)
        openOrders.append(child)
        log(.orderAccepted, child, "\(describe(child)) accepted, waiting for entry #\(parent.id)", stamp)
    }

    /// Sizes and prices bracket children from the entry's filled quantity and
    /// average fill price, and makes them work.
    private mutating func activateChildren(of entry: Order, stamp: Stamp) {
        guard let bracket = entry.bracket, let average = entry.averageFillPrice else { return }
        let spec = entry.symbol.spec
        let base = spec.ticks(price: average)
        let long = entry.side == .buy
        for i in openOrders.indices where openOrders[i].parentID == entry.id && openOrders[i].isOpen {
            var child = openOrders[i]
            child.quantity = child.filledQuantity + max(0, entry.filledQuantity - child.filledQuantity)
            if child.role == .takeProfit, let tp = bracket.takeProfitTicks {
                child.limitTicks = long ? base + Int64(tp) : base - Int64(tp)
            }
            if child.role == .stopLoss, let sl = bracket.stopLossTicks {
                child.stopTicks = long ? base - Int64(sl) : base + Int64(sl)
            }
            let wasAccepted = child.status == .accepted
            if wasAccepted { child.status = .working }
            child.statusReason = nil
            child.updatedSequence = stamp.sequence
            child.updatedAt = stamp.time
            openOrders[i] = child
            if wasAccepted { log(.orderWorking, child, "\(describe(child)) working", stamp) }
        }
    }

    /// After any fill: cancel the OCO siblings of a filled protective order,
    /// cancel protective orders whose position is gone, and shrink the rest
    /// to the open position.
    private mutating func reconcileProtectiveOrders(symbol: MarketSymbol, filledOrder: Order, stamp: Stamp) {
        if filledOrder.role.isReduceOnly, filledOrder.status == .filled, let group = filledOrder.ocoGroup {
            for o in openOrders where o.ocoGroup == group && o.id != filledOrder.id {
                close(orderID: o.id, as: .cancelled, reason: "OCO: \(filledOrder.role.label.lowercased()) filled", stamp: stamp)
            }
        }
        let p = position(symbol)
        for o in openOrders where o.symbol == symbol && o.role.isReduceOnly && o.status != .accepted && o.role != .close {
            guard let p, p.side != o.side else {
                close(orderID: o.id, as: .cancelled, reason: "Position closed", stamp: stamp)
                continue
            }
            if o.remainingQuantity > abs(p.quantity), let i = openOrders.firstIndex(where: { $0.id == o.id }) {
                openOrders[i].quantity = openOrders[i].filledQuantity + abs(p.quantity)
            }
        }
    }

    private mutating func cancelPendingChildren(of parentID: Int, stamp: Stamp) {
        for o in openOrders where o.parentID == parentID && o.status == .accepted {
            close(orderID: o.id, as: .cancelled, reason: "Entry cancelled before filling", stamp: stamp)
        }
    }

    // MARK: - Bookkeeping

    private mutating func makeOrder(_ request: OrderRequest, role: OrderRole, status: OrderStatus, stamp: Stamp,
                                    limitTicks: Int64?, stopTicks: Int64?, reason: String?,
                                    parentID: Int? = nil, ocoGroup: Int? = nil) -> Order {
        let order = Order(id: nextOrderID, clientOrderID: request.clientOrderID, symbol: request.symbol,
                          side: request.side, type: request.type, role: role, quantity: request.quantity,
                          limitTicks: limitTicks, stopTicks: stopTicks, parentID: parentID, ocoGroup: ocoGroup,
                          bracket: role == .entry ? request.bracket : nil, status: status, statusReason: reason,
                          createdSequence: stamp.sequence, createdAt: stamp.time,
                          updatedSequence: stamp.sequence, updatedAt: stamp.time)
        nextOrderID += 1
        return order
    }

    /// Moves an open order to a final state.
    private mutating func close(orderID: Int, as status: OrderStatus, reason: String?, stamp: Stamp) {
        guard let index = openOrders.firstIndex(where: { $0.id == orderID }) else { return }
        var order = openOrders.remove(at: index)
        order.status = status
        order.statusReason = reason
        order.updatedSequence = stamp.sequence
        order.updatedAt = stamp.time
        archive(order)
        log(status == .rejected ? .orderRejected : .orderCancelled, order,
            "\(describe(order)) cancelled\(reason.map { ": \($0)" } ?? "")", stamp)
    }

    private mutating func archive(_ order: Order) {
        orderHistory.append(order)
        if orderHistory.count > Self.orderHistoryLimit { orderHistory.removeFirst(orderHistory.count - Self.orderHistoryLimit) }
    }

    private mutating func remember(_ clientOrderID: String) {
        recentClientIDs.append(clientOrderID)
        if recentClientIDs.count > Self.clientIDMemory { recentClientIDs.removeFirst(recentClientIDs.count - Self.clientIDMemory) }
    }

    private mutating func log(_ kind: AccountEvent.Kind, _ order: Order?, _ message: String, _ stamp: Stamp) {
        events.append(AccountEvent(id: nextEventID, kind: kind, orderID: order?.id, symbol: order?.symbol,
                                   message: message, sequence: stamp.sequence, time: stamp.time))
        nextEventID += 1
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
    }

    /// Short human description, e.g. "#12 Buy 2 GC limit 2,655.10".
    public func describe(_ order: Order) -> String {
        let spec = order.symbol.spec
        var text = "#\(order.id) \(order.side.label) \(order.quantity) \(order.symbol.ticker) \(order.role == .entry ? order.type.rawValue : order.role.label.lowercased())"
        if let l = order.limitTicks { text += " \(PriceFormat.price(spec.price(ticks: l), decimals: spec.priceDecimals))" }
        if let s = order.stopTicks { text += " stop \(PriceFormat.price(spec.price(ticks: s), decimals: spec.priceDecimals))" }
        return text
    }
}

