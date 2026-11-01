import Foundation

/// UserDefaults keys for local, non-sensitive preferences. Nothing here is a
/// credential, account detail or server decision.
enum Preferences {
    static let defaultSpeed = "simulation.defaultSpeed"
    static let startSimulationOnLaunch = "simulation.startOnLaunch"
    static let ladderLevels = "orderFlow.ladderLevels"
    /// Hours of simulated market history a new session starts with.
    static let marketHistoryHours = "simulation.marketHistoryHours"
    static let defaultMarketHistoryHours = 6
    /// Chart state for Order Flow (timeframe, overlays, study), as JSON.
    static let chartSettings = "orderFlow.chartSettings"
}
