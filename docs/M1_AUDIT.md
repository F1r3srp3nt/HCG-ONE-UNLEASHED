# HCG ONE UNLEASHED — M1 Audit (M2.0)

Date: 2026-10-30 · Branch: `feature/m2.0-audit-stabilization` (from `main` @ `e1b7ec1`) · Not committed.

## How this audit was done

| Source of evidence | Used for |
|---|---|
| **Founder report** (self-reported): the app compiled in Xcode, launched, navigation and Home render, and simulated prices are visible | Baseline: the M1 project format and code compile on macOS |
| **Line-by-line code review** of every app and HCGKit source file | UI behaviour, layout, controls, concurrency |
| **Executed tests and measurements**: Swift 6.2.4, official `swift:6.2-noble` Docker image, Linux x86_64 | Simulation, broker, navigation model, stability, performance of the core |

**Not available here:** Xcode, the macOS SDK, a display. Nothing in this audit was observed on screen. Findings about layout are derived from layout arithmetic and SwiftUI behaviour, and are marked **"by review"** until you confirm them on the Mac.

Legend:
- ✅ works
- 🧩 intentionally incomplete (planned)
- 🐞 defect, fixed in M2.0
- ⚠️ open issue
- 👁 needs visual confirmation on the Mac

---

## 1. Destination-by-destination

| Destination | What works | Intentionally incomplete | Defects found | Controls | Dependencies for completion |
|---|---|---|---|---|---|
| **Home** | ✅ Brand header, build notice, four live simulated market cards (click → Order Flow), HCG product catalog, "requires sign-in" activity panel | 🧩 Authorized activity, notifications | 🐞 HOME-1: the whole page re-rendered on every market update. Only the market cards do now. | Market cards: open Order Flow ✅ | M3 (sign-in) for activity; M5 for notifications |
| **Trading / Learn** | ✅ Honest unavailable page with "Open Order Flow" | 🧩 Lessons (curriculum exists in HCG ONE) | — | "Open Order Flow" ✅ | M2: curriculum port |
| **Trading / Simulate** | ✅ Unavailable page pointing to the basic ticket in Order Flow | 🧩 Full ticket, limit/stop orders, positions, history | — | ✅ | M2.3 (plan §3) |
| **Trading / Order Flow** | ✅ Symbol picker, quote strip, candlesticks with bid/ask/last/VWAP, DOM ladder, resizable split, play/pause/step/speed, market buy/sell/flatten with P&L | 🧩 Footprint, tape, CVD, heatmap, profile panels; detachable windows; saved layouts | 🐞 OF-1 quote strip clipped when narrow · 🐞 OF-2 ticket bar clipped when narrow · 🐞 OF-3 toolbar rebuilt on every update · 🐞 OF-4 DOM hover followed the price instead of the pointer · 🐞 OF-5 DOM tooltips reset every update · ⚠️ OF-6 last-price label can overlap the newest candles 👁 · ⚠️ OF-7 Space toggles playback only when Order Flow has keyboard focus | All toolbar and ticket controls perform their advertised action (by review + host tests). Step is correctly disabled while playing; Flatten while flat. | M2.1, M2.2, M2.4 |
| **Trading / Market Lab** | ✅ Unavailable page | 🧩 Scenario runner and debriefs (10 scenarios already in the engine) | 🐞 COPY-1: the page said scenarios "already run in this build", but there is no way to start one. Reworded. | ✅ | M2: scenario runner UI |
| **Trading / Progress** | ✅ Unavailable page | 🧩 Lesson, quiz and scenario progress | — | ✅ | M2 + local persistence (D-29) |
| **Explore** | ✅ Unavailable page | 🧩 Services and product discovery; no request submission (no endpoint) | — | — | M5; D-07 (request endpoint) |
| **Projects** | ✅ Unavailable page | 🧩 Requires sign-in and an HCG projects service that does not exist | — | — | M3 + backend service |
| **HCG Connect** | ✅ Unavailable page | 🧩 Inbox and messaging | — | — | M3 (sign-in), M5 (Connect API) |
| **Profile** | ✅ Unavailable page; states that the Executive Workspace is never shown from local data | 🧩 Account profile | — | — | M3 (approval required) |
| **Client Workspace** | ✅ Unavailable page | 🧩 Server-authorized web workspace via handoff | — | — | M3 + M4 |
| **Settings** | ✅ Account → Settings page with "Open Settings…"; Settings window: default speed, start on launch, DOM depth, reset with confirmation, About | — | 🐞 SIM-2: Reset left the clock paused with no indication. It now resumes if it was running. | All controls functional (by review); Reset covered by tests | — |

Executive Workspace is **not listed** in the sidebar, by design. It requires server-verified access, and the build has no sign-in (SECURITY_BOUNDARIES S-05). A test now enforces this.

## 2. Cross-cutting findings

| ID | Area | Finding | Evidence | Status |
|---|---|---|---|---|
| **OF-1** | Layout | The quote strip is one fixed row of non-wrapping figures, about 1,050–1,100 pt wide. With the sidebar open, the detail area is about 750 pt at the 980 pt minimum window width and about 1,100 pt at the default size. SwiftUI centres an over-wide `HStack`, so it clipped at **both** edges. | By review (layout arithmetic) 👁 | 🐞 Fixed: `ViewThatFits` chooses full / compact (no VWAP, Volume) / minimal |
| **OF-2** | Layout | The ticket bar (controls + 4 figures + message) is about 1,000–1,280 pt in one row. Same clipping. | By review 👁 | 🐞 Fixed: one row when it fits, otherwise two rows |
| **OF-3** | Performance / UI | `OrderFlowView.body` read the simulation frame, so the **toolbar** (market picker, speed menu) was rebuilt 2–16 times per second. An open toolbar menu can be disturbed by that churn. | By review | 🐞 Fixed: the toolbar shell no longer reads the frame; `OrderFlowPanels` does |
| **OF-4** | Interaction | DOM hover was stored as a *price*. When the book moved under a still pointer, the highlight moved away from the pointer. | By review | 🐞 Fixed: hover tracked by row position (`onContinuousHover`) |
| **OF-5** | Interaction | DOM tooltips contained the live resting size, so the tooltip text changed every update and macOS kept dismissing it. | By review | 🐞 Fixed: stable tooltip text; live size still read by VoiceOver |
| **OF-6** | Visual | The last-price tag is drawn as an overlay at the chart's trailing edge and can cover the newest candles. | By review 👁 | ⚠️ Open (cosmetic; chart rework in M2.2) |
| **OF-7** | Keyboard | Space toggles playback only when Order Flow has focus (click into it first). ⇧⌘P works everywhere. | By review | ⚠️ Open (documented behaviour) |
| **NAV-1** | Layout | The sidebar footer placed two badges side by side (about 245 pt with padding) in a sidebar whose ideal width is 224 pt and minimum 200 pt. | By review 👁 | 🐞 Fixed: badges stacked |
| **CMD-1** | Menus | SwiftUI's standard File menu includes Page Setup… (⇧⌘P), which collides with Play/Pause Simulation (⇧⌘P). | By review (standard menu contents) 👁 | 🐞 Fixed: print items removed (the app has nothing to print) |
| **SIM-1** | Simulation | A speed change only took effect after the pending wait. At 0.25× that is up to 2 s of delay. | **Test** "A speed change applies to the pending wait immediately" | 🐞 Fixed |
| **SIM-2** | Simulation | Reset always left the clock paused. | **Test** "Reset keeps playback running when it was running" | 🐞 Fixed |
| **SIM-3** | Simulation | `InstrumentSpec.price(ticks:)` multiplied by the tick size, so values were inexact (`2652.7000000000003`). Display formatting hid it; comparisons and future persistence would not. | **Measured** in a probe run; **test** "Tick prices are the closest Double…" | 🐞 Fixed: divide by ticks-per-unit; added `roundedToTick` |
| **SIM-4** | Model tuning | Volatility is identical **in ticks** for every instrument (about 1.41 ticks of mean absolute move per update; inherited from HCG ONE). Over 50,000 updates CL ranged about 5.7 %, ES 4.5 %, GC 1.7 %, NQ 0.6 %. | **Measured** | ⚠️ Not a bug. A tuning decision (D-28). |
| **COPY-1** | Honesty | The Market Lab page implied scenarios could be run. | By review | 🐞 Fixed |
| **HOME-1** | Performance | The whole Home page re-rendered per market update. | By review | 🐞 Fixed (isolated `SimulatedMarketsSection`) |
| **ARCH-1** | Testability | Navigation types lived in the app target and could not be unit-tested. | — | 🐞 Fixed: moved to new `HCGAppModel` target with 7 tests |
| **BG-1** | Resources | The simulation keeps running when every window is closed. The app stays alive on macOS; cost is about 36 µs per update. | Measured cost | ⚠️ Open, low impact. Option: pause when no window is visible (M2.6). |

No crashes were found. The only intentional trap is `SimulationFrame[symbol]`'s precondition for a market that does not exist; all four markets always exist, and the 10,000- and 50,000-update runs found no invalid state.

## 3. Simulation verification

| Check | Result | Evidence |
|---|---|---|
| GC, NQ, ES, CL definitions | ✅ GC 0.10 / $10 per tick, NQ 0.25 / $5, ES 0.25 / $12.50, CL 0.01 / $10 | Tests (executed) |
| Tick sizes and price rounding | 🐞 → ✅ exact tick prices; nearest-tick rounding | 2 new tests ×4 instruments (executed) |
| Bid/ask consistency | ✅ bid < ask on every update | Tests (executed) |
| Spread calculations | ✅ spread = ask − bid in ticks and price; calm GC exactly 0.10 for 10,000 updates; stress widening bounded and decaying | Tests (executed) |
| Deterministic behaviour | ✅ same seed, same market; scenario replays identical; pauses do not change results | Tests (executed) |
| Pause, resume, speed | 🐞 → ✅ (SIM-1, SIM-2 fixed) | Host tests with the real playback loop (executed) |
| Order Flow updates | ✅ every panel reads one snapshot per frame (one clock) | Tests on the panel models (executed); views by review |
| Simulated order entry | ✅ bounds 1–100, rejections leave the account untouched, thin-book liquidity rejection, P&L math, reversal | Tests (executed) |
| Memory during sustained simulation | ✅ tape ≤ 200, bars ≤ 160, snapshot trades ≤ 40, fill history ≤ 200 after 50,000 updates and 1,000 orders | Tests (executed) |
| CPU during sustained simulation (engine only) | ✅ about 36 µs per update for all four markets (release, Linux x86_64); about 190 µs per update in debug including per-update invariant checks; frame build about 3 µs | Measured. **The Mac's rendering cost is not measured** (needs Instruments). |

All market data remains simulated and labelled ("Simulated data" badge, "Simulated" subtitle, tooltips). No market-data connectivity was added.

## 4. Remaining known issues

1. **The M2.0 changes to the app target have not been compiled.** The founder's build covered M1. All 18 app and design-system files parse.
2. OF-6, OF-7, BG-1 (above).
3. **Untested by automation:** visual layout, light/dark/high-contrast appearance, menu behaviour, window resizing. These need a manual check on the Mac (M2_TEST_RESULTS §4).
4. **Not built:** the welcome window (D-06), UI tests, render throttling, persistence of the simulated account and layouts.
5. **Volatility and spread model tuning** (SIM-4, D-28).

## 5. Branding assessment

### Present in the repository

| Asset | Location | Assessment |
|---|---|---|
| `AppIcon` (10 PNG sizes, 16–1024 px) | `HCGOneUnleashed/Resources/Assets.xcassets/AppIcon.appiconset/` | **Temporary.** Generated in M1 from the HCG logo on a dark plate with a "DEV BUILD" label. Not approved artwork. |
| `HCGLogo` (1024 × 1024 PNG, silver on solid black, no transparency) | `…/Assets.xcassets/HCGLogo.imageset/` | Hakmi Capital Group logo from HCG ONE. In light appearance it reads as a black tile. Not the UNLEASHED brand. |
| `AccentColor` | `…/Assets.xcassets/AccentColor.colorset/` | Graphite (light) / silver (dark), matching HCG ONE |
| Wordmark | Typeset in code (`HCGWordmark`: serif "HCG ONE" + tracked "UNLEASHED") | Placeholder typography, not approved artwork |

**The approved futuristic HCG ONE: UNLEASHED branding is not in the repository.** No assets were invented.

### Prepared in M2.0

`HCGOneUnleashed/Components/BrandMark.swift` defines `BrandAsset` names plus `BrandMark` and `BrandWordmark` views. They show approved artwork **automatically when it is installed under the names below**, and fall back to the current logo and text wordmark otherwise. Home and Settings → About use them. No code change is needed when the assets arrive.

### Required assets and where to install them

| Asset | Format | Install as | Notes |
|---|---|---|---|
| **App icon** (macOS 15+) | 1024 × 1024 master on the macOS icon grid (rounded-rectangle plate, transparent outside), exported at 16, 32, 128, 256, 512 pt @1x/@2x | Replace the PNGs in `Resources/Assets.xcassets/AppIcon.appiconset/` and keep the file names in `Contents.json` | Removes the "DEV BUILD" icon |
| **App icon for macOS 26 "Liquid Glass"** (optional) | Icon Composer `.icon` file | Add to the `HCGOneUnleashed/` folder; set **App Icon** in the target to its name | ASSUMPTION to verify in Xcode 26: how it coexists with the asset-catalog icon used by macOS 15 |
| **UNLEASHED mark** | Vector PDF (or SVG) with transparent background; separate light/dark variants if the artwork needs them | New image set `Resources/Assets.xcassets/HCGUnleashedMark.imageset` with **Preserve Vector Data** on; Appearances "Any, Dark" if two variants | Used by `BrandMark` (Home, About) |
| **UNLEASHED wordmark** | Horizontal vector PDF/SVG, transparent background, light/dark variants | `Resources/Assets.xcassets/HCGUnleashedWordmark.imageset` | Used by `BrandWordmark` |
| **Brand colours** | Hex values for primary, accent and any glow/highlight colours, for light and dark | Provided as a list; applied in `HCGKit/Sources/HCGDesignSystem/HCGColor.swift` | Required for the "futuristic" Command Center (M2.5) |
| **Typography** (if the brand uses a custom typeface) | Font files with a desktop app-embedding licence | `HCGOneUnleashed/Resources/Fonts/` + `ATSApplicationFontsPath` | Licence must allow app embedding |

**Product name punctuation:** the brief writes **"HCG ONE: UNLEASHED"**, while the app currently shows "HCG ONE UNLEASHED" (bundle display name, wordmark, About). This is a founder decision (D-30). Changing it touches `INFOPLIST_KEY_CFBundleDisplayName`, `HCGEcosystem.productName`, `HCGWordmark` and the window title.
