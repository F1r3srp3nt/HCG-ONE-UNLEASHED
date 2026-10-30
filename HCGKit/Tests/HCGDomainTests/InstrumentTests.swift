import Foundation
import Testing
@testable import HCGDomain

@Suite("Instrument specifications")
struct InstrumentTests {
    @Test("Every instrument has a positive, finite tick size and point value", arguments: MarketSymbol.allCases)
    func tickSizeIsValid(_ symbol: MarketSymbol) {
        let spec = symbol.spec
        #expect(spec.symbol == symbol)
        #expect(spec.tickSize > 0 && spec.tickSize.isFinite)
        #expect(spec.pointValue > 0 && spec.pointValue.isFinite)
        #expect(spec.tickValue > 0)
    }

    @Test("Tick sizes and tick values match the contract specifications")
    func knownContractValues() {
        #expect(MarketSymbol.gc.spec.tickSize == 0.10)
        #expect(MarketSymbol.nq.spec.tickSize == 0.25)
        #expect(MarketSymbol.es.spec.tickSize == 0.25)
        #expect(MarketSymbol.cl.spec.tickSize == 0.01)
        #expect(abs(MarketSymbol.gc.spec.tickValue - 10) < 1e-9)
        #expect(abs(MarketSymbol.nq.spec.tickValue - 5) < 1e-9)
        #expect(abs(MarketSymbol.es.spec.tickValue - 12.5) < 1e-9)
        #expect(abs(MarketSymbol.cl.spec.tickValue - 10) < 1e-9)
    }

    @Test("Prices round-trip through whole ticks", arguments: MarketSymbol.allCases)
    func priceTickRoundTrip(_ symbol: MarketSymbol) {
        let spec = symbol.spec
        for ticks: Int64 in [1, 7, 7_740, 26_550, 79_400, 1_000_000] {
            #expect(spec.ticks(price: spec.price(ticks: ticks)) == ticks)
        }
    }

    @Test("Tick prices are the closest Double to the exact decimal value")
    func exactTickPrices() {
        #expect(MarketSymbol.gc.spec.price(ticks: 26_527) == 2652.7)
        #expect(MarketSymbol.gc.spec.price(ticks: 26_891) == 2689.1)
        #expect(MarketSymbol.nq.spec.price(ticks: 79_263) == 19_815.75)
        #expect(MarketSymbol.es.spec.price(ticks: 22_555) == 5_638.75)
        #expect(MarketSymbol.cl.spec.price(ticks: 7_642) == 76.42)
    }

    @Test("Off-tick prices round to the nearest valid tick", arguments: MarketSymbol.allCases)
    func roundingToTick(_ symbol: MarketSymbol) {
        let spec = symbol.spec
        let base = spec.price(ticks: 10_000)
        #expect(spec.roundedToTick(base + spec.tickSize * 0.4) == base)
        #expect(spec.roundedToTick(base + spec.tickSize * 0.6) == spec.price(ticks: 10_001))
        #expect(spec.roundedToTick(base - spec.tickSize * 0.6) == spec.price(ticks: 9_999))
        #expect(spec.ticks(price: spec.roundedToTick(base + spec.tickSize * 0.6)) == 10_001)
    }

    @Test("Display decimals cover the tick size")
    func priceDecimals() {
        #expect(MarketSymbol.gc.spec.priceDecimals == 2)
        #expect(MarketSymbol.nq.spec.priceDecimals == 2)
        #expect(MarketSymbol.es.spec.priceDecimals == 2)
        #expect(MarketSymbol.cl.spec.priceDecimals == 2)
    }

    @Test("Symbols sort in workstation order")
    func symbolOrder() {
        #expect(MarketSymbol.allCases.sorted() == [.gc, .nq, .es, .cl])
        #expect(MarketSymbol.gc.ticker == "GC")
    }
}

@Suite("Formatting")
struct FormattingTests {
    private let locale = Locale(identifier: "en_US")

    @Test func priceUsesFixedDecimals() {
        #expect(PriceFormat.price(2655.1, decimals: 2, locale: locale) == "2,655.10")
        #expect(PriceFormat.price(77.4, decimals: 2, locale: locale) == "77.40")
    }

    @Test func changeIsSigned() {
        #expect(PriceFormat.change(1.2, decimals: 2, locale: locale) == "+1.20")
        #expect(PriceFormat.change(-0.75, decimals: 2, locale: locale) == "\u{2212}0.75")
        #expect(PriceFormat.change(0, decimals: 2, locale: locale) == "0.00")
    }

    @Test func ticksPluralise() {
        #expect(PriceFormat.ticks(1) == "1 tick")
        #expect(PriceFormat.ticks(3) == "3 ticks")
    }

    @Test func productCatalogHasUniqueIdentifiers() {
        let ids = HCGEcosystem.products.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.first == "hcg-one-unleashed")
    }
}
