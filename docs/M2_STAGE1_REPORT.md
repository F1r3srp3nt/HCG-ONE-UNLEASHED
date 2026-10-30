# HCG ONE UNLEASHED — M2 Stage 1 Report: Simulated Trading Account and Order Engine

Date: 2026-10-30 · Branch: `feature/m2-stage1-trading-engine` (from `feature/m2.0-audit-stabilization` @ `9482feb`) · **Not committed.** Awaiting founder review.

Engine rules and assumptions: `TRADING_ENGINE.md`. Decisions raised: `OPEN_DECISIONS.md` ("Status after M2 Stage 1").

## 1. What was implemented

**Engine (`HCGTrading`, new HCGKit target, Foundation + `HCGDomain` only)**
- Simulated account: starting balance, balance (cash), equity, buying power, margin in use, positions, unrealized and realized P&L, commissions and fees, and order, fill, trade and activity history.
- Orders: market buy/sell, limit, stop, cancel, cancel all (per market or all), close position, flatten all, stop-loss, take-profit, bracket (TP and/or SL as tick distances, OCO, follows partial fills), and position protection (replaces existing protection; validated before anything is cancelled).
- Deterministic, bid/ask-aware matching: market orders walk the visible book; marketable limits are capped at their price; resting limits fill at their price (partially on touch, fully on trade-through); stops trigger on the correct side of the book.
- Distinct states: accepted, working, partially filled, filled, cancelled, rejected, each with a user-facing reason where relevant.
- Validation against the instrument registry (tick grid, positive finite prices, stop side) and the risk rules (max order size, worst-case position limit, margin-based buying power).
- No duplicate execution: duplicate client IDs are rejected; each market update is processed once per market; reduce-only orders can never overfill.
- Configurable per-market commission, fees and initial margin, plus slippage, limits and the buying-power check. The starting balance applies at the next reset.
- Account reset, with history cleared.

**Integration (`HCGMarketSim`)**
- The account is part of `SimulationState`, so the market and the account always advance on the same simulated update and clock (`SimulatedClock`: 1 s per update, UTC).
- Session persistence: JSON, atomic, off the main actor. Saved after account changes, periodically while markets run, and on quit. Restored at launch; unreadable or newer files are kept aside and the user is told.
- The M1 market-orders-only broker (`SimulatedAccount.swift`) was removed. Its behaviour is a subset of the new engine.

**App**
- **Trading → Simulate** is now available (it was a "coming in M2" placeholder): quote strip, order ticket with a live preview, account summary, and a blotter (positions with Close and Protect…, working orders with cancel, order history, fills, trades, activity).
- Order Flow's ticket bar uses the new engine (market orders, flatten, position, P&L, equity).
- **Trading** menu: ticket (⇧⌘T), cancel all, flatten all (⌥⇧⌘F), reset account… Reset Simulated Session… now asks for confirmation (it reset immediately before).
- **Settings → Account:** starting balance, slippage, risk limits, buying-power check, per-market commission, fees and margin, with Apply / Revert / Restore Defaults and a confirmed reset.
- A banner reports a restored session, a recovered unreadable file, or a save failure.
- The session is saved before the app quits (`AppDelegate.applicationShouldTerminate`).
- "Simulated" labelling: Simulate's title and subtitle, the ticket's badge and button ("Place simulated buy order"), the quote strip badge, the account panel, every table's empty state, menu item names, confirmations, Settings footers, and About ("Simulated account only").

**Found and fixed during Stage 1 (before they shipped)**
- Protect… would have cancelled the existing stop and target *before* validating the new prices, leaving a position unprotected after a typo. It now validates first (test added).
- Protect… did not replace working bracket orders, so a position could carry two stops. It now replaces them (test added).
- Value-bound text fields on macOS update only when they commit, so ⌘↩ straight after typing could place the previous price. The ticket and Protect… now read the text as typed (helpers tested in two locales).

## 2. Files changed

46 files, +4,170 / −577 lines (`git diff --stat`, new files included).

| Area | Files |
|---|---|
| New engine target | `HCGKit/Sources/HCGTrading/` — `TradingModels.swift`, `AccountConfiguration.swift`, `MarketView.swift`, `TradingAccount.swift`, `TradingFormat.swift` |
| Simulation | `SimulationEngine.swift` (account + clock in state), `SimulationHost.swift` (trading API, autosave, restore), **new** `SessionPersistence.swift`, **deleted** `SimulatedAccount.swift`; `Codable` added in `MarketSimulator`, `OrderBook`, `MarketScenario`, `MarketSnapshot`, `SeededRNG`, `SimulationProfile` |
| Domain / navigation | `Instruments.swift` (`price(fractionalTicks:)`, `CodingKeyRepresentable`), `HCGAppModel/Navigation.swift` (Simulate available) |
| Package / project | `Package.swift` (HCGTrading target + tests), `project.pbxproj` (HCGTrading linked), shared scheme (HCGTradingTests) |
| Tests | **new** `HCGTradingTests/TradingAccountTests.swift`, `HCGTradingTests/TradingFormatTests.swift`, `HCGMarketSimTests/TradingIntegrationTests.swift`; `BrokerAndHostTests.swift` → `SimulationHostTests.swift`; `MarketSimulatorTests.swift`, `NavigationTests.swift` updated |
| App | **new** `App/AppDelegate.swift`, `Components/Confirmation.swift`, `Components/SessionNoticeBanner.swift`, `Features/Settings/AccountSettingsTab.swift`, `Features/Trading/Simulate/` (`SimulateView`, `OrderTicketView`, `AccountSummaryView`, `AccountTablesView`, `ProtectionSheet`); updated `HCGOneUnleashedApp`, `MainWindow`, `AppCommands`, `SettingsView`, `HomeView`, `OrderFlowView`, `SimulatedTicketBar`, `AppInfo` |
| Docs | **new** `TRADING_ENGINE.md`, this report; `OPEN_DECISIONS.md`, `DEVELOPMENT_ROADMAP.md`, `ARCHITECTURE.md`, `README.md` updated |

## 3. What was actually tested

### 3.1 Automated: HCGKit (executed)

Command, from `HCGKit/`, in the official Swift image (Swift 6.2.4, Ubuntu 24.04 container on Linux, `TZ=Europe/Oslo`):

```bash
docker run --rm -e TZ=Europe/Oslo -v "$PWD":/pkg -w /pkg swift:6.2-noble swift test
```

Result: **`✔ Test run with 92 tests in 15 suites passed`**. No compiler warnings in the package build.

| Suite | Tests |
|---|---|
| Trading engine — market orders | 5 |
| Trading engine — limit and stop orders | 5 |
| Trading engine — brackets, stop-loss and take-profit | 7 |
| Trading engine — position accounting | 5 (one parameterized over all four markets) |
| Trading engine — validation, risk and integrity | 7 |
| Ticket price entry and trading formats | 4 |
| Trading on the simulated market (integration, persistence, soak) | 9 |
| Simulation host — playback | 7 |
| Simulation state — one clock | 6 |
| Market simulator (order book; determinism and scenarios) | 13 |
| Instruments, formatting, GEX model, navigation | 24 |

What the trading tests establish, all asserted rather than observed:
- fill prices at bid or ask; book walking to a VWAP; slippage against the trader; the depth-exhausted remainder cancelled;
- limit fills (partial on touch, full on trade-through, marketable limits capped); stop placement rules and triggering;
- bracket OCO, brackets following partial fills, children cancelled with an unfilled entry; protection validation, replacement and removal; an invalid replacement keeps the old protection;
- P&L per tick for every market (contract multipliers); averaging, partial closes and reversals; marking longs at the bid and shorts at the ask; commission and fee attribution; the cash identity;
- rejections leave positions untouched; worst-case position limit; buying-power rejections; the margin preview;
- duplicate IDs and repeated updates never execute twice; reset; configuration validation; starting balance at reset;
- JSON round-trips, exact (account and whole session); a restored session continues identically; determinism of the same inputs;
- orders never change the market path; simulated time; persistence save/load, corrupt-file recovery, newer schema rejected; host autosave and restore across a "relaunch";
- **20,000-update soak** with mixed orders across all markets: cash identity holds, no order is overfilled, history stays within bounds, position limits hold, and reduce-only orders never point the wrong way;
- price entry parses and round-trips in en_US and nb_NO, snapping never traps on NaN, ∞ or 1e300, and simulated time displays in UTC while the machine's zone is Europe/Oslo.

### 3.2 App target (NOT compiled here)

This environment is Linux; Xcode, SwiftUI and AppKit are unavailable. What was done:
- `swiftc -parse` on all 24 app Swift files: **no syntax errors**. This checks syntax only, not types.
- The non-UI helpers the screens rely on were moved into `HCGTrading` so they are compiled and tested above.
- A line-by-line review for Swift 6 isolation and SwiftUI API use. It found and fixed `override init()` in a main-actor `NSObject` subclass (an error in Swift 6), now a lazy property.

**The app has not been built or run.** The first macOS build may surface type-checker errors, most likely in the SwiftUI `Table` builders or bindings. Please send any compiler output and I will fix it.

### 3.3 Not tested
- Any UI interaction, layout, keyboard shortcut, sheet or confirmation dialog.
- Save on quit through AppKit, and the sandbox container path.
- Performance with full histories (5,000 fills) in SwiftUI `Table`.
- Behaviour on macOS 15 vs 26.

## 4. Build status

| Item | Status |
|---|---|
| HCGKit package (Linux, Swift 6.2.4) | **Builds, 92/92 tests pass, 0 warnings** |
| App target (macOS, Xcode) | **Not built here.** Syntax-checked only. Needs the founder's Mac. |
| Xcode project | `HCGTrading` product added to the target's package dependencies and Frameworks phase; `HCGTradingTests` added to the shared scheme. Edited by hand; Xcode has not opened it yet. |

## 5. Known issues and limitations

- Engine limitations L-1 to L-8 in `TRADING_ENGINE.md` §8. The most visible are L-1 (your own orders don't consume liquidity; D-33c proposes a fix) and L-3 (no margin calls; D-35).
- **Settings → Account** fields are value-bound: if you type a value and click Apply without pressing Return or Tab, the last edit may not be included. Apply stays disabled until the change registers. This is low-risk (nothing is placed in the market), but it is listed in the QA checklist.
- Positions show unrealized P&L per frame; the other tables update only when the account changes. Large histories have not been profiled (§3.3).
- Simulated time is UTC and starts at 2026-01-05 14:30 (D-36).
- Branding: the supplied logo and icon are **not installed** (Stage 4, D-31). The temporary DEV icon remains.

## 6. Manual QA checklist (founder's Mac)

Build: open `HCGOneUnleashed.xcodeproj`, scheme **HCGOneUnleashed**, **My Mac**, ⌘R. Run tests: ⌘U (should run HCGDomainTests, HCGMarketSimTests, HCGTradingTests, HCGAppModelTests).

1. **Launch:** the sidebar shows Simulate as available, not dimmed. On first launch there is no restore banner.
2. **Market order:** Simulate → Buy, Market, 1 → Place. The fill price equals the ask shown in the quote strip; the position appears; Balance drops by the commission ($2.50 GC).
3. **Book walk:** a market order larger than the best level (see the "more than N shown" line) fills at a worse average than the best ask.
4. **Limit:** a limit buy at the bid shows "Working"; it fills at exactly the limit when the market reaches it (Fills tab, "Resting").
5. **Stop rules:** a buy stop below the ask → the preview warns, and Place is rejected with the reason in red. A valid stop triggers and fills at market.
6. **Bracket:** turn on Attach, TP 10 / SL 10, market buy. Working shows two orders; when one fills, the other is cancelled ("OCO").
7. **Protect…:** on a position, enter an invalid stop (above the bid for a long) and Apply → error shown, and the existing stop and target are still in Working. Enter valid prices → they replace the bracket orders, so there are not four.
8. **Close / Flatten:** Close on a row; Flatten All (⌥⇧⌘F); Cancel All. The positions and Working tables empty.
9. **Typed price:** type a new limit price and press ⌘↩ immediately, without Return. The order uses the typed price.
10. **Risk:** Settings → Account → max position 2 → Apply; a 3-lot order is rejected with the limit named. Turn the buying-power check on with a $1,000 starting balance and reset → orders are rejected for margin.
11. **Settings → Account:** change the ES commission, press Return, Apply; the next ES fill uses it. Also try clicking Apply without Return (known issue above).
12. **Reset:** Reset Account… asks for confirmation; Cancel does nothing; Reset empties everything and restores the starting balance. Reset Simulated Session… (Simulation menu) also asks.
13. **Persistence:** open a position and a working limit, quit (⌘Q), relaunch. The banner says "Restored…"; the position, working order, history and market prices continue from where they were.
14. **Corrupt file:** quit; replace the contents of `~/Library/Containers/com.hakmicapitalgroup.hcgoneunleashed/Data/Library/Application Support/HCGOneUnleashed/session.json` with `{`; relaunch. The banner explains, a `session.unreadable-….json` file is kept, and a fresh session starts.
15. **Order Flow:** the bottom ticket's Buy/Sell/Flatten change the same account the Simulate screen shows.
16. **Time display:** the quote strip and tables show simulated time labelled UTC, advancing 1 s per update at any speed.
17. **Speed:** at 8× with several working orders, the UI stays responsive. Note any stutter in the Simulate screen.

## 7. Remaining work

**Stage 1 (to close it)**
- Build the app on the founder's Mac and fix any compile errors.
- Founder decisions: D-32 margin values, D-33 / D-33c liquidity, D-35 margin calls.

**Next, only with approval: Stage 2 (charting)**
- Timeframes 1m–1d aggregated from timestamped trade events.
- Indicators SMA/EMA/RSI/MACD/Bollinger/VWAP/ATR, tested against reference data.
- Then Stage 3 (Order Flow workstation), Stage 4 (Command Center Home and branding), Stage 5 (workspaces, skins, multi-window, ⌘K, export, performance).
