import Foundation
import Testing
@testable import HCGMarketSim

// Ported from HCG-One@b4f0e29: ios-hcg/HCGONETests/HCGONETests.swift (GEXModelTests).
// Test bodies are unchanged unless noted.

/// GEX / DEX model stability: the exposure model must never produce NaN,
/// Infinity or a Double→Int conversion trap, whatever the inputs — a bad
/// dataset degrades to zeros, never a crash.
@Suite("GEX model (ported from HCG ONE)")
struct GEXModelTests {

    private func assertFinite(_ output: GEXOutput) {
        for s in output.strikes {
            #expect(s.gex.isFinite, "GEX by strike must be finite")
            #expect(s.callDeltaDEX.isFinite, "call DEX must be finite")
            #expect(s.putDeltaDEX.isFinite, "put DEX must be finite")
            #expect(s.callOI >= 0 && s.putOI >= 0, "open interest must be non-negative")
        }
        #expect(output.totalGEX.isFinite)
        #expect(output.totalDEX.isFinite)
        for p in output.profile { #expect(p.gex.isFinite) }
        for p in output.dexProfile { #expect(p.dex.isFinite) }
    }

    @Test func defaultInputsProduceFiniteSaneOutput() {
        let output = GEXModel.run(inputs: GEXInputs())
        assertFinite(output)
        #expect(output.strikes.count == 21)
        #expect(output.flipLevel != nil, "the default profile should cross zero")
        #expect(output.gammaWall != nil)
        #expect(output.callDEX >= 0 && output.putDEX <= 0)
    }

    /// The original crash: outer-strike distances could exceed 1, and a
    /// negative base raised to a fractional exponent produced NaN, whose
    /// Int conversion traps at runtime.
    @Test func fractionalConcentrationDoesNotProduceNaN() {
        var inputs = GEXInputs()
        inputs.concentration = 0.6 // fractional exponent 4.4
        inputs.spot = 5_481 // ATM rounding pushes outer-strike distance past 1
        assertFinite(GEXModel.run(inputs: inputs))

        inputs.concentration = 1.0
        inputs.callPutSkew = -1.0
        assertFinite(GEXModel.run(inputs: inputs))
    }

    @Test func extremeInputsDegradeToZeroNotCrash() {
        var invalid = GEXInputs()
        invalid.spot = 0
        invalid.impliedVol = 0
        invalid.daysToExpiry = 0
        assertFinite(GEXModel.run(inputs: invalid))

        var nan = GEXInputs()
        nan.spot = .nan
        nan.impliedVol = .infinity
        nan.concentration = .nan
        nan.strikeStep = -25
        nan.strikesEitherSide = -5
        let output = GEXModel.run(inputs: nan)
        assertFinite(output)
        // Corrected expectation: the iOS test expected 3 strikes, but `sanitized`
        // restores `strikesEitherSide` to its default of 10, i.e. 2 × 10 + 1 = 21
        // strikes. The model is unchanged; this assertion could not pass on iOS.
        #expect(output.strikes.count == 21, "sanitized inputs restore a valid chain")
    }

    @Test func deltasStayWithinBounds() {
        for strikeOffset in -5...5 {
            let strike = 5_480 + Double(strikeOffset) * 25
            let call = GEXModel.callDelta(spot: 5_480, strike: strike, vol: 0.14, dte: 7)
            let put = GEXModel.putDelta(spot: 5_480, strike: strike, vol: 0.14, dte: 7)
            #expect(call >= 0 && call <= 1)
            #expect(put >= -1 && put <= 0)
        }
        // Degenerate inputs return 0 rather than NaN.
        #expect(GEXModel.callDelta(spot: 0, strike: 100, vol: 0.2, dte: 7) == 0)
        #expect(GEXModel.putDelta(spot: 100, strike: 100, vol: 0, dte: 7) == 0)
        #expect(GEXModel.gamma(spot: 100, strike: 100, vol: 0.2, dte: 0) == 0)
    }

    @Test func gexAndDexShareTheSameSyntheticChain() {
        let output = GEXModel.run(inputs: GEXInputs())
        // The same open interest feeds both exposures — the charts cannot
        // disagree about the chain they describe.
        let oiSum = output.strikes.reduce(0) { $0 + $1.callOI + $1.putOI }
        #expect(oiSum > 0)
        #expect(abs(output.totalDEX - (output.callDEX + output.putDEX)) < 0.01)
    }

    @Test func seedDeterminism() {
        var a = GEXInputs(); a.seed = 7
        var b = GEXInputs(); b.seed = 7
        let x = GEXModel.run(inputs: a)
        let y = GEXModel.run(inputs: b)
        #expect(x.strikes.map(\.callOI) == y.strikes.map(\.callOI))
        #expect(x.totalGEX == y.totalGEX)
    }
}
