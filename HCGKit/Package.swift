// swift-tools-version: 6.0
import PackageDescription

// HCGKit — shared, UI-independent building blocks for HCG ONE: UNLEASHED.
//
// - HCGDomain:       value types (instruments, product catalog, formatting). Foundation only.
// - HCGTrading:      simulated paper-trading account and deterministic order engine. Foundation only.
// - HCGCharting:     candles for 1m–1D aggregated from timestamped trades, and indicators. Foundation only.
// - HCGMarketSim:    deterministic simulated market, order book, clock, host, persistence. Foundation + Observation.
// - HCGAppModel:     app navigation model (destinations, Go menu, per-window state). Foundation + Observation.
// - HCGDesignSystem: SwiftUI tokens and components for macOS. Compiles to an empty module elsewhere.
let package = Package(
    name: "HCGKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HCGDomain", targets: ["HCGDomain"]),
        .library(name: "HCGTrading", targets: ["HCGTrading"]),
        .library(name: "HCGCharting", targets: ["HCGCharting"]),
        .library(name: "HCGMarketSim", targets: ["HCGMarketSim"]),
        .library(name: "HCGAppModel", targets: ["HCGAppModel"]),
        .library(name: "HCGDesignSystem", targets: ["HCGDesignSystem"]),
    ],
    targets: [
        .target(name: "HCGDomain"),
        .target(name: "HCGTrading", dependencies: ["HCGDomain"]),
        .target(name: "HCGCharting"),
        .target(name: "HCGMarketSim", dependencies: ["HCGDomain", "HCGTrading", "HCGCharting"]),
        .target(name: "HCGAppModel", dependencies: ["HCGDomain"]),
        .target(name: "HCGDesignSystem", dependencies: ["HCGDomain"]),
        .testTarget(name: "HCGDomainTests", dependencies: ["HCGDomain"]),
        .testTarget(name: "HCGTradingTests", dependencies: ["HCGTrading", "HCGDomain"]),
        .testTarget(name: "HCGChartingTests", dependencies: ["HCGCharting"]),
        .testTarget(name: "HCGMarketSimTests", dependencies: ["HCGMarketSim", "HCGTrading", "HCGCharting", "HCGDomain"]),
        .testTarget(name: "HCGAppModelTests", dependencies: ["HCGAppModel", "HCGDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
