// swift-tools-version: 6.0
import PackageDescription

// HCGKit — shared, UI-independent building blocks for HCG ONE UNLEASHED.
//
// - HCGDomain:       value types (instruments, product catalog, formatting). Foundation only.
// - HCGMarketSim:    deterministic simulated market, order book, broker, host. Foundation + Observation.
// - HCGDesignSystem: SwiftUI tokens and components for macOS. Compiles to an empty module elsewhere.
let package = Package(
    name: "HCGKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HCGDomain", targets: ["HCGDomain"]),
        .library(name: "HCGMarketSim", targets: ["HCGMarketSim"]),
        .library(name: "HCGDesignSystem", targets: ["HCGDesignSystem"]),
    ],
    targets: [
        .target(name: "HCGDomain"),
        .target(name: "HCGMarketSim", dependencies: ["HCGDomain"]),
        .target(name: "HCGDesignSystem", dependencies: ["HCGDomain"]),
        .testTarget(name: "HCGDomainTests", dependencies: ["HCGDomain"]),
        .testTarget(name: "HCGMarketSimTests", dependencies: ["HCGMarketSim", "HCGDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
