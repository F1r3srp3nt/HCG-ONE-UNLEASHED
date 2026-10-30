import Foundation
import Testing
import HCGDomain
@testable import HCGTrading

@Suite("Ticket price entry and trading formats")
struct TradingFormatTests {
    let us = Locale(identifier: "en_US")
    let no = Locale(identifier: "nb_NO")

    @Test("Prices parse with a dot everywhere and in the user's own locale")
    func parse() {
        #expect(TradingFormat.parsePrice("2655.1", locale: us) == 2655.1)
        #expect(TradingFormat.parsePrice(" 2655.1 ", locale: no) == 2655.1, "dot decimal accepted in any locale")
        #expect(TradingFormat.parsePrice("2655,1", locale: no) == 2655.1)
        #expect(TradingFormat.parsePrice("2,655.10", locale: us) == 2655.1)
        #expect(TradingFormat.parsePrice("", locale: us) == nil)
        #expect(TradingFormat.parsePrice("abc", locale: us) == nil)
    }

    @Test("A price written into the ticket reads back exactly, for every market and locale")
    func roundTrip() {
        for symbol in MarketSymbol.allCases {
            let spec = symbol.spec
            let price = spec.price(ticks: spec.ticks(price: 1234.5) + 3)
            for locale in [us, no] {
                let text = TradingFormat.priceText(price, spec, locale: locale)
                #expect(TradingFormat.parsePrice(text, locale: locale) == price, "\(symbol) \(locale.identifier) \(text)")
            }
        }
        #expect(TradingFormat.priceText(21_920.25, MarketSymbol.es.spec, locale: us) == "21920.25", "no grouping in fields")
        #expect(TradingFormat.priceText(2655.1, MarketSymbol.gc.spec, locale: no) == "2655,10", "GC shows two decimals, as HCG ONE does")
    }

    @Test("Snapping rounds to the tick and never traps on unusable input")
    func safety() {
        let spec = MarketSymbol.es.spec
        #expect(TradingFormat.snapped(21_920.30, spec) == 21_920.25)
        for bad in [Double.nan, .infinity, -1, 0, 1e300] {
            #expect(!TradingFormat.isSafe(bad))
            let snapped = TradingFormat.snapped(bad, spec)
            #expect(snapped.isNaN || snapped == bad, "unusable prices are passed through for the engine to reject")
        }
        #expect(TradingFormat.parsePrice("nan", locale: us).map(TradingFormat.isSafe) == false)
    }

    @Test("Simulated time is shown in UTC")
    func utcTime() {
        #expect(TradingFormat.dateTime(Date(timeIntervalSince1970: 1_767_623_400)).hasSuffix("UTC"))
        let time = TradingFormat.time(Date(timeIntervalSince1970: 1_767_623_400)) // 2026-01-05 14:30:00 UTC
        #expect(time.contains("14:30:00") || time.contains("2:30:00"), "24- or 12-hour clock, but UTC: \(time)")
    }
}
