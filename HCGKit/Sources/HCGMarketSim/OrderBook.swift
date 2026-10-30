import Foundation

/// Resting liquidity at one price level of the simulated book.
public struct BookLevel: Hashable, Sendable, Identifiable, Codable {
    /// Price in whole ticks (price = priceTicks × tickSize).
    public let priceTicks: Int64
    /// Contracts resting at this level.
    public var size: Int

    public var id: Int64 { priceTicks }

    public init(priceTicks: Int64, size: Int) {
        self.priceTicks = priceTicks
        self.size = size
    }
}

public enum BookSide: String, Codable, Sendable, Hashable {
    case bid, offer
}

/// The simulated order book.
///
/// Invariants (checked by `violations()` and the test suite):
/// - both sides hold exactly `depth` levels, every level with size ≥ 1;
/// - bids are best-first and strictly descending one tick apart;
/// - asks are best-first and strictly ascending one tick apart;
/// - best bid < best ask, and spread = best ask − best bid ≥ 1 tick.
///
/// This replaces HCG ONE's `advancePrice` book shift, which removed the best
/// levels and appended new ones next to the worst, so every price move
/// widened the spread (docs/IOS_COMPATIBILITY.md §5.1).
struct OrderBook: Sendable, Equatable, Codable {
    private(set) var bids: [BookLevel]
    private(set) var asks: [BookLevel]
    let depth: Int

    var bestBid: Int64 { bids[0].priceTicks }
    var bestAsk: Int64 { asks[0].priceTicks }
    var spreadTicks: Int { Int(bestAsk - bestBid) }

    /// Lowest best bid that keeps every bid level at a positive price.
    var minimumBestBid: Int64 { Int64(depth) }

    init(bestBid: Int64, spreadTicks: Int, depth: Int, restingSize: ClosedRange<Int>, rng: inout SeededRNG) {
        self.depth = depth
        self.bids = []
        self.asks = []
        reprice(bestBid: bestBid, spreadTicks: spreadTicks, restingSize: restingSize, rng: &rng)
    }

    /// Re-centres the book on a new best bid and spread. Levels whose price
    /// stays on the same side keep their resting size; prices that are new to
    /// a side (including former levels of the opposite side) receive fresh size.
    mutating func reprice(bestBid requestedBid: Int64, spreadTicks requestedSpread: Int,
                          restingSize: ClosedRange<Int>, rng: inout SeededRNG) {
        let spread = Int64(max(1, requestedSpread))
        let bestBid = max(minimumBestBid, requestedBid)
        let bestAsk = bestBid + spread

        var oldBids: [Int64: Int] = [:]
        for level in bids { oldBids[level.priceTicks] = level.size }
        var oldAsks: [Int64: Int] = [:]
        for level in asks { oldAsks[level.priceTicks] = level.size }

        var newBids: [BookLevel] = []
        newBids.reserveCapacity(depth)
        for i in 0..<depth {
            let price = bestBid - Int64(i)
            newBids.append(BookLevel(priceTicks: price, size: Self.carried(oldBids[price]) ?? rng.range(restingSize)))
        }
        var newAsks: [BookLevel] = []
        newAsks.reserveCapacity(depth)
        for i in 0..<depth {
            let price = bestAsk + Int64(i)
            newAsks.append(BookLevel(priceTicks: price, size: Self.carried(oldAsks[price]) ?? rng.range(restingSize)))
        }
        bids = newBids
        asks = newAsks
    }

    /// Resting size carried over to the repriced book; a depleted level
    /// (size 0) is treated as gone and receives fresh size.
    private static func carried(_ size: Int?) -> Int? {
        guard let size, size > 0 else { return nil }
        return size
    }

    /// Moves the whole quote by `ticks`, keeping the spread.
    mutating func shift(by ticks: Int, restingSize: ClosedRange<Int>, rng: inout SeededRNG) {
        guard ticks != 0 else { return }
        reprice(bestBid: bestBid + Int64(ticks), spreadTicks: spreadTicks, restingSize: restingSize, rng: &rng)
    }

    /// Consumes up to `size` contracts at the best level of `side`.
    /// Returns `true` when the level was fully depleted.
    mutating func consumeBest(_ side: BookSide, size: Int) -> Bool {
        switch side {
        case .bid:
            bids[0].size -= min(bids[0].size, size)
            return bids[0].size == 0
        case .offer:
            asks[0].size -= min(asks[0].size, size)
            return asks[0].size == 0
        }
    }

    /// Sets the resting size `levelsFromBest` levels into one side.
    mutating func setSize(_ size: Int, side: BookSide, levelsFromBest index: Int) {
        guard index >= 0, index < depth else { return }
        switch side {
        case .bid: bids[index].size = max(1, size)
        case .offer: asks[index].size = max(1, size)
        }
    }

    /// Divides every resting size on one side (liquidity pulled), keeping ≥ 1.
    mutating func thin(_ side: BookSide, divisor: Int) {
        let d = max(1, divisor)
        switch side {
        case .bid: for i in bids.indices { bids[i].size = max(1, bids[i].size / d) }
        case .offer: for i in asks.indices { asks[i].size = max(1, asks[i].size / d) }
        }
    }

    /// Refills levels that dropped below a third of the typical size.
    mutating func replenish(typicalSize: Int, rate: Double) {
        let threshold = max(1, typicalSize / 3)
        let refill = max(1, Int(Double(typicalSize) * min(max(rate, 0), 1)))
        for i in bids.indices where bids[i].size < threshold { bids[i].size += refill }
        for i in asks.indices where asks[i].size < threshold { asks[i].size += refill }
    }

    /// Every invariant violation (empty when the book is valid).
    func violations() -> [String] {
        var problems: [String] = []
        if bids.count != depth { problems.append("bid depth \(bids.count) ≠ \(depth)") }
        if asks.count != depth { problems.append("ask depth \(asks.count) ≠ \(depth)") }
        guard let bid = bids.first, let ask = asks.first else {
            problems.append("empty side")
            return problems
        }
        if bid.priceTicks >= ask.priceTicks { problems.append("crossed book: bid \(bid.priceTicks) ≥ ask \(ask.priceTicks)") }
        for i in 1..<bids.count where bids[i].priceTicks != bids[i - 1].priceTicks - 1 {
            problems.append("bids not contiguous/descending at \(i)")
        }
        for i in 1..<asks.count where asks[i].priceTicks != asks[i - 1].priceTicks + 1 {
            problems.append("asks not contiguous/ascending at \(i)")
        }
        if bids.contains(where: { $0.size < 1 }) { problems.append("bid level with size < 1") }
        if asks.contains(where: { $0.size < 1 }) { problems.append("ask level with size < 1") }
        if bids.contains(where: { $0.priceTicks <= 0 }) { problems.append("non-positive bid price") }
        return problems
    }
}
