# HCG ONE: UNLEASHED — M2 Stage 2 Report: Charting

Date: 2026-11-01 · Branch: `feature/m2-stage2-charting` (from `feature/m2-stage1-trading-engine` @ `fce6d27`) · **Not committed.** Awaiting founder review.

Design and conventions: `CHARTING.md`.

## 1. What was implemented

**`HCGCharting`** is a new HCGKit target that uses Foundation only.
- **Timeframes** 1m, 5m, 15m, 1h, 4h and 1D. Intraday candles align to the UTC clock; 4h and 1D align to the 22:00 UTC futures session open.
- **Candles built from timestamped trade events:**
  - each candle holds OHLC, volume, buy and sell volume (delta), trade count and exact VWAP;
  - trades that arrive out of order are placed in the right candle;
  - history is bounded at 400 candles per timeframe;
  - a trade only changes the forming candle, which keeps it cheap.
- **Indicators:** SMA, EMA, RSI (Wilder), MACD (12/26/9, TA-Lib seeding), Bollinger Bands (20, 2σ population), ATR (Wilder) and session VWAP.
- **Chart model:** the viewport (zoom and pan), price scale, round tick-aligned axis labels, crosshair hit-testing, and per-frame study computation.

**Simulation integration**
- Every simulated trade feeds all six timeframes of its market, with a timestamp inside its simulated second.
- Charts are stored in the session state, so they are saved, restored and deterministic. Older session files load with empty charts.
- **Market history:** a new session first simulates 6 hours (08:30–14:30 UTC) off the main actor, so charts open with candles. Playback waits for it, and Reset Simulated Session rebuilds it. The length is set in Settings → Simulation (none, 1, 3 or 6 hours).
- Loading a scenario restarts that market's chart.

**App**
- **New chart in Trading → Order Flow**, replacing the M1 price chart:
  - timeframe picker; overlays (SMA, two EMAs, Bollinger, session VWAP); lower study (RSI, MACD or ATR);
  - volume coloured by delta;
  - your position and working orders as labelled lines;
  - last-price tag, crosshair and a readout (UTC time, OHLC, volume, delta, indicator values);
  - zoom and pan with a "Latest" button.
  - Chart settings are remembered.
- `HCGCharting` is linked in the Xcode project, and `HCGChartingTests` is in the shared scheme.

**Performance work during the stage.** The first version of chart feeding doubled the cost of each simulated update, because whole dictionaries were copied on every trade. In-place mutation and array storage cut the overhead from +118% to **+45%** (debug build on Linux: about 0.15 ms per update for all four markets). The risk check also no longer builds market views when there are no positions.

## 2. Files changed

24 files, +4,291 / −129 lines (new files included; 2,254 of the added lines are the generated reference fixture).

| Area | Files |
|---|---|
| New target | `HCGKit/Sources/HCGCharting/` — `Timeframe.swift`, `Candles.swift`, `Indicators.swift`, `ChartModel.swift` |
| Simulation | `SimulationEngine.swift` (chart store, feeding, `prepared` history, frame charts), `SimulationHost.swift` (`prepareHistory`, history on reset, playback deferral) |
| Trading | `TradingAccount.swift` (`needsRiskCheck`, a fast path) |
| Package / project | `Package.swift`, `project.pbxproj` (HCGCharting linked), shared scheme (HCGChartingTests) |
| Tests | **new** `HCGChartingTests/` (`ChartingTests`, `ChartModelTests`, `Reference`, generated `ReferenceData`), `HCGMarketSimTests/ChartIntegrationTests.swift` |
| Tools | **new** `HCGKit/Tools/generate_chart_reference.py` |
| App | **new** `CandleChartPanel.swift`, `ChartRenderer.swift`; **removed** `PriceChartPanel.swift`; updated `OrderFlowView`, `AppDelegate`, `Preferences`, `SettingsView` |
| Docs | **new** `CHARTING.md`, this report; roadmap, architecture, open decisions and README updated |

## 3. What was actually tested

### 3.1 Automated (executed)

From `HCGKit/`, in the Swift 6.2.4 Docker image on Linux with `TZ=Europe/Oslo`:

```bash
docker run --rm -e TZ=Europe/Oslo -v "$PWD":/pkg -w /pkg swift:6.2-noble swift test
```

Result: **`✔ Test run with 134 tests in 23 suites passed`**, no compiler warnings. 25 tests are new in this stage:

| Suite | What it proves |
|---|---|
| Charting — timeframes (1) | UTC alignment for 1m–1h; 22:00 UTC session alignment for 4h and 1D; session day boundaries |
| Charting — candles from trades (5) | **Every timeframe equals pandas' resampling of the same 1,500 trades** (OHLC, volume, buy/sell, trades, notional — exactly); a shuffled feed builds identical candles; 5m–1D equal their 1m candles combined; forming vs closed candles; history bound and dropped trades; candle VWAP and delta |
| Charting — indicators against TA-Lib and pandas (8) | SMA20, EMA9, EMA21, RSI14, MACD line, signal and histogram, Bollinger upper, middle and lower, and ATR14 all **match TA-Lib** on 150 candles, element by element; session VWAP **matches pandas** on 1m and 5m and resets at 22:00 UTC; edge cases (short input, flat market) |
| Charting — chart model (6) | live and scrolled viewport, bounds, right-alignment; crosshair hit-testing round-trips; price scale both ways; round tick-aligned axis labels for ES and CL; studies computed only when shown; settings clamp and round-trip |
| Charts on the simulated market (5) | over 15 simulated minutes, all four markets and six timeframes: candle volume = printed volume, close = last trade, ordered and aligned; prepared history opens at 14:30 UTC with the expected candle counts and is deterministic; charts round-trip through the session file, and old files without charts load; a scenario restarts only its market's chart; the host builds history before playback, rebuilds it on reset, and leaves a running session alone |

The reference fixture was regenerated and found byte-identical (SHA-256 `40a3cabf…`), so the reference data is reproducible.

### 3.2 App target (NOT compiled here)

- `swiftc -parse` on all 25 app files: no syntax errors.
- I reviewed the code by hand for SwiftUI and Swift 6 API use, and fixed a tuple-label type mismatch found in the renderer.
- **The chart has never been rendered.** The first Mac build may surface type-checker errors, most likely in `CandleChartPanel` (gestures, bindings) or `ChartRenderer` (GraphicsContext calls). Please send the compiler output.

### 3.3 Not tested

- Visual correctness of the chart: colours, label overlap, light and dark mode.
- Hover, drag, pinch, and the chart's accessibility.
- Rendering performance at 8× speed with 400 candles. Measured simulation cost is in §1; rendering cost is unmeasured.
- History build time in a release build on a Mac.

## 4. Build status

| Item | Status |
|---|---|
| HCGKit (Linux, Swift 6.2.4) | **Builds; 134/134 tests pass; 0 warnings** |
| App target (macOS) | **Not built here.** Parse-checked only. |
| Stage 1 on the founder's Mac | Still unconfirmed; this stage builds on it. |

## 5. Known issues and limitations

See `CHARTING.md` §4. In short:
- the 1D chart fills only as simulated sessions pass;
- indicator periods are not editable in the UI yet;
- there are no drawing tools and no chart trading;
- time is shown in UTC only;
- rendering performance is unmeasured.

Charts make the session file larger. Measured with 7 simulated hours (the 1m history full at 400 candles): **0.70 MB** (a fresh session without history is 12 KB), encoded in 24 ms in a debug build. The file is written off the main actor after account changes and at most every 30 s.

## 6. Manual QA checklist (founder's Mac)

1. **First launch** (or delete `session.json`): the chart shows "Building simulated market history…" briefly, then opens with candles; playback then starts.
2. **Timeframes:** 1m about 360 candles, 5m 72, 15m 24, 1h 7, 4h 3, 1D 1. Candles end at the current simulated time, and the readout shows UTC times.
3. **Live update:** at 1× the last candle grows; at 8× a new 1m candle starts every 60 updates (7.5 s).
4. **Consistency:** the 5m candle's high and low match the highest high and lowest low of its five 1m candles.
5. **Indicators:** toggle each overlay; switch the study between RSI, MACD and ATR. RSI stays between 0 and 100 with 30/70 guides.
6. **Delta volume:** bars are green when buyers dominated and red when sellers did, matching the readout's Δ sign.
7. **Orders on chart:** place a limit and a bracket in Simulate. Dashed lines appear at their prices, and a position line at the average price.
8. **Crosshair:** hovering shows a vertical line and a price tag, and the readout follows the pointer.
9. **Zoom and pan:** use the buttons and a pinch; drag right to look back; "Latest" returns.
10. **Persistence:** quit and relaunch. The same candles return (no new history is built), and the chosen timeframe and overlays are remembered.
11. **Reset Simulated Session:** history is rebuilt, and the account is reset with confirmation.
12. **Settings → Simulation → Market history = None,** then reset: charts start empty and fill from 14:30.
13. **Light and dark mode:** labels are legible and do not overlap at narrow widths.

## 7. Remaining work

**Close Stage 2**
- Build on the Mac and fix any compile errors (Stage 1 and Stage 2 together).
- Look at the chart and tune colours, label density and pane heights.

**Next, only with approval: Stage 3 (Order Flow workstation)**
- Separate window: DOM, time & sales, heatmap from depth snapshots, footprint, volume bubbles, volume profile, CVD.
- All from the same simulation, never inferring depth from OHLC.
- It builds directly on this stage's candles (which carry buy/sell volume) and on the Stage 1 queue model.
