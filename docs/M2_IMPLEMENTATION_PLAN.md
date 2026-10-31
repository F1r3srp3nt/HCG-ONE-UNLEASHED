# HCG ONE: UNLEASHED — M2 Implementation Plan

Status: **PROPOSAL for founder review. Not started. Nothing in this plan is implemented until the founder authorizes it.**
Baseline: M1 plus the M2.0 stabilization (`docs/M1_AUDIT.md`).

**Ground rules for all of M2:**
- Simulated data only, clearly labelled.
- No sign-in, network, licensing or payments; those remain M3+ and need separate approval.
- Each sub-milestone ends with executed tests and a founder build on the Mac.

## Recommended order

| Step | Area (brief numbering) | Why this order | Size |
|---|---|---|---|
| **M2.1** | 3. Simulated account, orders and positions (domain) | Everything else displays or drives it | M |
| **M2.2** | 1. Functional demo trading (Simulate UI) | First complete user workflow on top of M2.1 | M |
| **M2.3** | 2. Candlestick charting and indicators | Independent of orders; feeds the workstation | M–L |
| **M2.4** | 4. Independent Order Flow workstation | Needs M2.3 panels and the render throttle | L |
| **M2.5** | 6. Saved workspaces and user preferences | Persists what M2.1–M2.4 create | M |
| **M2.6** | 5. Futuristic HCG Command Center | **Blocked on approved branding assets** (D-31) and naming (D-30) | M |

S/M/L are relative sizes, not time estimates.

---

## M2.1 — Simulated account, orders and positions (area 3)

**Goal:** a complete, deterministic simulated broker model.

**Reuse:**
- `SimulatedAccount` and `Position` (market orders, average price, reversal, P&L).
- `SimulationState.submit` / `flatten`, and the `revision` ordering.
- The iOS `SimBroker` semantics for limit/stop triggers and take-profit/stop-loss (read-only reference: `HCG-One/ios-hcg/HCGONE/TradingLab/SimBroker.swift`). Its defects are already identified (M1 report §4).

**Gaps to build:**
- **Working orders.** Limit, stop and stop-limit with IDs, a lifecycle (working → filled / cancelled / rejected) and cancel/modify. They are evaluated inside `SimulationState.advance()`, so fills stay deterministic.
- **Bracket protection:** take-profit and stop-loss attached to a position.
- **Trade history:** round trips with entry, exit, commission, net P&L, MAE/MFE (port the iOS idea, fixing the commission attribution).
- **Account statistics:** equity curve (bounded), win rate, average win/loss, profit factor.
- **Margin:** a simple per-contract initial margin to block unrealistic size. Values are a founder decision (D-32).
- **Decision (D-33):** whether user orders consume simulated liquidity (more realistic, but it changes the market for the user).

**Tests:**
- deterministic limit/stop triggering at exact ticks;
- gap-through fills;
- cancel never touches positions;
- take-profit/stop-loss precedence;
- statistics math against hand-computed fixtures;
- bounded history.

**Acceptance:** all broker tests pass; a 50,000-update soak with random orders keeps account invariants (cash = start + realised − commissions).

## M2.2 — Functional demo trading (area 1)

**Goal:** Trading → Simulate becomes a working simulated trading screen.

**Reuse:**
- M2.1 model;
- `SimulatedTicketBar` patterns, `TradingStat`, `HCGButtonStyle`, `PriceFormat`;
- the Order Flow snapshot pipeline.

**Gaps to build:**
- Ticket with order type, quantity, limit/stop price (tick-snapped with `roundedToTick`), optional take-profit/stop-loss, and a **risk preview** (money at risk from stop distance).
- Tables, with sorting and context menus: positions, working orders, fills, trade history.
- Account summary: equity, cash, realised/unrealised, margin used.
- Account reset, with confirmation.
- Optional order hotkeys: **opt-in, off by default** (D-20).

**Tests:** view-model tests for ticket validation (tick snapping, side vs trigger price, risk calculation) in a testable target; manual UI checklist.

**Acceptance:** a user can open, protect, scale and close positions on all four markets; every rejection explains itself; nothing claims real execution.

## M2.3 — Candlestick charting and indicators (area 2)

**Goal:** a professional chart panel.

**Reuse:**
- `PriceBar` / `PriceSeries`, the current Swift Charts candles;
- iOS `CVDChart`, `VolumeProfileChart` and the `valueArea()` algorithm (reference).

**Gaps to build:**
- **Indicator engine** in `HCGMarketSim`: pure, tested functions for SMA, EMA, VWAP bands, Bollinger Bands, session high/low, volume profile with point of control and value area, cumulative delta.
- **Timeframes** by bar aggregation (10 / 30 / 60 updates per bar).
- **Longer history:** the bar cap goes from 160 to a configurable 1,000–2,000, with a memory test.
- **Interaction:** zoom and pan (scroll and trackpad), crosshair with OHLC and volume readout, volume and delta sub-panes.
- **Rendering decision:** keep Swift Charts or move candles to `Canvas` if profiling shows Charts is too slow at 8× with indicators. Measure first, on a 16 GB Mac (D-21).
- **Render throttling** (`TimelineView`), capped at the display refresh rate.
- Fix OF-6 (last-price tag placement).

**Tests:** indicator math against reference vectors; aggregation correctness; performance budget test for the indicator pass.

**Acceptance:** smooth at 8× with 3 indicators on the 16 GB reference machine (measured with Instruments).

## M2.4 — Independent Order Flow workstation (area 4)

**Goal:** the multi-panel, multi-window simulated workstation (ARCHITECTURE §4).

**Reuse:**
- `SimulationHost` (one clock for every window);
- `DepthLadder`, `PriceSeries`, `MarketHeaderBar`, the DOM and chart panels;
- the `ViewThatFits` patterns from M2.0.

**Gaps to build:**
- **Layout tree** (`LayoutNode`: panel / split), resizable nested splits.
- **Panel kinds:** Chart, DOM, **Footprint**, **Time & Sales (tape)**, **CVD**, **Heatmap**, **Volume Profile**, Ticket.
- **Simulator extensions:**
  - per-price bid/ask volume in bars (footprint);
  - a longer trade window in snapshots (tape);
  - liquidity bands (port the iOS `evolveBands` idea; heatmap).
- **Detachable panel windows:** `WindowGroup(for: PanelDescriptor.self)`, each bound to a symbol.
- **Optional:** tick only markets with an open panel or position (if profiling says so).
- Keyboard: panel focus cycling, per-panel shortcuts; Space works in any focused workstation panel (fixes OF-7).

**Tests:**
- layout-tree operations (split, close, move) and Codable round-trip;
- panel models derived from one frame agree (extend the existing divergence test);
- footprint volume = tape volume per bar.

**Acceptance:** 4+ windows across 2 symbols at 1×–8× within the ARCHITECTURE §6 budgets, **measured on 16 GB**.

## M2.5 — Saved workspaces and user preferences (area 6)

**Goal:** the workstation and app remember the user's setup, locally.

**Reuse:**
- `@AppStorage` preferences (speed, start on launch, DOM depth);
- `@SceneStorage` (sidebar, symbol);
- `NavigationModel.restore`.

**Gaps to build:**
- **`WorkspaceStore`:** named layouts (M2.4 layout tree) as versioned JSON in Application Support (sandbox container). Create, rename, duplicate, delete, set default, restore open windows on launch.
- **Preferences model:** default symbol, speed, DOM depth, chart defaults, indicator presets, start-on-launch, pause-in-background (addresses BG-1).
- **Persistence of the simulated account and progress** (D-29).
- **Corruption handling:** an unreadable file falls back to defaults and is kept aside, never silently deleted.

**Tests:** Codable round-trip, schema migration, corrupted-file fallback, file locations inside the sandbox container.

**Acceptance:** quit and relaunch restores layouts, windows, preferences and the simulated account exactly.

## M2.6 — Futuristic HCG Command Center (area 5)

**Goal:** a branded command surface: the new Home or a dedicated window, in the approved futuristic style.

**Content limits:** only what exists locally.
- Simulated market overview;
- simulated account summary;
- workstation and layout launcher;
- learning progress;
- the HCG product family;
- build/system status.

**No fake activity, news or server data.** Executive or ERP content appears only after M3/M4 with server verification.

**Reuse:**
- Home sections, `BrandMark` / `BrandWordmark` (auto-use approved assets);
- `HCGDesignSystem` tokens;
- the `ModuleDescriptor` idea (ARCHITECTURE §3.4).

**Gaps to build:**
- tile/grid layout with live simulated tiles;
- a **command palette (⌘K)** to jump to any destination, market or layout;
- motion design within macOS accessibility settings (Reduce Motion, Increase Contrast);
- a design-system extension (glow/emphasis tokens) **from the approved brand colours**.

**Blocked on:** approved branding assets and colours (D-31) and the product-name punctuation (D-30).

**Tests:** command-palette search ranking (testable model); Reduce Motion respected (manual checklist).

---

## Cross-cutting work in M2

- **Performance budgets:** measured with Instruments on the M4 Max **and** a 16 GB Apple Silicon Mac (D-21) at each step from M2.3.
- **UI test target:** smoke tests for launch, navigation and Order Flow controls. Runs only on the Mac or CI (D-10).
- **CI:** a macOS build-and-test workflow, only with approval (macOS runner minutes on a private repo may be billed).
- **Documentation:** each sub-milestone updates M2_TEST_RESULTS and the roadmap.

## Decisions needed before M2.1

| ID | Decision |
|---|---|
| D-20 | Order hotkeys (recommended: opt-in) |
| D-21 | 16 GB test hardware |
| D-28 | Spread and **volatility** model tuning (volatility is currently uniform in ticks; see audit SIM-4) |
| D-29 | Persist the simulated account and progress |
| D-32 (new) | Simulated margin per contract, or no margin model |
| D-33 (new) | Whether user orders consume simulated liquidity |
| D-30, D-31 | Name punctuation and branding assets (needed by M2.6) |
