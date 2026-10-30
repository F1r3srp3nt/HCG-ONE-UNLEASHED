import Foundation

// Ported from HCG-One@b4f0e29: ios-hcg/HCGONE/Models/InstrumentSpec.swift and
// ios-hcg/HCGONE/TradingLab/LabInstruments.swift. Narrowed to the four
// simulated futures markets; prices are handled in whole ticks.

/// The four simulated futures markets of HCG ONE UNLEASHED.
///
/// These are contract specifications only. All market activity in the app is
/// simulated — no exchange, broker or live market feed is involved.
public enum MarketSymbol: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable, Comparable {
    case gc, nq, es, cl

    public var id: String { rawValue }

    /// Upper-case ticker as traders write it ("GC").
    public var ticker: String { rawValue.uppercased() }

    public var spec: InstrumentSpec { InstrumentSpec.spec(for: self) }

    public static func < (lhs: MarketSymbol, rhs: MarketSymbol) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .gc: 0
        case .nq: 1
        case .es: 2
        case .cl: 3
        }
    }
}

/// Contract specification used to convert price movement into money.
public struct InstrumentSpec: Codable, Hashable, Sendable {
    public let symbol: MarketSymbol
    public let name: String
    public let venue: String
    /// Currency the P&L is denominated in.
    public let currency: String
    /// Money value of a 1.0 price move for one contract.
    public let pointValue: Double
    /// Minimum price increment.
    public let tickSize: Double
    public let unitLabel: String

    /// Money value of one tick for one contract.
    public var tickValue: Double { pointValue * tickSize }

    /// Decimals used to display prices (at least two, as in HCG ONE).
    public var priceDecimals: Int {
        guard tickSize > 0, tickSize.isFinite else { return 2 }
        let needed = Int((-log10(tickSize) - 1e-9).rounded(.up))
        return max(2, needed)
    }

    /// Ticks per 1.0 of price (10 for GC, 4 for NQ/ES, 100 for CL) when the
    /// tick size divides 1.0 exactly; otherwise `nil`.
    private var ticksPerUnit: Double? {
        guard tickSize > 0, tickSize.isFinite else { return nil }
        let inverse = (1 / tickSize).rounded()
        return abs(inverse * tickSize - 1) < 1e-12 ? inverse : nil
    }

    /// Price of a whole number of ticks, as the closest `Double` to the exact
    /// decimal value (26_527 GC ticks → 2652.7, not 2652.7000000000003).
    public func price(ticks: Int64) -> Double {
        if let perUnit = ticksPerUnit { return Double(ticks) / perUnit }
        return Double(ticks) * tickSize
    }

    /// Price of a fractional number of ticks (e.g. a volume-weighted fill).
    public func price(fractionalTicks: Double) -> Double {
        if let perUnit = ticksPerUnit { return fractionalTicks / perUnit }
        return fractionalTicks * tickSize
    }

    /// Nearest whole number of ticks for a price.
    public func ticks(price: Double) -> Int64 {
        if let perUnit = ticksPerUnit { return Int64((price * perUnit).rounded()) }
        return Int64((price / tickSize).rounded())
    }

    /// `price` rounded to the nearest valid tick.
    public func roundedToTick(_ price: Double) -> Double {
        self.price(ticks: ticks(price: price))
    }

    public static func spec(for symbol: MarketSymbol) -> InstrumentSpec {
        switch symbol {
        case .gc:
            InstrumentSpec(symbol: .gc, name: "Gold Futures", venue: "COMEX", currency: "USD",
                           pointValue: 100, tickSize: 0.10, unitLabel: "contract")
        case .nq:
            InstrumentSpec(symbol: .nq, name: "E-mini Nasdaq-100", venue: "CME", currency: "USD",
                           pointValue: 20, tickSize: 0.25, unitLabel: "contract")
        case .es:
            InstrumentSpec(symbol: .es, name: "E-mini S&P 500", venue: "CME", currency: "USD",
                           pointValue: 50, tickSize: 0.25, unitLabel: "contract")
        case .cl:
            InstrumentSpec(symbol: .cl, name: "WTI Crude Oil Futures", venue: "NYMEX", currency: "USD",
                           pointValue: 1_000, tickSize: 0.01, unitLabel: "contract")
        }
    }

    /// Short educational description, carried over from HCG ONE.
    public var summary: String {
        switch symbol {
        case .gc: "COMEX gold. $10 per 0.10 tick — a classic battleground for absorption and sweeps."
        case .nq: "E-mini Nasdaq-100. $5 per 0.25 tick — fast, momentum-heavy index order flow."
        case .es: "E-mini S&P 500. $12.50 per 0.25 tick — the deepest liquidity in index futures."
        case .cl: "NYMEX WTI crude. $10 per 0.01 tick — violent news-driven volatility."
        }
    }
}
