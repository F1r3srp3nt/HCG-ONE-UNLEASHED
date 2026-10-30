# HCG ONE UNLEASHED — M1 Implementation Report

Milestone: **M1, native macOS foundation** (docs/DEVELOPMENT_ROADMAP.md).
Branch: `feature/m1-native-macos-foundation` (local, **not committed or pushed**; awaiting founder approval).
Source reference: `F1r3srp3nt/HCG-One` at `b4f0e29`, read-only, unchanged.
Date: 2026-10-30

> **Build status in one line:** the HCGKit core (domain + simulation) was **compiled and tested** with Swift 6.2.4 on Linux. The **macOS app target was not compiled** here: no Xcode or macOS SDK exists in this environment. Its first real build happens on the founder's Mac (§8).

## 1. Implemented components

### HCGKit (local Swift package, Swift 6 language mode)

| Target | What it contains | Platform |
|---|---|---|
| `HCGDomain` | `MarketSymbol`, `InstrumentSpec` (GC, NQ, ES, CL), `PriceFormat`, `HCGEcosystem` product catalog | Foundation only |
| `HCGMarketSim` | `MarketSimulator`, `OrderBook`, `MarketSnapshot`, scenarios (10, ported), `SimulatedAccount` (basic broker), `SimulationState` + `SimulationEngine` (actor), `SimulationHost` (clock, `@MainActor @Observable`), `DepthLadder` / `PriceSeries` panel models, `GEXModel` (ported) | Foundation + Observation. No SwiftUI, AppKit or UIKit. |
| `HCGDesignSystem` | Semantic light/dark/high-contrast colors, typography, panel surface, panel header, eyebrow, button styles (hover/pressed), status badges, simulated-data badge, trading values, sidebar label, wordmark | SwiftUI + AppKit, macOS only. Compiles to an empty module elsewhere. |

### macOS app (`HCGOneUnleashed` target)

| Screen / feature | State |
|---|---|
| Main window: `NavigationSplitView` sidebar (Home · Trading: Learn, Simulate, Order Flow, Market Lab, Progress · HCG: Explore, Projects, HCG Connect · Account: Profile, Client Workspace, Settings). Resizable, minimum 980 × 620, selection and symbol restored per window. | Implemented |
| Home: build notice, four live simulated market cards (click to open in Order Flow), HCG ecosystem catalog, "Your HCG activity" marked "Requires sign-in" | Implemented |
| **Trading → Order Flow:** symbol picker, header strip (last, change, bid, ask, spread in price and ticks, VWAP, volume, running state), candlestick chart (Swift Charts) with bid/ask/last/VWAP lines, DOM ladder sized to the panel height with hover rows and tooltips, resizable `HSplitView`, play/pause, step, speed, basic simulated ticket (market buy/sell/flatten, position, unrealised/realised P&L, equity) | Implemented |
| Menus: **Go** (⌘1–⌘6), **Simulation** (Play/Pause ⇧⌘P, Step ⌥⌘., Faster ⌘], Slower ⌘[, Speed submenu, Market ⌥⌘1–⌥⌘4, Reset), standard View → Sidebar commands; Space toggles playback when Order Flow has focus | Implemented |
| Settings window (⌘,): Simulation tab (default speed, start on launch, DOM depth, reset with confirmation), About tab (version, build type, data, network, account, bundle ID). Account → Settings page opens it. | Implemented |
| Learn, Simulate, Market Lab, Progress, Explore, Projects, HCG Connect, Profile, Client Workspace | **Not implemented.** Each shows an explicit "Not available in this development build" state that says what it depends on. No sample data. |
| Executive Workspace | **Deliberately not listed.** It requires server-verified access, and there is no sign-in (S-05). |
| Temporary app icon | HCG logo on a Mac icon plate with a **"DEV BUILD"** label. **Temporary**; a designed Mac icon is still needed (D-27). |

### Not implemented in M1 (by decision)

Authentication, any network call, Keychain use, HCG Studio, the Website/App switcher, payments, licensing, Sparkle, distribution, telemetry, multi-window trading panels (M2), saved layouts (M2), footprint/tape/heatmap/CVD panels (M2).

## 2. File structure

```
.gitignore                                      new — Xcode/SwiftPM output, secrets and signing material
README.md                                       rewritten — build and test instructions
HCGOneUnleashed.xcodeproj/
  project.pbxproj                               new — objectVersion 77, 1 app target, local package HCGKit
  project.xcworkspace/contents.xcworkspacedata  new
  xcshareddata/xcschemes/HCGOneUnleashed.xcscheme  new — build/run app, test HCGKit test targets
HCGOneUnleashed/                                (file-system synchronized group)
  App/HCGOneUnleashedApp.swift                  @main, WindowGroup, Settings scene, commands
  App/MainWindow.swift                          split view, sidebar, detail routing, build footer
  App/Navigation.swift                          PrimaryArea, SidebarItem, NavigationModel, focus key
  App/AppCommands.swift                         Go and Simulation menus
  App/Preferences.swift                         UserDefaults keys (non-sensitive)
  Components/UnavailableSectionView.swift       honest unavailable states
  Features/Home/HomeView.swift
  Features/Settings/SettingsView.swift          Settings window + Account → Settings page
  Features/Trading/OrderFlow/OrderFlowView.swift
  Features/Trading/OrderFlow/MarketHeaderBar.swift
  Features/Trading/OrderFlow/PriceChartPanel.swift
  Features/Trading/OrderFlow/DepthLadderPanel.swift
  Features/Trading/OrderFlow/SimulatedTicketBar.swift
  Platform/AppInfo.swift
  Resources/Assets.xcassets                     AppIcon (temporary, 10 sizes), AccentColor, HCGLogo
  Resources/HCGOneUnleashed.entitlements        App Sandbox only (no network entitlement)
HCGKit/
  Package.swift                                 swift-tools 6.0, macOS 15, Swift 6 mode
  Sources/HCGDomain/{Instruments,PriceFormat,HCGEcosystem}.swift
  Sources/HCGMarketSim/{SeededRNG,SimulationProfile,OrderBook,MarketScenario,MarketSnapshot,
                        MarketSimulator,SimulatedAccount,SimulationEngine,SimulationHost,
                        PanelModels,GEXModel}.swift
  Sources/HCGDesignSystem/{HCGColor,HCGTypography,HCGComponents}.swift
  Tests/HCGDomainTests/InstrumentTests.swift
  Tests/HCGMarketSimTests/{MarketSimulatorTests,BrokerAndHostTests,GEXModelTests}.swift
docs/M1_IMPLEMENTATION_REPORT.md                new (this file); other docs updated
```

Size: 4,414 lines of Swift (36 files), no third-party dependencies.

**Copied from HCG-One:** `HCGLogo.png` (brand asset) and, with attribution headers, the scenario catalog text, the GEX model, the GEX tests, the SplitMix64 RNG, and instrument specifications. Nothing else was copied: no keys, URLs, test accounts, demo data or configuration.

## 3. Simulation design

```
SimulationHost (@MainActor @Observable)   ← the only object views observe
   │  publishes immutable SimulationFrame (sequence, revision, 4 snapshots, account)
   │  one playback loop: wait(speed.interval) → await engine.advance() → publish
   ▼
SimulationEngine (actor, off the main actor)
   └─ SimulationState (value type): [MarketSymbol: MarketSimulator] + SimulatedAccount
         advance() steps all four markets in lockstep, then sequence += 1
```

- **One clock.** Every market in a frame carries the same `frameSequence`. Chart, DOM, header and ticket render from the same snapshot read once in `OrderFlowView.body`, so connected panels cannot drift apart. Tests: "All markets in a frame share the same clock value", "Chart and DOM models derived from one frame agree".
- **Deterministic.** SplitMix64 seeded per market from the session seed, with no wall-clock time and no `Int.random`. The same seed and the same number of updates give identical state, whether or not playback was paused in between.
- **Integer ticks.** All prices are `Int64` ticks (price = ticks × tick size), so book arithmetic and the spread are exact for every instrument's tick size.
- **Order book.** Each side has 22 contiguous levels, best first. A price move re-centres both sides around one quote. Levels that stay on their side keep their size; new prices receive fresh seeded size. Fills consume the best level, and a depleted level moves the quote.
- **Spread model.**
  - Per-instrument base spread: 1 tick for all four in M1.
  - Per-instrument maximum widening: GC 6, NQ 6, ES 4, CL 8 ticks.
  - Per-instrument sensitivity: GC 1.0, NQ 1.2, ES 0.6, CL 1.3.
  - Widening comes from liquidity pulls, volatility bursts and volatility above 1.5, and decays back to base.
  - These are **simulation parameters chosen for UNLEASHED, not market statistics** (ASSUMPTION about what is realistic; tunable in `SimulationProfile`).
- **Playback.** Play, pause (cancels the loop; an in-flight update still delivers its true frame), `pauseAndWait`, step while paused, speeds 0.25× to 8× (0.5 s per update at 1×, as in HCG ONE), reset. Frames carry a monotonic `revision`, so out-of-order deliveries are dropped.
- **Broker (basic).**
  - Market orders of 1–100 contracts walk the simulated book to a volume-weighted price.
  - Per-instrument commission (from HCG ONE).
  - Signed positions with average price: add, reduce, close and reverse; realised P&L.
  - Unrealised P&L is marked at the bid for longs and the ask for shorts.
  - **User orders do not consume simulated liquidity in M1.** No limit or stop orders yet (M2).

## 4. Bug fixes and defects found

| # | Defect in HCG-One | Evidence | Fix in UNLEASHED |
|---|---|---|---|
| 1 | **Spread widens on every price move** (`MarketEngine.advancePrice`). Removing the best levels and appending next to the worst made GC go 0.10 → 0.30 → 3.50 (20 moves) → 54.70 (400 moves). | Phase 1: Python port of the function (not the Swift code). | `OrderBook` keeps both sides contiguous around one quote. Regression test: GC spread is **exactly** 1 tick (0.10) on every one of 10,000 free-market updates, and price actually moves. |
| 2 | **Aggressor direction sign error.** The move sign test `(aggressor == .buy ? drift : -drift) < 0` left sell-aggressor moves pointing **up** whenever drift was ≤ 0. | Code reading during the port. | A move follows the aggressor's side; against-drift aggressors are absorbed toward the drift 50 % of the time. Test: drift −0.5 ends below the start, drift +0.5 above, on 3 seeds. |
| 3 | **Possible empty ask side** (`askLevels` never refilled on down-moves). | Code reading (not reproduced on iOS). | Both sides are rebuilt to full depth on every reprice. Invariant checked on every update in the soak test. |
| 4 | **Nondeterministic fills** (`Int.random` slippage in `SimBroker.fill`). | Code reading. | Fills priced by walking the seeded book. Deterministic. |
| 5 | **Trade-history P&L attribution** (`SimBroker.open/fill`). Adding to a position overwrote the stored opening commission with only the added contracts' commission, and every partial close attributed the full stored amount to its trade record. Cash itself was not double-charged. | Code reading. | Commission is charged once per fill and P&L is computed per fill; the math is tested. A trade-history view arrives with Simulate (M2). |
| 6 | **Incorrect GEX test expectation.** `extremeInputsDegradeToZeroNotCrash` expected 3 strikes, but `sanitized` restores 10 strikes per side, giving 21. | **Executed:** the ported test failed with `(output.strikes.count → 21) == 3` on Swift 6.2.4. | Expectation corrected to 21; model unchanged. This test could not have passed in HCG ONE as written. |

Fixes 1–6 exist only in UNLEASHED. The iOS app is unchanged, because HCG-One is read-only (D-08).

## 5. Test evidence

**Where:** official Docker image `swift:6.2-noble`, Swift 6.2.4 (swift-6.2.4-RELEASE), x86_64 Linux, run in this session.

Commands:

```bash
cd HCGKit
swift build -c release
swift test
```

**Results (actual output):**
- `swift build -c release` → `Build complete!`
- `swift test` → `✔ Test run with 43 tests in 8 suites passed after 1.962 seconds.`
- 0 compiler warnings.
- The full suite was repeated 5 more times with the same result: 43 tests, 8 suites, all passing.

43 test functions cover **73 executed cases**, because 8 tests are parameterised over the 4 instruments or the 10 scenarios.

| Required coverage | Test(s) | Result |
|---|---|---|
| Instrument tick-size validity | "Every instrument has a positive, finite tick size and point value" ×4; "Tick sizes and tick values match…"; "Prices round-trip through whole ticks" ×4 | Passed |
| Bid below ask | "Bid stays below ask on every update" ×4 (2,000 updates each) | Passed |
| Spread calculation | "Spread equals ask − bid in ticks and in price" ×4 | Passed |
| Order-book price ordering | "Book levels are ordered best-first and contiguous" ×4 | Passed |
| Non-empty valid book sides | "Both book sides stay non-empty with valid sizes" ×4 | Passed |
| Deterministic with fixed seed | "Same seed produces the identical market" ×4; "Different seeds produce different markets"; "Reset restores the opening state of the seed" | Passed |
| Repeatable scenario playback | "Every scenario replays identically" ×10; "Scenario catalog is well-formed" | Passed |
| Pause and resume | "Pause stops the clock and resume continues it"; "Playback with pauses reproduces an uninterrupted run exactly"; "Manual steps advance exactly one update while paused" | Passed |
| No divergence between panels | "All markets in a frame share the same clock value"; "Chart and DOM models derived from one frame agree"; "Loading a scenario affects only its market…" | Passed |
| GC spread regression | "GC spread stays at one 0.10 tick in a calm market (iOS regression)" (10,000 updates) | Passed |
| 10,000-update soak | "10,000-update soak keeps every market valid" (all 4 markets, cycling all 10 scenarios, every invariant every update) | Passed |
| Spread stress behaviour | "Stress widens the spread within limits and it decays back to base" | Passed |
| Broker | 6 tests: fill at ask, book walk, round-trip P&L, reversal, rejections, unrealised marks | Passed |
| Ported GEX tests | 6 tests (one with the corrected expectation, §4 #6) | Passed |

**Not tested:** the SwiftUI app target (views, menus, Settings, layout, light/dark appearance). It has no automated UI tests and was not compiled.

## 6. Build status

| Item | Status | Evidence |
|---|---|---|
| HCGKit `HCGDomain`, `HCGMarketSim` + tests | **Compiled and tested** (Linux, Swift 6.2.4) | §5 |
| HCGKit `HCGDesignSystem` | **Not compiled for macOS.** It compiles as an empty module on Linux; its SwiftUI/AppKit code passed syntax parsing only. | `swiftc -parse` |
| macOS app target (14 Swift files) | **Not compiled.** Syntax-parsed only. Type-checking against the macOS 15 SDK has not happened. | `swiftc -parse`: all files parse |
| `project.pbxproj` | Parsed with an OpenStep parser: 22 objects, every reference resolves, none unused. **Not opened in Xcode.** | `openstep_parser` |
| Scheme, workspace, entitlements, asset catalog JSON | Well-formed (XML/JSON parsed) | Python `xml.dom`, `json` |

**Known build risks** (to be confirmed on the Mac):
- **Local package format.** The project references HCGKit through `XCLocalSwiftPackageReference` + `XCSwiftPackageProductDependency` (product name only). This is hand-written, not Xcode-generated. If Xcode does not resolve the package, remove and re-add it via File → Add Package Dependencies → Add Local…, choosing `HCGKit`.
- **Package test targets in the shared scheme.** The scheme's Test action lists HCGKit's test targets. If `xcodebuild test` does not find them, `cd HCGKit && swift test` runs the same tests.
- **SwiftUI API usage was reviewed by hand, not by the compiler.** The first build may report type errors. They are expected to be small and local.

## 7. Known limitations

- **Unverified app build** (§6).
- **No UI tests, and no visual check** of light or dark appearance.
- **Rendering is not throttled.** Panels redraw on every published frame, up to about 16 per second at 8×. A `TimelineView`-based throttle is planned for M2 (ARCHITECTURE §4.2).
- **All four markets tick continuously**, even when not shown. This is cheap, but unmeasured on a 16 GB Mac.
- **Broker:** market orders only; orders don't affect simulated liquidity; no margin model; the account is not persisted across launches.
- **Simulation state is not persisted.** Every launch starts from the default seed.
- **Spread parameters** are UNLEASHED choices (§3), not calibrated against real markets.
- **Temporary icon** (D-27).
- **Short welcome window (D-06) not implemented.** The app opens straight to Home.
- **Scene restoration** relies on `@SceneStorage`; multiple main windows each keep their own selection.

## 8. Founder actions needed for first launch

1. On the M4 Max, with Xcode 16 or later (26 recommended), check out the branch and open the project (README → "Open and run in Xcode").
2. Press **⌘R** with the HCGOneUnleashed scheme and My Mac. Signing is "Sign to Run Locally"; no team is needed.
3. If the build fails, send the first error lines. If the package isn't found, re-add `HCGKit` as a local package (§6).
4. Run the tests: **⌘U** in Xcode, or `cd HCGKit && swift test`.
5. Review: Order Flow (GC spread should read 0.10 · 1 tick in calm conditions), the menus, Settings, and light and dark appearance (System Settings → Appearance).
6. Decide on commit/push of this branch, CI (D-10), and the open M1 items in docs/OPEN_DECISIONS.md.
