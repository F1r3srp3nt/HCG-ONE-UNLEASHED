import Foundation

// Ported verbatim (algorithm) from HCG-One@b4f0e29: TradingLab/MarketEngine.swift.

/// SplitMix64 — small, fast, reproducible. The same seed always produces the
/// same sequence, which is what makes simulated sessions and scenario replays
/// exact on every machine.
public struct SeededRNG: Sendable, Equatable, Codable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    /// Uniform value in `0..<1`.
    public mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_25CE_4D95
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z & ((1 << 53) - 1)) / Double(1 << 53)
    }

    /// Uniform integer in `0..<upper` (`upper` is clamped to at least 1).
    public mutating func int(_ upper: Int) -> Int {
        let bound = max(1, upper)
        return Int(next() * Double(bound)) % bound
    }

    /// Uniform integer in `lower...upper`.
    public mutating func range(_ lower: Int, _ upper: Int) -> Int {
        lower + int(max(1, upper - lower + 1))
    }

    public mutating func range(_ bounds: ClosedRange<Int>) -> Int {
        range(bounds.lowerBound, bounds.upperBound)
    }
}
