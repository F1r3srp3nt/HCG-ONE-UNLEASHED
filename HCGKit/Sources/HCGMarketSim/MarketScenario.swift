import Foundation
import HCGDomain

// Ported from HCG-One@b4f0e29: ios-hcg/HCGONE/TradingLab/MarketScenario.swift.
// The scenario catalog text and phase parameters are unchanged.

/// Scripted events the simulator applies mid-phase. They are market mechanics,
/// not outcomes: a wall can absorb or break depending on the flow around it.
public enum ScenarioEvent: Codable, Sendable, Hashable {
    /// A large resting order placed `ticksFromMid` levels into the book.
    case absorptionWall(side: BookSide, ticksFromMid: Int, size: Int)
    /// Fast execution that sweeps through N levels of liquidity.
    case sweep(side: BookSide, levels: Int)
    /// Resting liquidity is pulled, thinning the book (and widening the spread).
    case liquidityPull(side: BookSide)
    case volatilityBurst
    case calm
}

/// One phase of a scripted scenario: a stretch of market updates with a flow
/// regime plus optional discrete events.
public struct ScenarioPhase: Hashable, Sendable {
    /// Number of market updates in the phase.
    public var ticks: Int
    /// Mean drift in ticks per update (negative = sellers in control).
    public var drift: Double
    /// −1 heavy aggressive selling … +1 heavy aggressive buying.
    public var aggressorBias: Double
    /// Volatility regime: mean absolute move per executed trade, in ticks.
    public var vol: Double
    /// How quickly consumed liquidity is refilled (0…1).
    public var replenish: Double
    public var events: [ScenarioEvent]

    public init(ticks: Int, drift: Double = 0, aggressorBias: Double = 0, vol: Double = 1,
                replenish: Double = 0.35, events: [ScenarioEvent] = []) {
        self.ticks = ticks
        self.drift = drift
        self.aggressorBias = aggressorBias
        self.vol = vol
        self.replenish = replenish
        self.events = events
    }
}

/// A complete training scenario. `observe` tells the user what to watch for;
/// `debrief` is the explanation revealed afterwards.
public struct MarketScenario: Identifiable, Hashable, Sendable {
    public enum Level: String, Sendable, CaseIterable {
        case beginner, intermediate, advanced
    }

    public var id: String
    public var title: String
    public var symbol: MarketSymbol
    public var level: Level
    public var summary: String
    public var observe: [String]
    public var phases: [ScenarioPhase]
    public var debrief: [String]
    public var concept: String

    public init(id: String, title: String, symbol: MarketSymbol, level: Level, summary: String,
                observe: [String], phases: [ScenarioPhase], debrief: [String], concept: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.level = level
        self.summary = summary
        self.observe = observe
        self.phases = phases
        self.debrief = debrief
        self.concept = concept
    }

    /// Stable per-scenario seed — every scenario replays identically.
    public var defaultSeed: UInt64 {
        let scalars = id.unicodeScalars.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1.value) }
        return (scalars % 100_000) + 7
    }

    /// Total market updates across all phases.
    public var totalTicks: Int { phases.reduce(0) { $0 + $1.ticks } }

    // MARK: Catalog

    public static let catalog: [MarketScenario] = [
        MarketScenario(
            id: "sweep-reversal", title: "Liquidity Sweep & Reversal", symbol: .gc, level: .beginner,
            summary: "Price pushes below a shelf of resting bids, fills the stops sitting there, then snaps back. The classic stop-hunt structure.",
            observe: [
                "Bid sizes below the prior low thin out — resting stops live there.",
                "A burst of aggressive selling prints, but price barely travels.",
                "The tape flips to aggressive buying right after the sweep.",
                "CVD makes a new low while price does not — a divergence.",
            ],
            phases: [
                ScenarioPhase(ticks: 14, drift: 0.05, aggressorBias: 0.1, vol: 1),
                ScenarioPhase(ticks: 10, drift: -0.25, aggressorBias: -0.45, vol: 1.4, events: [.sweep(side: .bid, levels: 5)]),
                ScenarioPhase(ticks: 8, drift: -0.1, aggressorBias: -0.2, vol: 2.2, events: [.liquidityPull(side: .bid)]),
                ScenarioPhase(ticks: 26, drift: 0.32, aggressorBias: 0.55, vol: 1.3),
                ScenarioPhase(ticks: 14, drift: 0.05, aggressorBias: 0.05, vol: 1),
            ],
            debrief: [
                "The resting bids below the low were mostly stop-loss orders from longs — liquidity waiting to be filled.",
                "Aggressive sellers consumed them, but the Selling was largely completed by stops, not new conviction.",
                "When the selling dried up, larger buyers stepped in above; price reverted because the push had no follow-through liquidity.",
                "This is why a sweep that fails to hold is often a stronger reversal signal than the breakdown itself.",
            ],
            concept: "Liquidity sweeps"
        ),
        MarketScenario(
            id: "breakout-continuation", title: "Breakout Continuation", symbol: .nq, level: .beginner,
            summary: "Consolidation under resistance, offers pulled, then aggressive buyers lift through the level and momentum carries.",
            observe: [
                "Ask sizes at the highs shrink — offers are being pulled before the break.",
                "Large aggressive buys print in quick succession at the level.",
                "Volume expands and the footprint shows stacked buy imbalances.",
            ],
            phases: [
                ScenarioPhase(ticks: 16, drift: 0.02, aggressorBias: 0.05, vol: 0.8, replenish: 0.6),
                ScenarioPhase(ticks: 6, drift: 0, aggressorBias: 0, vol: 0.7, events: [.liquidityPull(side: .offer)]),
                ScenarioPhase(ticks: 18, drift: 0.42, aggressorBias: 0.7, vol: 1.6, replenish: 0.2),
                ScenarioPhase(ticks: 22, drift: 0.22, aggressorBias: 0.35, vol: 1.2),
                ScenarioPhase(ticks: 12, drift: 0.04, aggressorBias: 0.1, vol: 1),
            ],
            debrief: [
                "Breakouts need two things: resting liquidity to be cleared or pulled, and aggressive flow to replace it.",
                "The offer pull matters — breaking into a stacked book burns aggressor capital and often fails.",
                "Continuation is visible in the footprint: new imbalances form at successive levels rather than one lone print.",
            ],
            concept: "Breakouts"
        ),
        MarketScenario(
            id: "failed-breakout", title: "Failed Breakout", symbol: .es, level: .intermediate,
            summary: "Buyers push through resistance into heavy resting size, get absorbed, and the move reverses on trapped longs.",
            observe: [
                "A large offer sits above the highs and is NOT pulled.",
                "Buy volume prints heavily at the wall while price stalls.",
                "Sellers regain control immediately after the wall holds.",
            ],
            phases: [
                ScenarioPhase(ticks: 14, drift: 0.08, aggressorBias: 0.2, vol: 1),
                ScenarioPhase(ticks: 22, drift: 0.06, aggressorBias: 0.65, vol: 1.5, events: [.absorptionWall(side: .offer, ticksFromMid: 2, size: 900)]),
                ScenarioPhase(ticks: 10, drift: 0, aggressorBias: -0.1, vol: 1.2),
                ScenarioPhase(ticks: 24, drift: -0.35, aggressorBias: -0.6, vol: 1.6),
                ScenarioPhase(ticks: 12, drift: 0, aggressorBias: 0, vol: 1),
            ],
            debrief: [
                "Absorption: passive sellers continuously replenished the wall, so every aggressive buy was matched and price could not advance.",
                "High volume with no progress is distribution, not demand.",
                "Trapped breakout longs become forced sellers when the level rejects them — fuel for the reversal.",
            ],
            concept: "Absorption"
        ),
        MarketScenario(
            id: "absorption-resistance", title: "Absorption at Resistance", symbol: .gc, level: .intermediate,
            summary: "A slow grind into a price where a large participant is quietly selling every rally — visible in the footprint, not the price.",
            observe: [
                "Each push up prints strong buy volume but gains almost no ticks.",
                "The delta of up-moves shrinks while volume stays high.",
                "CVD rises while price flattens — classic absorption signature.",
            ],
            phases: [
                ScenarioPhase(ticks: 12, drift: 0.12, aggressorBias: 0.3, vol: 1),
                ScenarioPhase(ticks: 30, drift: 0.02, aggressorBias: 0.55, vol: 1.1, replenish: 0.85, events: [.absorptionWall(side: .offer, ticksFromMid: 3, size: 1200)]),
                ScenarioPhase(ticks: 16, drift: -0.15, aggressorBias: -0.3, vol: 1.4),
                ScenarioPhase(ticks: 14, drift: 0, aggressorBias: 0, vol: 1),
            ],
            debrief: [
                "Absorption means a passive seller is absorbing every aggressive buy — the footprint shows it as high volume with negligible price progress.",
                "Aggressive buyers are spending their ammunition; once it is spent, price falls of its own weight.",
                "Watch the replenish rate: a wall that refills itself is conviction, a one-shot print is not.",
            ],
            concept: "Absorption"
        ),
        MarketScenario(
            id: "selling-exhaustion", title: "Selling Exhaustion", symbol: .cl, level: .intermediate,
            summary: "A waterfall decline that keeps printing sells but stops making downside progress — aggressive sellers are being absorbed below.",
            observe: [
                "Successive sell bursts move price down by less and less.",
                "Bid sizes below rebuild faster than they are consumed.",
                "The final flush leaves price stable on low follow-through.",
            ],
            phases: [
                ScenarioPhase(ticks: 12, drift: -0.1, aggressorBias: -0.3, vol: 1.2),
                ScenarioPhase(ticks: 20, drift: -0.4, aggressorBias: -0.7, vol: 1.8, replenish: 0.15),
                ScenarioPhase(ticks: 22, drift: -0.12, aggressorBias: -0.55, vol: 1.4, replenish: 0.95, events: [.absorptionWall(side: .bid, ticksFromMid: 2, size: 1100)]),
                ScenarioPhase(ticks: 18, drift: 0.2, aggressorBias: 0.4, vol: 1.3),
                ScenarioPhase(ticks: 12, drift: 0, aggressorBias: 0, vol: 1),
            ],
            debrief: [
                "Exhaustion is an absorption event on the sell side: passive buyers absorb aggressive sellers.",
                "Replenishing bids that survive multiple sweeps show real size is defending the level.",
                "The reversal usually starts quietly — small aggressive buys — before momentum traders pile in.",
            ],
            concept: "Exhaustion"
        ),
        MarketScenario(
            id: "vwap-rejection", title: "VWAP Rejection", symbol: .es, level: .intermediate,
            summary: "Price stretches far above session VWAP, value-based sellers defend it, and price mean-reverts to the average.",
            observe: [
                "Distance from VWAP widens while delta weakens.",
                "Selling into strength appears at the extension extreme.",
                "Price gravitates back toward VWAP as participation normalizes.",
            ],
            phases: [
                ScenarioPhase(ticks: 20, drift: 0.3, aggressorBias: 0.5, vol: 1.4),
                ScenarioPhase(ticks: 12, drift: 0.15, aggressorBias: 0.2, vol: 1.8, events: [.volatilityBurst]),
                ScenarioPhase(ticks: 26, drift: -0.28, aggressorBias: -0.5, vol: 1.3),
                ScenarioPhase(ticks: 14, drift: 0, aggressorBias: 0, vol: 1),
            ],
            debrief: [
                "VWAP is the volume-weighted average price — the session's fairest price by definition.",
                "Extensions above VWAP attract sellers who benchmark against it; the further price stretches, the more they add.",
                "Rejections back to VWAP are auction behavior, not a magic level — confirm with delta and absorption.",
            ],
            concept: "VWAP & auction theory"
        ),
        MarketScenario(
            id: "positive-gamma-range", title: "Positive Gamma Range", symbol: .es, level: .advanced,
            summary: "In a positive-gamma regime, dealer hedging suppresses volatility: moves fade and the market mean-reverts inside a range.",
            observe: [
                "Every push attracts counter-flow — moves fade quickly.",
                "The book stays relatively balanced on both sides.",
                "CVD oscillates around zero instead of trending.",
            ],
            phases: [
                ScenarioPhase(ticks: 18, drift: 0.18, aggressorBias: 0.3, vol: 1, replenish: 0.8),
                ScenarioPhase(ticks: 18, drift: -0.18, aggressorBias: -0.3, vol: 1, replenish: 0.8),
                ScenarioPhase(ticks: 18, drift: 0.15, aggressorBias: 0.25, vol: 0.9, replenish: 0.8),
                ScenarioPhase(ticks: 14, drift: 0, aggressorBias: 0, vol: 0.8),
            ],
            debrief: [
                "Positive gamma: dealers who are long gamma sell into rallies and buy dips to stay hedged — a stabilizing feedback loop.",
                "This is a model, not a law: positioning data is simulated here to illustrate the mechanism.",
                "Ranges born of positive gamma break when the regime flips — usually near large option expiries or event risk.",
            ],
            concept: "Gamma exposure"
        ),
        MarketScenario(
            id: "negative-gamma-expansion", title: "Negative Gamma Volatility Expansion", symbol: .nq, level: .advanced,
            summary: "Below the gamma flip, hedging becomes destabilizing: every move forces more selling, and ranges expand violently.",
            observe: [
                "One-sided aggression keeps triggering follow-through.",
                "Liquidity pulls — the book thins exactly when it is needed.",
                "Moves compound instead of fading.",
            ],
            phases: [
                ScenarioPhase(ticks: 10, drift: -0.05, aggressorBias: -0.15, vol: 1.1),
                ScenarioPhase(ticks: 8, drift: -0.1, aggressorBias: -0.3, vol: 1.6, events: [.liquidityPull(side: .bid)]),
                ScenarioPhase(ticks: 24, drift: -0.5, aggressorBias: -0.75, vol: 2.2, replenish: 0.1),
                ScenarioPhase(ticks: 16, drift: -0.15, aggressorBias: -0.2, vol: 2.6, events: [.volatilityBurst]),
                ScenarioPhase(ticks: 12, drift: 0, aggressorBias: 0, vol: 1.6),
            ],
            debrief: [
                "Negative gamma: dealers hedging amplify moves — sell lower, buy higher — which turns trends into accelerations.",
                "Liquidity withdrawal is the mechanism you can see: the book thins as the move builds.",
                "The Lab models this mechanism with simulated options data; it does not know real dealer positioning.",
            ],
            concept: "Gamma exposure"
        ),
        MarketScenario(
            id: "opening-range", title: "Opening Range Breakout", symbol: .nq, level: .beginner,
            summary: "The first 30 minutes build a range; the break of its edge attracts momentum and sets the session's first trend.",
            observe: [
                "Early prints cluster tightly — the range forms.",
                "The break prints expanding size at the range edge.",
                "Follow-through bars hold above the broken level.",
            ],
            phases: [
                ScenarioPhase(ticks: 22, drift: 0, aggressorBias: 0, vol: 0.7, replenish: 0.7),
                ScenarioPhase(ticks: 8, drift: 0.1, aggressorBias: 0.3, vol: 1, events: [.liquidityPull(side: .offer)]),
                ScenarioPhase(ticks: 20, drift: 0.45, aggressorBias: 0.7, vol: 1.5),
                ScenarioPhase(ticks: 18, drift: 0.15, aggressorBias: 0.25, vol: 1.1),
            ],
            debrief: [
                "The opening range concentrates the day's first liquidity decisions; its edges are reference prices.",
                "Breaks with pulling offers and stacked imbalances tend to continue; breaks into resting walls tend to fail.",
                "Session anchors like the OR high/low remain relevant for the rest of the day in auction-market logic.",
            ],
            concept: "Breakouts"
        ),
        MarketScenario(
            id: "news-volatility", title: "News Volatility", symbol: .cl, level: .advanced,
            summary: "A headline hits: spreads blow out, resting liquidity vanishes, and price gaps in bursts with violent whipsaw.",
            observe: [
                "Book depth collapses — liquidity pull on both sides.",
                "Trades print in bursts with wide gaps between prices.",
                "Two-way whipsaw before a direction survives.",
            ],
            phases: [
                ScenarioPhase(ticks: 10, drift: 0, aggressorBias: 0, vol: 0.9, replenish: 0.6),
                ScenarioPhase(ticks: 6, drift: 0, aggressorBias: -0.2, vol: 2, events: [.liquidityPull(side: .bid), .liquidityPull(side: .offer), .volatilityBurst]),
                ScenarioPhase(ticks: 12, drift: -0.5, aggressorBias: -0.7, vol: 3, replenish: 0.05),
                ScenarioPhase(ticks: 12, drift: 0.4, aggressorBias: 0.6, vol: 2.8, replenish: 0.1),
                ScenarioPhase(ticks: 18, drift: -0.2, aggressorBias: -0.3, vol: 2),
                ScenarioPhase(ticks: 12, drift: 0, aggressorBias: 0, vol: 1.4),
            ],
            debrief: [
                "News risk is really liquidity risk: the danger is not the direction, it is executing into a book with nothing resting.",
                "Whipsaw happens because neither side has size — price teleports between small prints.",
                "In the Lab this is simulated; real event windows also carry slippage beyond any model shown here.",
            ],
            concept: "Market microstructure"
        ),
    ]

    public static func find(_ id: String) -> MarketScenario? { catalog.first { $0.id == id } }
}
