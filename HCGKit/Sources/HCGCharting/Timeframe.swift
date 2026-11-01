import Foundation

// Charting for HCG ONE: UNLEASHED. Candles are built from timestamped trade
// events, never from other candles, so every timeframe agrees with the tape.
// All data is simulated.

/// Chart timeframes, 1 minute to 1 day.
public enum Timeframe: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case m1, m5, m15, h1, h4, d1

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .m1: "1m"
        case .m5: "5m"
        case .m15: "15m"
        case .h1: "1h"
        case .h4: "4h"
        case .d1: "1D"
        }
    }

    /// Length of one candle in seconds.
    public var seconds: Int {
        switch self {
        case .m1: 60
        case .m5: 300
        case .m15: 900
        case .h1: 3_600
        case .h4: 14_400
        case .d1: 86_400
        }
    }

    /// Futures sessions open at 22:00 UTC (17:00 Chicago in daylight time).
    /// 4-hour and daily candles are aligned to the session open, as futures
    /// platforms do; shorter candles are aligned to the clock (UTC).
    public static let sessionOpenOffset = 22 * 3_600

    private var alignmentOffset: Int {
        self >= .h4 ? Self.sessionOpenOffset : 0
    }

    /// Start of the candle containing `time`.
    public func bucketStart(_ time: Date) -> Date {
        let t = time.timeIntervalSince1970 - Double(alignmentOffset)
        let start = (t / Double(seconds)).rounded(.down) * Double(seconds)
        return Date(timeIntervalSince1970: start + Double(alignmentOffset))
    }

    /// The session (trading day) a time belongs to, counted in days since
    /// 1970 from the 22:00 UTC session open. Used to reset session VWAP.
    public static func sessionDay(_ time: Date) -> Int {
        Int(((time.timeIntervalSince1970 - Double(sessionOpenOffset)) / 86_400).rounded(.down))
    }

    public static func < (lhs: Timeframe, rhs: Timeframe) -> Bool { lhs.seconds < rhs.seconds }
}
