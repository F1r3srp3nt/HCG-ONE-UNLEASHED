# HCG ONE UNLEASHED — M2.0 Test Results

Date: 2026-10-30 · Branch: `feature/m2.0-audit-stabilization` · Working tree, not committed.

## 1. Environment actually used

| Item | Value |
|---|---|
| Machine | Linux x86_64 (cloud container), Docker |
| Toolchain | `swift:6.2-noble` official image, **Swift 6.2.4 (swift-6.2.4-RELEASE)** |
| Xcode / macOS SDK | **Not available.** `xcodebuild` not installed. |

**Consequence:**
- The `HCGDomain`, `HCGMarketSim` and `HCGAppModel` targets and all tests were compiled and executed.
- `HCGDesignSystem` compiles as an empty module on Linux.
- **The macOS app target was not compiled.** Its 15 Swift files and the 3 design-system files were syntax-parsed only.

## 2. Commands and results

### 2.1 Baseline (M1 code, before any M2.0 change)

```bash
cd HCGKit && swift test
```

```
✔ Test run with 43 tests in 8 suites passed after 2.917 seconds.
```

0 compiler warnings.

### 2.2 After M2.0 changes

```bash
cd HCGKit && swift build -c release
```

```
Build complete! (10.27s)
```

```bash
cd HCGKit && swift test
```

```
✔ Test run with 58 tests in 9 suites passed after 9.416 seconds.
```

**Warnings:** 0. One warning from a new test, a redundant `#require`, appeared in an intermediate run and was fixed before this run.

**Repeat runs:** 3 more full runs. All 3: `✔ Test run with 58 tests in 9 suites passed` (10.055 s, 10.297 s, 10.336 s).

### 2.3 Syntax parsing of code that cannot be compiled here

```bash
swiftc -parse <file>   # for each file under HCGOneUnleashed/ and HCGKit/Sources/HCGDesignSystem/
```

```
parsed OK: 18 files
```

This checks syntax only. It does **not** type-check against SwiftUI/AppKit.

### 2.4 Project file validation

The Xcode project was parsed with `openstep_parser`:
- 24 objects;
- every referenced ID resolves; none unused;
- the target links `HCGDomain`, `HCGMarketSim`, `HCGDesignSystem`, `HCGAppModel`.

The scheme XML and asset JSON parse.

## 3. Test inventory (58 tests, 91 executed cases)

9 tests are parameterised: 7 run once per instrument (4 cases each) and 1 once per scenario (10 cases), giving 42 cases; the other 49 run once. 91 cases in total.

New in M2.0 are marked **(new)**.

| Requirement | Tests |
|---|---|
| **Instrument tick sizes** | Every instrument has a positive, finite tick size and point value (×4) · Tick sizes and tick values match the contract specifications · Prices round-trip through whole ticks (×4) · **Tick prices are the closest Double to the exact decimal value (new)** · **Off-tick prices round to the nearest valid tick (×4, new)** · Display decimals cover the tick size · Symbols sort in workstation order |
| **Bid/ask spread consistency** | Bid stays below ask on every update (×4) · Spread equals ask − bid in ticks and in price (×4) · Book levels are ordered best-first and contiguous (×4) · Both book sides stay non-empty with valid sizes (×4) · GC spread stays at one 0.10 tick in a calm market (iOS regression, 10,000 updates) · Stress widens the spread within limits and it decays back to base |
| **Simulation determinism** | Same seed produces the identical market (×4) · Different seeds produce different markets · Every scenario replays identically (×10) · Scenario catalog is well-formed · Reset restores the opening state of the seed · Playback with pauses reproduces an uninterrupted run exactly |
| **Order validation** | Invalid orders are rejected without changing the account · **The full order-size range is accepted at both bounds (new)** · **Orders larger than the visible book are rejected for insufficient liquidity (new)** · A market buy fills at the ask and opens a long · Large orders walk the book to a volume-weighted price · Round trip realises (exit − entry) × quantity × point value · Selling more than the long reverses into a short at the fill price · Unrealised P&L marks longs at the bid and shorts at the ask |
| **Playback controls** | Pause stops the clock and resume continues it · Manual steps advance exactly one update while paused · Speed control is bounded · **A speed change applies to the pending wait immediately (new)** · **Reset keeps playback running when it was running (new)** · Orders and resets publish through the same frame |
| **Navigation / view-model** | **Every destination belongs to exactly one sidebar group or is Home (new)** · **The founder-specified destinations are all present, in order (new)** · **Executive Workspace is never listed without server verification (new)** · **Only implemented destinations are marked available; every other one explains why (new)** · **Go menu: six areas, unique ⌘ digits 1–6… (new)** · **Opening areas and markets updates the selection (new)** · **Restoring saved state accepts valid values and falls back on invalid ones (new)** |
| **Prolonged execution / stability** | 10,000-update soak keeps every market valid · **50,000-update run keeps markets valid with bounded memory (new)** · **Account history stays bounded under sustained order entry (new)** · All markets in a frame share the same clock value · Chart and DOM models derived from one frame agree · Loading a scenario affects only its market and keeps the shared clock · Tape, bars, VWAP and delta are projections of the same trades · Strong negative drift moves price down |
| **Ported GEX model** | 6 tests (one corrected expectation, M1 report §4 #6) |
| **Formatting / catalog** | priceUsesFixedDecimals · changeIsSigned · ticksPluralise · productCatalogHasUniqueIdentifiers |

## 4. Measurements (engine only)

| Measurement | Result | Conditions |
|---|---|---|
| Cost per update, all four markets | about **36 µs** | Release build, 50,000 updates, probe run, Linux x86_64 in Docker |
| Cost per update incl. invariant checks | about **188 µs** | Debug build, the "50,000-update run" test |
| Frame build (`SimulationState.frame()`) | about **3 µs** | Release, 5,000 frames |
| Buffers after 50,000 updates | tape ≤ 200, bars ≤ 160, snapshot trades ≤ 40; fill history ≤ 200 after 1,000 orders | Asserted by tests |
| Price ranges over 50,000 updates (seed 2026) | GC 2644.4–2689.1 · NQ 19,815.00–19,928.25 · ES 5,410.00–5,658.50 · CL 76.15–80.58 | Probe run. Volatility is uniform in ticks (audit SIM-4). |

At 8× (16 updates/s) the engine uses well under 1 % of one core on this machine.

**Not measured:** SwiftUI rendering cost, memory of the running app, and behaviour on Apple Silicon or a 16 GB Mac. These require Instruments on the Mac.

## 5. Not executed (must be done on the Mac)

| Check | How |
|---|---|
| Build the app with the M2.0 changes | `xcodebuild … build` (§6) |
| Run tests through Xcode | ⌘U, or `xcodebuild … test` |
| Visual checks | See the checklist below |
| Instruments profile | Time Profiler + Allocations, 10 minutes at 8× with Order Flow open |

**Manual checklist** (the audit IDs from M1_AUDIT §2):
1. Shrink the window to its minimum with the sidebar open, on Order Flow. The quote strip switches to its compact or minimal layout and is not clipped (OF-1). The ticket bar wraps to two rows (OF-2).
2. Open the toolbar **Speed** menu while the simulation runs. The menu stays open (OF-3).
3. Rest the pointer on the DOM while it moves. The highlight stays under the pointer (OF-4) and the tooltip stays visible (OF-5).
4. Sidebar footer: the two badges are stacked and not clipped (NAV-1).
5. File menu: no Page Setup… or Print…. ⇧⌘P toggles the simulation (CMD-1).
6. Set the speed to 0.25×, then 8×. The market speeds up immediately (SIM-1).
7. Simulation → Reset Simulated Session while running. It keeps running (SIM-2).
8. Switch System Settings → Appearance between Light and Dark, and enable Increase Contrast. All text stays readable.

## 6. Exact Xcode build and run instructions

Requirements: Apple Silicon Mac, macOS 15+, Xcode 16 or later (26 recommended).

```bash
git clone https://github.com/F1r3srp3nt/HCG-ONE-UNLEASHED.git
```
```bash
cd HCG-ONE-UNLEASHED
```
```bash
git checkout feature/m2.0-audit-stabilization
```

The branch above exists on GitHub only after the founder approves a push. Until then, use `main` for the M1 build.

```bash
open HCGOneUnleashed.xcodeproj
```

In Xcode: scheme **HCGOneUnleashed**, destination **My Mac**, **⌘R** to run, **⌘U** to test. M2.0 adds a package product, so if Xcode reports a missing package, use File → Packages → Resolve Package Versions.

Terminal:

```bash
xcodebuild -project HCGOneUnleashed.xcodeproj -scheme HCGOneUnleashed -configuration Debug -destination 'platform=macOS,arch=arm64' build
```
```bash
xcodebuild -project HCGOneUnleashed.xcodeproj -scheme HCGOneUnleashed -destination 'platform=macOS,arch=arm64' test
```
```bash
cd HCGKit && swift test
```
