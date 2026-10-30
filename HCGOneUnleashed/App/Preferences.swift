import Foundation

/// UserDefaults keys for local, non-sensitive preferences. Nothing here is a
/// credential, account detail or server decision.
enum Preferences {
    static let defaultSpeed = "simulation.defaultSpeed"
    static let startSimulationOnLaunch = "simulation.startOnLaunch"
    static let ladderLevels = "orderFlow.ladderLevels"
}
