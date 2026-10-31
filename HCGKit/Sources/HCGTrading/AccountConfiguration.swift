import Foundation
import HCGDomain

/// Per-instrument cost and margin assumptions of the simulated account.
///
/// These are **simulation settings chosen for HCG ONE: UNLEASHED**. They do not
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
    /// Daily loss limit in USD, measured on equity (realized and unrealized)
    /// since the session began. Reaching it closes everything and locks
    /// trading until the next session. `nil` = off.
    public var dailyLossLimit: Double?
    /// Trailing maximum drawdown in USD below the equity high. The floor
    /// stops trailing once it reaches the starting balance. Reaching it closes
    /// everything and locks trading until the account is reset. `nil` = off.
    public var trailingDrawdown: Double?
    /// Close every position when equity falls below the margin the open
    /// positions require.
    public var liquidateOnMarginShortfall: Bool

    public init(maxOrderQuantity: Int = 100, maxPositionPerSymbol: Int = 50, enforceBuyingPower: Bool = true,
                dailyLossLimit: Double? = nil, trailingDrawdown: Double? = nil,
                liquidateOnMarginShortfall: Bool = false) {
        self.maxOrderQuantity = maxOrderQuantity
        self.maxPositionPerSymbol = maxPositionPerSymbol
        self.enforceBuyingPower = enforceBuyingPower
        self.dailyLossLimit = dailyLossLimit
        self.trailingDrawdown = trailingDrawdown
        self.liquidateOnMarginShortfall = liquidateOnMarginShortfall
    }

    // Sessions saved before the risk rules existed decode with the rules off.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxOrderQuantity = try c.decode(Int.self, forKey: .maxOrderQuantity)
        maxPositionPerSymbol = try c.decode(Int.self, forKey: .maxPositionPerSymbol)
        enforceBuyingPower = try c.decode(Bool.self, forKey: .enforceBuyingPower)
        dailyLossLimit = try c.decodeIfPresent(Double.self, forKey: .dailyLossLimit)
        trailingDrawdown = try c.decodeIfPresent(Double.self, forKey: .trailingDrawdown)
        liquidateOnMarginShortfall = try c.decodeIfPresent(Bool.self, forKey: .liquidateOnMarginShortfall) ?? false
    }

    /// An evaluation-style $50,000 account: 5 contracts, $1,000 daily loss
    /// limit, $2,000 trailing drawdown, liquidation below margin.
    public static let evaluation = RiskLimits(maxOrderQuantity: 5, maxPositionPerSymbol: 5, enforceBuyingPower: true,
                                              dailyLossLimit: 1_000, trailingDrawdown: 2_000,
                                              liquidateOnMarginShortfall: true)
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

    /// Defaults: a $50,000 evaluation-style account, the setup most
    /// futures traders practise order flow on (founder decision 2026-10-31,
    /// D-32 / D-35). Commissions match HCG ONE's Trading Lab. Margins are
    /// typical **intraday** levels, not exchange overnight margins. All values
    /// are simulated and editable.
    public static let standard = AccountConfiguration(
        startingBalance: 50_000,
        costs: [
            .gc: InstrumentCosts(commissionPerContract: 2.50, feesPerContract: 0, initialMarginPerContract: 1_000),
            .nq: InstrumentCosts(commissionPerContract: 2.00, feesPerContract: 0, initialMarginPerContract: 1_000),
            .es: InstrumentCosts(commissionPerContract: 2.00, feesPerContract: 0, initialMarginPerContract: 500),
            .cl: InstrumentCosts(commissionPerContract: 2.50, feesPerContract: 0, initialMarginPerContract: 1_000),
        ],
        slippageTicks: 0,
        risk: .evaluation)

    /// Problems that make the configuration unusable; empty when valid.
    public func validationErrors() -> [String] {
        var errors: [String] = []
        if !(startingBalance.isFinite && startingBalance > 0) { errors.append("Starting balance must be greater than zero.") }
        if risk.maxOrderQuantity < 1 { errors.append("Maximum order quantity must be at least 1.") }
        if risk.maxPositionPerSymbol < 1 { errors.append("Maximum position must be at least 1 contract.") }
        if let limit = risk.dailyLossLimit, !(limit.isFinite && limit > 0) { errors.append("The daily loss limit must be greater than zero.") }
        if let drawdown = risk.trailingDrawdown, !(drawdown.isFinite && drawdown > 0) { errors.append("The trailing drawdown must be greater than zero.") }
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
