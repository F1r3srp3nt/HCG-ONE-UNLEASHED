import Foundation
import HCGDomain

// A basic simulated broker for M1. Inspired by HCG-One@b4f0e29
// TradingLab/SimBroker.swift, rewritten so fills are deterministic (no
// `Int.random` slippage) and priced by walking the simulated book.

public enum OrderSide: String, Codable, Sendable, CaseIterable, Identifiable {
    case buy, sell

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// A simulated market order. M1 supports market orders only.
public struct MarketOrder: Sendable, Equatable {
    public let symbol: MarketSymbol
    public let side: OrderSide
    public let quantity: Int

    public init(symbol: MarketSymbol, side: OrderSide, quantity: Int) {
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
    }

    public static let maximumQuantity = 100
}

public enum OrderRejection: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidQuantity
    case insufficientLiquidity
    case noOpenPosition

    public var description: String {
        switch self {
        case .invalidQuantity: "Quantity must be between 1 and \(MarketOrder.maximumQuantity) contracts."
        case .insufficientLiquidity: "Not enough simulated liquidity in the visible book for this size."
        case .noOpenPosition: "There is no open simulated position to close."
        }
    }
}

/// A completed simulated fill.
public struct Fill: Sendable, Equatable, Identifiable {
    public let id: Int
    public let frameSequence: Int
    public let symbol: MarketSymbol
    public let side: OrderSide
    public let quantity: Int
    /// Volume-weighted price across the book levels the order consumed.
    public let averagePrice: Double
    public let commission: Double
    /// P&L realised by this fill (before commission).
    public let realizedPnL: Double
}

/// One aggregated position per market. Quantity is signed: + long, − short.
public struct Position: Sendable, Equatable {
    public internal(set) var quantity: Int
    public internal(set) var averagePrice: Double

    public var isLong: Bool { quantity > 0 }
    public var isFlat: Bool { quantity == 0 }
}

/// The simulated account. Fully isolated from any real account: nothing here
/// is ever routed to an exchange, broker or HCG service.
///
/// M1 model: market orders fill against the current simulated book (walking
/// levels best-first) without consuming that liquidity, so a user's orders do
/// not change the simulated market. Cash = starting balance + realised P&L −
/// commissions. Open positions are marked at the liquidation side (bid for
/// longs, ask for shorts).
public struct SimulatedAccount: Sendable, Equatable {
    public let startingBalance: Double
    public private(set) var realizedPnL = 0.0
    public private(set) var commissionsPaid = 0.0
    public private(set) var positions: [MarketSymbol: Position] = [:]
    public private(set) var fills: [Fill] = []
    private var fillCounter = 0

    static let fillHistoryLimit = 200

    public init(startingBalance: Double = 50_000) {
        self.startingBalance = startingBalance
    }

    public var cash: Double { startingBalance + realizedPnL - commissionsPaid }

    public func position(_ symbol: MarketSymbol) -> Position? {
        guard let p = positions[symbol], !p.isFlat else { return nil }
        return p
    }

    /// Unrealised P&L of the open position in `snapshot.symbol`.
    public func unrealizedPnL(_ snapshot: MarketSnapshot) -> Double {
        guard let p = position(snapshot.symbol) else { return 0 }
        let mark = p.isLong ? snapshot.bid : snapshot.ask
        return Double(p.quantity) * (mark - p.averagePrice) * snapshot.spec.pointValue
    }

    public func equity(_ snapshots: [MarketSymbol: MarketSnapshot]) -> Double {
        cash + positions.keys.reduce(0) { sum, symbol in
            guard let snap = snapshots[symbol] else { return sum }
            return sum + unrealizedPnL(snap)
        }
    }

    /// Executes a market order against `snapshot`'s book.
    @discardableResult
    public mutating func execute(_ order: MarketOrder, against snapshot: MarketSnapshot,
                                 commissionPerContract: Double) throws(OrderRejection) -> Fill {
        guard (1...MarketOrder.maximumQuantity).contains(order.quantity) else { throw .invalidQuantity }
        let levels = order.side == .buy ? snapshot.asks : snapshot.bids

        var remaining = order.quantity
        var notionalTicks = 0.0
        for level in levels where remaining > 0 {
            let take = min(remaining, level.size)
            notionalTicks += Double(level.priceTicks) * Double(take)
            remaining -= take
        }
        guard remaining == 0 else { throw .insufficientLiquidity }
        let price = notionalTicks / Double(order.quantity) * snapshot.spec.tickSize

        let realized = apply(order, price: price, pointValue: snapshot.spec.pointValue)
        let commission = Double(order.quantity) * commissionPerContract
        realizedPnL += realized
        commissionsPaid += commission

        let fill = Fill(id: fillCounter, frameSequence: snapshot.frameSequence, symbol: order.symbol,
                        side: order.side, quantity: order.quantity, averagePrice: price,
                        commission: commission, realizedPnL: realized)
        fillCounter += 1
        fills.append(fill)
        if fills.count > Self.fillHistoryLimit { fills.removeFirst(fills.count - Self.fillHistoryLimit) }
        return fill
    }

    /// Closes the whole position in `snapshot.symbol` with a market order.
    @discardableResult
    public mutating func flatten(against snapshot: MarketSnapshot, commissionPerContract: Double) throws(OrderRejection) -> Fill {
        guard let p = position(snapshot.symbol) else { throw .noOpenPosition }
        let order = MarketOrder(symbol: snapshot.symbol, side: p.isLong ? .sell : .buy, quantity: abs(p.quantity))
        return try execute(order, against: snapshot, commissionPerContract: commissionPerContract)
    }

    /// Updates the position and returns the P&L realised by this fill.
    private mutating func apply(_ order: MarketOrder, price: Double, pointValue: Double) -> Double {
        let signed = order.side == .buy ? order.quantity : -order.quantity
        var p = positions[order.symbol] ?? Position(quantity: 0, averagePrice: 0)
        var realized = 0.0

        if p.isFlat || (p.quantity > 0) == (signed > 0) {
            // Opening or adding: volume-weighted average entry.
            let total = abs(p.quantity) + order.quantity
            p.averagePrice = (p.averagePrice * Double(abs(p.quantity)) + price * Double(order.quantity)) / Double(total)
            p.quantity += signed
        } else {
            // Reducing, closing or reversing.
            let closing = min(abs(p.quantity), order.quantity)
            let direction = p.quantity > 0 ? 1.0 : -1.0
            realized = direction * (price - p.averagePrice) * Double(closing) * pointValue
            let newQuantity = p.quantity + signed
            if newQuantity == 0 {
                p = Position(quantity: 0, averagePrice: 0)
            } else if (newQuantity > 0) != (p.quantity > 0) {
                // Reversed: the remainder opens at this fill's price.
                p = Position(quantity: newQuantity, averagePrice: price)
            } else {
                p.quantity = newQuantity
            }
        }
        positions[order.symbol] = p.isFlat ? nil : p
        return realized
    }
}
