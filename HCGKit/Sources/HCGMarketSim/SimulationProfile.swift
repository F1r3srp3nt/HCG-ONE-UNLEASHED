import Foundation
import HCGDomain

/// Per-instrument parameters of the simulated market model.
///
/// These are simulation settings, not real market statistics. Session start
/// prices, resting sizes and commissions come from HCG ONE's Trading Lab; the
/// spread parameters are new in UNLEASHED (see docs/M1_IMPLEMENTATION_REPORT.md).
public struct SimulationProfile: Sendable, Hashable, Codable {
    public let symbol: MarketSymbol
    /// Price the simulated session opens at.
    public let sessionStartPrice: Double
    /// Inside spread in a calm market, in ticks. Never below 1.
    public let baseSpreadTicks: Int
    /// Maximum additional widening during stress (liquidity pulls, volatility bursts).
    public let maxExtraSpreadTicks: Int
    /// Multiplier for how readily the spread widens under elevated volatility.
    public let spreadSensitivity: Double
    /// Price levels kept on each side of the book.
    public let bookDepth: Int
    /// Range of resting size (contracts) for a freshly placed level.
    public let restingSize: ClosedRange<Int>
    /// Simulated commission per contract per fill.
    public let commissionPerContract: Double
    /// Market updates per price bar.
    public let updatesPerBar: Int

    public init(symbol: MarketSymbol, sessionStartPrice: Double, baseSpreadTicks: Int,
                maxExtraSpreadTicks: Int, spreadSensitivity: Double, bookDepth: Int,
                restingSize: ClosedRange<Int>, commissionPerContract: Double, updatesPerBar: Int) {
        self.symbol = symbol
        self.sessionStartPrice = sessionStartPrice
        self.baseSpreadTicks = max(1, baseSpreadTicks)
        self.maxExtraSpreadTicks = max(0, maxExtraSpreadTicks)
        self.spreadSensitivity = max(0, spreadSensitivity)
        self.bookDepth = max(4, bookDepth)
        self.restingSize = max(1, restingSize.lowerBound)...max(1, restingSize.upperBound)
        self.commissionPerContract = max(0, commissionPerContract)
        self.updatesPerBar = max(1, updatesPerBar)
    }

    /// Widest spread the model can produce, in ticks.
    public var maxSpreadTicks: Int { baseSpreadTicks + maxExtraSpreadTicks }

    public static func standard(for symbol: MarketSymbol) -> SimulationProfile {
        switch symbol {
        case .gc:
            SimulationProfile(symbol: .gc, sessionStartPrice: 2_655.0, baseSpreadTicks: 1,
                              maxExtraSpreadTicks: 6, spreadSensitivity: 1.0, bookDepth: 22,
                              restingSize: 35...260, commissionPerContract: 2.50, updatesPerBar: 10)
        case .nq:
            SimulationProfile(symbol: .nq, sessionStartPrice: 19_850.0, baseSpreadTicks: 1,
                              maxExtraSpreadTicks: 6, spreadSensitivity: 1.2, bookDepth: 22,
                              restingSize: 35...260, commissionPerContract: 2.00, updatesPerBar: 10)
        case .es:
            SimulationProfile(symbol: .es, sessionStartPrice: 5_480.0, baseSpreadTicks: 1,
                              maxExtraSpreadTicks: 4, spreadSensitivity: 0.6, bookDepth: 22,
                              restingSize: 35...260, commissionPerContract: 2.00, updatesPerBar: 10)
        case .cl:
            SimulationProfile(symbol: .cl, sessionStartPrice: 77.40, baseSpreadTicks: 1,
                              maxExtraSpreadTicks: 8, spreadSensitivity: 1.3, bookDepth: 22,
                              restingSize: 35...260, commissionPerContract: 2.50, updatesPerBar: 10)
        }
    }
}
