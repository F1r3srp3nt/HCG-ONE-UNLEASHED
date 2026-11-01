import Foundation
@testable import HCGCharting

/// Parsed reference data (see ReferenceData.swift and
/// HCGKit/Tools/generate_chart_reference.py).
enum Reference {
    private static func rows(_ csv: String) -> [[Substring]] {
        csv.split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false) }
    }

    private static let ohlc = rows(ReferenceCSV.ohlc).map { $0.map { Double($0)! } }
    static let open = ohlc.map { $0[0] }
    static let high = ohlc.map { $0[1] }
    static let low = ohlc.map { $0[2] }
    static let close = ohlc.map { $0[3] }

    private static let indicatorRows = rows(ReferenceCSV.indicators).map { $0.map { Double($0) } }
    private static func column(_ i: Int) -> [Double?] { indicatorRows.map { $0[i] } }
    static let sma20 = column(0)
    static let ema9 = column(1)
    static let ema21 = column(2)
    static let rsi14 = column(3)
    static let macd = column(4)
    static let macdSignal = column(5)
    static let macdHistogram = column(6)
    static let bollingerUpper = column(7)
    static let bollingerMiddle = column(8)
    static let bollingerLower = column(9)
    static let atr14 = column(10)

    static let trades: [TradeEvent] = rows(ReferenceCSV.trades).map {
        TradeEvent(time: Date(timeIntervalSince1970: Double($0[0])!), priceTicks: Int64($0[1])!,
                   size: Int($0[2])!, aggressor: $0[3] == "b" ? .buy : .sell)
    }

    typealias CandleRow = (Double, Int64, Int64, Int64, Int64, Int, Int, Int, Int, Double)

    static let candles: [Timeframe: [CandleRow]] = {
        var out: [Timeframe: [CandleRow]] = [:]
        for r in rows(ReferenceCSV.candles) {
            let row: CandleRow = (Double(r[1])!, Int64(r[2])!, Int64(r[3])!, Int64(r[4])!, Int64(r[5])!,
                                  Int(r[6])!, Int(r[7])!, Int(r[8])!, Int(r[9])!, Double(r[10])!)
            out[Timeframe(rawValue: String(r[0]))!, default: []].append(row)
        }
        return out
    }()

    private static let vwapRows = rows(ReferenceCSV.sessionVWAP)
    static let sessionVWAP1m = vwapRows.filter { $0[0] == "m1" }.map { Double($0[1])! }
    static let sessionVWAP5m = vwapRows.filter { $0[0] == "m5" }.map { Double($0[1])! }
}
