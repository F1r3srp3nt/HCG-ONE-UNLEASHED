import Foundation
import HCGDomain

/// Per-instrument cost and margin assumptions of the simulated account.
///
/// These are **simulation settings chosen for HCG ONE UNLEASHED**. They do not
/// reproduce any broker's or exchange's actual commissions, fees or margin.
public struct InstrumentCosts: Codable, Hashable, Sendable {
    /// Commission per contract per fill (each side of a round trip).
    public var commissionPerContract: Double
    /// Exchange/clearing-style fees per contract per fill.
    public var feesPerContract: Double
    /// Margin set aside per open (or potentially open) contract.
    public var initialMarginPerContract: Double

    public init(commissionPerContract: Double, feesPerContract: Double, initialMarginPerContract: Double) {
        self.commissionPerContract = commissionPerContract
        self.feesPerContract = feesPerContract
        self.initialMarginPerContract = initialMarginPerContract
    }
}

/// Simulated risk controls.
public struct RiskLimits: Codable, Hashable, Sendable {
    /// Largest quantity a single order may have.
    public var maxOrderQuantity: Int
    /// Largest position (contracts, either direction) per market, counting
    /// working orders that could add to it.
    public var maxPositionPerSymbol: Int
    /// Reject orders whose worst-case margin exceeds the available buying power.
    public var enforceBuyingPower: Bool

    public init(maxOrderQuantity: Int = 100, maxPositionPerSymbol: Int = 50, enforceBuyingPower: Bool = true) {
        self.maxOrderQuantity = maxOrderQuantity
        self.maxPositionPerSymbol = maxPositionPerSymbol
        self.enforceBuyingPower = enforceBuyingPower
    }
}

/// Configuration of the simulated paper-trading account.
public struct AccountConfiguration: Codable, Hashable, Sendable {
    /// Balance the account starts (and resets) with, in USD.
    public var startingBalance: Double
    public var costs: [MarketSymbol: InstrumentCosts]
    /// Extra adverse ticks applied to every taker fill (market orders,
    /// triggered stops, marketable limits), on top of walking the book.
    public var slippageTicks: Int
    public var risk: RiskLimits

    public init(startingBalance: Double, costs: [MarketSymbol: InstrumentCosts], slippageTicks: Int, risk: RiskLimits) {
        self.startingBalance = startingBalance
        self.costs = costs
        self.slippageTicks = max(0, slippageTicks)
        self.risk = risk
    }

    public func costs(for symbol: MarketSymbol) -> InstrumentCosts {
        costs[symbol] ?? Self.standard.costs[symbol] ?? InstrumentCosts(commissionPerContract: 0, feesPerContract: 0, initialMarginPerContract: 0)
    }

    /// Defaults. Commissions match HCG ONE's Trading Lab; margins are round,
    /// clearly simulated figures.
    public static let standard = AccountConfiguration(
        startingBalance: 50_000,
        costs: [
            .gc: InstrumentCosts(commissionPerContract: 2.50, feesPerContract: 0, initialMarginPerContract: 10_000),
            .nq: InstrumentCosts(commissionPerContract: 2.00, feesPerContract: 0, initialMarginPerContract: 20_000),
            .es: InstrumentCosts(commissionPerContract: 2.00, feesPerContract: 0, initialMarginPerContract: 15_000),
            .cl: InstrumentCosts(commissionPerContract: 2.50, feesPerContract: 0, initialMarginPerContract: 6_000),
        ],
        slippageTicks: 0,
        risk: RiskLimits())

    /// Problems that make the configuration unusable; empty when valid.
    public func validationErrors() -> [String] {
        var errors: [String] = []
        if !(startingBalance.isFinite && startingBalance > 0) { errors.append("Starting balance must be greater than zero.") }
        if risk.maxOrderQuantity < 1 { errors.append("Maximum order quantity must be at least 1.") }
        if risk.maxPositionPerSymbol < 1 { errors.append("Maximum position must be at least 1 contract.") }
        for symbol in MarketSymbol.allCases {
            let c = costs(for: symbol)
            if !(c.commissionPerContract >= 0 && c.feesPerContract >= 0 && c.initialMarginPerContract >= 0)
                || ![c.commissionPerContract, c.feesPerContract, c.initialMarginPerContract].allSatisfy(\.isFinite) {
                errors.append("\(symbol.ticker) costs and margin must be zero or positive.")
            }
        }
        return errors
    }
}
