import Foundation
import HCGDomain

// Ported from HCG-One@b4f0e29: ios-hcg/HCGONE/TradingLab/GEXModel.swift.
// Model unchanged; declarations made public and keyed by MarketSymbol.

/// Illustrative gamma & delta exposure model. All inputs are user-configured
/// and the open interest is synthetic — this is SIMULATED OPTIONS DATA built
/// to teach the dealer-hedging mechanism, not real exchange data and not
/// knowledge of any actual dealer's positioning.
///
/// Model assumptions (explicit):
/// - Black-Scholes European options, constant volatility, no rates/dividends.
/// - Contract multiplier 1 (exposure is expressed in $ per 1% underlying move
///   per contract: |gamma| × OI × spot² × 0.01, |delta| × OI × spot × 0.01).
/// - Sign convention: dealers are assumed short calls / long puts, so call
///   gamma exposure is positive and put gamma exposure is negative. Delta
///   exposure is the dealer's directional hedge requirement: calls positive,
///   puts negative (put delta is negative).
public struct GEXInputs: Sendable, Hashable {
    public var spot: Double = 5_480
    public var impliedVol: Double = 0.14 // annualized
    public var daysToExpiry: Double = 7
    public var strikeStep: Double = 25
    public var strikesEitherSide: Int = 10
    /// 0…1 — how concentrated open interest is at at-the-money strikes.
    public var concentration: Double = 0.6
    /// >0 tilts OI toward calls (dealer short calls ⇒ positive gamma above), <0 toward puts.
    public var callPutSkew: Double = 0.2
    public var seed: UInt64 = 42

    public init() {}

    public static func defaults(for symbol: MarketSymbol) -> GEXInputs {
        var i = GEXInputs()
        switch symbol {
        case .gc: i.spot = 2_655; i.strikeStep = 10
        case .nq: i.spot = 19_850; i.strikeStep = 50
        case .es: i.spot = 5_480; i.strikeStep = 25
        case .cl: i.spot = 77.4; i.strikeStep = 1
        }
        return i
    }

    /// Clamped, finite copy of the inputs. Every user-facing value passes
    /// through here before any calculation runs, so an invalid dataset can
    /// never produce NaN/Infinity downstream (or a conversion trap).
    public var sanitized: GEXInputs {
        var i = self
        i.spot = i.spot.isFinite && i.spot > 0 ? min(i.spot, 1_000_000) : 5_480
        i.impliedVol = i.impliedVol.isFinite ? min(max(i.impliedVol, 0.01), 3.0) : 0.14
        i.daysToExpiry = i.daysToExpiry.isFinite ? min(max(i.daysToExpiry, 0.25), 365) : 7
        i.strikeStep = i.strikeStep.isFinite && i.strikeStep > 0 ? min(i.strikeStep, i.spot) : 25
        i.strikesEitherSide = (1...20).contains(i.strikesEitherSide) ? i.strikesEitherSide : 10
        i.concentration = i.concentration.isFinite ? min(max(i.concentration, 0), 1) : 0.6
        i.callPutSkew = i.callPutSkew.isFinite ? min(max(i.callPutSkew, -1), 1) : 0.2
        return i
    }
}

public struct GEXStrike: Identifiable, Sendable, Hashable {
    public var strike: Double
    public var callOI: Int
    public var putOI: Int
    /// Model gamma exposure in $ per 1% move, calls positive / puts negative
    /// under the standard "dealers short calls, long puts" convention.
    public var gex: Double
    /// Dealer delta exposure in $ per 1% move (call delta positive, put delta negative).
    public var callDeltaDEX: Double
    public var putDeltaDEX: Double
    public var dex: Double { callDeltaDEX + putDeltaDEX }
    public var id: Double { strike }
}

public struct GEXOutput: Sendable {
    public var strikes: [GEXStrike]
    /// Net gamma profile across price: (price, netGEX).
    public var profile: [(price: Double, gex: Double)]
    /// Net delta profile across price: (price, netDEX).
    public var dexProfile: [(price: Double, dex: Double)]
    /// Price where cumulative net gamma crosses zero (the flip).
    public var flipLevel: Double?
    /// Strike with the largest absolute gamma concentration (the "wall").
    public var gammaWall: Double?
    public var totalGEX: Double
    public var totalDEX: Double
    public var callDEX: Double
    public var putDEX: Double
}

public enum GEXModel {

    // MARK: Normal distribution helpers

    /// Standard normal probability density function.
    public static func normPDF(_ x: Double) -> Double {
        exp(-0.5 * x * x) / sqrt(2 * .pi)
    }

    /// Standard normal CDF via the Abramowitz–Stegun erf approximation
    /// (|error| < 1.5e-7 — far beyond chart precision).
    public static func normCDF(_ x: Double) -> Double {
        let sign = x < 0 ? -1.0 : 1.0
        let ax = abs(x) / sqrt(2.0)
        // erf(z) ≈ 1 - (1 + a1 t + a2 t² + a3 t³ + a4 t⁴ + a5 t⁵)^-4, t = 1/(1 + p z)
        let p = 0.3275911
        let a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429
        let t = 1 / (1 + p * ax)
        let poly = ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t
        let erf = sign * (1 - poly * exp(-ax * ax))
        return 0.5 * (1 + erf)
    }

    // MARK: Greeks

    /// Black-Scholes gamma per unit of underlying. Returns 0 for any
    /// non-positive or non-finite input instead of NaN.
    public static func gamma(spot: Double, strike: Double, vol: Double, dte: Double) -> Double {
        guard isValid(spot: spot, strike: strike, vol: vol, dte: dte) else { return 0 }
        let t = dte / 365.0
        let sqrtT = sqrt(t)
        let d1 = (log(spot / strike) + 0.5 * vol * vol * t) / (vol * sqrtT)
        guard d1.isFinite else { return 0 }
        let pdf = normPDF(d1)
        let g = pdf / (spot * vol * sqrtT)
        return g.isFinite ? g : 0
    }

    private static func d1(spot: Double, strike: Double, vol: Double, t: Double) -> Double {
        (log(spot / strike) + 0.5 * vol * vol * t) / (vol * sqrt(t))
    }

    /// Black-Scholes call delta (0…1). Returns 0 for invalid inputs.
    public static func callDelta(spot: Double, strike: Double, vol: Double, dte: Double) -> Double {
        guard isValid(spot: spot, strike: strike, vol: vol, dte: dte) else { return 0 }
        let delta = normCDF(d1(spot: spot, strike: strike, vol: vol, t: dte / 365.0))
        return delta.isFinite ? min(max(delta, 0), 1) : 0
    }

    /// Black-Scholes put delta (−1…0). Returns 0 for invalid inputs.
    public static func putDelta(spot: Double, strike: Double, vol: Double, dte: Double) -> Double {
        guard isValid(spot: spot, strike: strike, vol: vol, dte: dte) else { return 0 }
        let delta = normCDF(d1(spot: spot, strike: strike, vol: vol, t: dte / 365.0)) - 1
        return delta.isFinite ? min(max(delta, -1), 0) : 0
    }

    private static func isValid(spot: Double, strike: Double, vol: Double, dte: Double) -> Bool {
        spot > 0 && strike > 0 && vol > 0 && dte > 0
            && [spot, strike, vol, dte].allSatisfy(\.isFinite)
    }

    /// Bounded integer conversion: NaN/Infinity and out-of-range values never
    /// trap (Double→Int conversion with NaN crashes at runtime).
    private static func safeInt(_ value: Double, upperBound: Double = 10_000_000) -> Int {
        guard value.isFinite, value >= 0, value < upperBound else { return 0 }
        return Int(value)
    }

    // MARK: Model

    public static func run(inputs rawInputs: GEXInputs) -> GEXOutput {
        let inputs = rawInputs.sanitized
        var rng = SeededRNG(seed: inputs.seed)
        let n = inputs.strikesEitherSide
        let atmStrike = (inputs.spot / inputs.strikeStep).rounded() * inputs.strikeStep
        let halfRange = inputs.strikeStep * Double(n)

        var strikes: [GEXStrike] = []
        for k in -n...n {
            let strike = atmStrike + Double(k) * inputs.strikeStep
            guard strike > 0 else { continue }
            // Clamp to 0…1: outer strikes plus ATM rounding could exceed 1,
            // which made the exponentiation below NaN (fractional exponent of
            // a negative base) — the original GEX crash.
            let distance = min(1, max(0, abs(strike - inputs.spot) / halfRange))
            let exponent = 2 + inputs.concentration * 4
            let atmWeight = distance < 1 ? pow(1 - distance, exponent) : 0
            let base = 4_000 * atmWeight + Double(rng.range(0, 900))
            // Puts stack in the wings (distance → 1), mirroring real chains —
            // this is what makes the gamma flip level meaningful for neutral inputs.
            let callShare = 0.5 + inputs.callPutSkew * 0.5 * (1 - distance) - 0.15 * distance
            let callOI = safeInt(base * min(0.95, max(0.05, callShare)))
            let putOI = safeInt(base) - callOI >= 0 ? safeInt(base) - callOI : 0
            let g = gamma(spot: inputs.spot, strike: strike, vol: inputs.impliedVol, dte: inputs.daysToExpiry)
            let cd = callDelta(spot: inputs.spot, strike: strike, vol: inputs.impliedVol, dte: inputs.daysToExpiry)
            let pd = putDelta(spot: inputs.spot, strike: strike, vol: inputs.impliedVol, dte: inputs.daysToExpiry)
            // $ per 1% move: gamma/delta × OI × spot (or spot²) × 0.01
            let callGEX = g * Double(callOI) * inputs.spot * inputs.spot * 0.01
            let putGEX = -g * Double(putOI) * inputs.spot * inputs.spot * 0.01
            let callDEX = cd * Double(callOI) * inputs.spot * 0.01
            let putDEX = pd * Double(putOI) * inputs.spot * 0.01
            strikes.append(GEXStrike(
                strike: strike, callOI: callOI, putOI: putOI,
                gex: (callGEX + putGEX).isFinite ? callGEX + putGEX : 0,
                callDeltaDEX: callDEX.isFinite ? callDEX : 0,
                putDeltaDEX: putDEX.isFinite ? putDEX : 0
            ))
        }

        // Exposure profiles across price (OI fixed, spot varying). 60 steps
        // over a bounded range — cheap, and re-run only on input change.
        let lo = (strikes.first?.strike ?? atmStrike) - inputs.strikeStep * 3
        let hi = (strikes.last?.strike ?? atmStrike) + inputs.strikeStep * 3
        let steps = 60
        var profile: [(price: Double, gex: Double)] = []
        var dexProfile: [(price: Double, dex: Double)] = []
        if hi > lo {
            for i in 0...steps {
                let p = lo + (hi - lo) * Double(i) / Double(steps)
                var net = 0.0
                var netDEX = 0.0
                for s in strikes {
                    let g = gamma(spot: p, strike: s.strike, vol: inputs.impliedVol, dte: inputs.daysToExpiry)
                    let gexTerm = (g * Double(s.callOI) - g * Double(s.putOI)) * p * p * 0.01
                    net += gexTerm.isFinite ? gexTerm : 0
                    let cd = callDelta(spot: p, strike: s.strike, vol: inputs.impliedVol, dte: inputs.daysToExpiry)
                    let pd = putDelta(spot: p, strike: s.strike, vol: inputs.impliedVol, dte: inputs.daysToExpiry)
                    let dexTerm = (cd * Double(s.callOI) + pd * Double(s.putOI)) * p * 0.01
                    netDEX += dexTerm.isFinite ? dexTerm : 0
                }
                profile.append((p, net.isFinite ? net : 0))
                dexProfile.append((p, netDEX.isFinite ? netDEX : 0))
            }
        }

        var flip: Double?
        for i in 1..<max(profile.count, 1) {
            let a = profile[i - 1].gex
            let b = profile[i].gex
            if (a > 0 && b <= 0) || (a < 0 && b >= 0) {
                flip = profile[i].price
                break
            }
        }
        let wall = strikes.max(by: { abs($0.gex) < abs($1.gex) })?.strike
        let totalGEX = strikes.reduce(0) { $0 + $1.gex }
        let callDEXTotal = strikes.reduce(0) { $0 + $1.callDeltaDEX }
        let putDEXTotal = strikes.reduce(0) { $0 + $1.putDeltaDEX }
        return GEXOutput(
            strikes: strikes,
            profile: profile,
            dexProfile: dexProfile,
            flipLevel: flip,
            gammaWall: wall,
            totalGEX: totalGEX.isFinite ? totalGEX : 0,
            totalDEX: (callDEXTotal + putDEXTotal).isFinite ? callDEXTotal + putDEXTotal : 0,
            callDEX: callDEXTotal.isFinite ? callDEXTotal : 0,
            putDEX: putDEXTotal.isFinite ? putDEXTotal : 0
        )
    }
}
