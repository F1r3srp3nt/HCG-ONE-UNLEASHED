# HCG ONE UNLEASHED — Simulated Trading Engine

Status: **M2 Stage 1, implemented (2026-10-30)**. Code: `HCGKit/Sources/HCGTrading` (the engine) and `HCGKit/Sources/HCGMarketSim` (clock, markets, persistence). Tests: `HCGKit/Tests/HCGTradingTests`, `HCGKit/Tests/HCGMarketSimTests/TradingIntegrationTests.swift`. Results: `M2_STAGE1_REPORT.md`.

**Everything here is simulated.** No order, fill or position is ever sent to an exchange, broker, HCG service or any network. Prices come from the app's own simulated markets. Margins, commissions and fees are configurable simulation values, not exchange or broker figures.

## 1. Where it sits

```
SimulationHost  (@MainActor @Observable, app-facing; publishes frames, autosaves)
  └─ SimulationEngine  (actor: all work off the main actor)
       └─ SimulationState  (value type: one clock, four markets, one account)
            ├─ markets: [MarketSymbol: MarketSimulator]   HCGMarketSim
            └─ account: TradingAccount                    HCGTrading
```

- `HCGTrading` imports Foundation and `HCGDomain` only. It knows nothing about the simulator: each call receives a `MarketView` (bid, ask, last, visible depth, sequence and simulated time for one market).
- One clock. `SimulationState.advance()` moves every market one update, then lets the account process the markets that have working orders. Market data and account always come from the same update, and the UI receives both in the same `SimulationFrame`.
- **Instrument registry:** `InstrumentSpec.spec(for:)` in `HCGDomain` is the single source for tick size, point value, currency and decimals. The engine, the simulator and every screen read it.

| Market | Tick | Tick value | Point value |
|---|---|---|---|
| GC | 0.10 | $10.00 | $100 |
| NQ | 0.25 | $5.00 | $20 |
| ES | 0.25 | $12.50 | $50 |
| CL | 0.01 | $10.00 | $1,000 |

## 2. Orders

| Request | Behaviour |
|---|---|
| **Market** buy/sell | Fills immediately against the opposite side of the visible book, best price first, as one volume-weighted fill. Configured slippage is then added against the trader. Any quantity beyond the visible depth is **cancelled** ("Not enough simulated liquidity"); market orders never rest. |
| **Limit** | If marketable when placed (buy limit ≥ ask, sell limit ≤ bid), it takes liquidity up to its price, like a market order capped at the limit (slippage never pushes it past the limit). Any remainder **rests** at the limit. |
| **Stop** | Must be beyond the market when placed: buy stop **above the ask**, sell stop **below the bid**. Triggers when the ask reaches a buy stop (ask ≥ stop) or the bid reaches a sell stop (bid ≤ stop), then fills like a market order on that update. It can fill worse than the stop if the market gaps. |
| **Bracket** (on any entry) | Take-profit (limit) and/or stop-loss (stop), given as **tick distances** from the entry's average fill. They wait as `accepted` until the entry fills, then work for the filled quantity, priced from the average fill. They follow later partial fills of the entry. Cancelling an unfilled entry cancels its waiting children. |
| **Close position** | Market order for the whole position, opposite side (role `close`). |
| **Protect position** (stop-loss / take-profit) | Reduce-only OCO pair sized to the current position. It **replaces** every working stop-loss and take-profit on that position, including working bracket orders. Both prices are validated first: if either is invalid, both are rejected and the existing protection stays. Passing neither removes the protection. |
| **Cancel / Cancel all / Flatten all** | Cancel one order, all orders (optionally per market), or cancel everything and close every position. Cancelling never changes a position. |

### Resting limit fills (maker)

A working limit fills **at its own price**:
- **touch** (the opposite best price equals the limit): up to the size shown at that best level, so it may fill partially;
- **trade-through** (the opposite best price moves past the limit): fully.

### Reduce-only rules

Take-profit, stop-loss and close orders never add to or reverse a position. They are capped at the open quantity on every fill. When the position shrinks they are resized, and when it closes they are cancelled ("Position closed"). When one order of an OCO pair fills completely, the other is cancelled.

### Order states

| State | Meaning |
|---|---|
| `accepted` | Validated and stored, not yet active: a bracket child waiting for its entry. Shown as "Waiting for entry fill". |
| `working` | Active; may fill on a later update. |
| `partiallyFilled` | Some quantity filled; the rest still works. |
| `filled` | Final. |
| `cancelled` | Final. Carries a reason (user, OCO, position closed, not enough liquidity, replaced). |
| `rejected` | Final. Never active. Carries the validation reason shown to the user. |

## 3. Validation and risk (checked on every submission)

1. **Duplicate client order ID** (the last 2,000 IDs are remembered) → rejected. The ticket also disables its button until the engine answers, so one click places one order.
2. **Quantity** must be between 1 and the configured maximum order size (default 100).
3. **Prices** must be positive, finite and on the instrument's tick grid. Market orders take no price. Stops must be beyond the market (above).
4. **Bracket** needs at least one leg; distances are at least 1 tick.
5. **Position limit** (default 50 per market): checked against the **worst case**, which is the current position plus every working entry order on one side, plus this order. Reduce-only orders never count.
6. **Buying power** (on by default): the extra worst-case contracts × the instrument's initial margin must not exceed buying power.

Unsafe numbers (NaN, ±∞, ≤ 0, ≥ 10⁹) are rejected before any integer tick conversion, so malformed input cannot crash the engine.

## 4. Account values

| Value | Definition |
|---|---|
| Balance (cash) | starting balance + realized P&L − commissions − fees |
| Unrealized P&L | per position: quantity × (mark − average price) × point value. **Longs are marked at the bid, shorts at the ask**, the price the position could be closed at now. |
| Equity | balance + unrealized P&L |
| Margin in use | Σ worst-case contracts per market × initial margin per contract |
| Buying power | equity − margin in use (can go negative; see §8) |
| Realized P&L | gross, before costs. Each fill records the P&L it realized. |
| Trade record | one per closed quantity: direction, entry/exit prices and times, gross P&L, attributed costs (entry costs pro rata + exit costs), net P&L |

Positions are one aggregated position per market, with a volume-weighted average price. Adding averages in; reducing realizes P&L at the average; an order larger than the position reverses it, and the remainder opens at the fill price.

### Defaults (`AccountConfiguration.standard`, all editable in Settings → Account)

| | GC | NQ | ES | CL |
|---|---|---|---|---|
| Commission / contract / fill | $2.50 | $2.00 | $2.00 | $2.50 |
| Fees / contract / fill | $0 | $0 | $0 | $0 |
| Initial margin / contract (simulated) | $10,000 | $20,000 | $15,000 | $6,000 |

Starting balance $50,000 · slippage 0 ticks · max order 100 · max position 50 per market · buying-power check on. The commissions match HCG ONE's Trading Lab. The margins are round placeholder values pending founder decision D-32. **The starting balance applies at the next account reset**; costs, slippage and limits apply to new orders and fills immediately.

## 5. Determinism and simulated time

- The engine is a value type with no clock, randomness or I/O of its own. The same requests and market updates always produce the same account (tested).
- Simulated time comes from `SimulatedClock`: the session starts at **2026-01-05 14:30:00 UTC** and each update is **1 simulated second**, whatever the playback speed. Every order, fill, trade and event carries the update's sequence number and simulated time. The app shows simulated time **in UTC**, labelled as such.
- **Orders do not move the market (D-33, current behaviour).** The simulated market path is identical with or without trading (tested). Each market update is processed at most once per market, and an update whose liquidity an order already used on submission is not processed again.

## 6. Persistence

- The whole session (all four markets, the scenario state, the clock and the account) is saved as JSON to `Application Support/HCGOneUnleashed/session.json`. With the App Sandbox this is inside the app's container (`~/Library/Containers/com.hakmicapitalgroup.hcgoneunleashed/Data/Library/Application Support/`). Markets and account are saved together, so a restored position is never marked against a restarted market.
- **When it is saved:** about one second after any account change; at most every 30 seconds for market-only changes; and when the app quits (quitting waits for the write). Writes are atomic and happen off the main actor.
- **On launch:** a saved session is restored and a banner says so. An unreadable file, or one written by a newer schema version, is moved aside as `session.unreadable-<timestamp>.json` (not deleted), a fresh session starts, and the banner says why.
- File format: `schemaVersion` 1, `accountSchemaVersion` 1, ISO 8601 dates. Nothing in it is a credential or account detail; it contains only simulated data.
- **Bounded history:** order history keeps the last 2,000 orders, fills and trades the last 5,000, and the activity log the last 500 events. The oldest entries are dropped first; balances and P&L are unaffected.

## 7. Where the user sees it

| Place | What |
|---|---|
| **Trading → Simulate** | Market picker, quote strip (bid/ask/last, simulated UTC time, tick value), order ticket (side, market/limit/stop, quantity, price with ±tick and use-bid/ask, bracket in ticks with $ per contract), live preview (execution, costs, margin after order, bracket prices, warnings), account summary, Flatten All, Reset Account… (with confirmation), and the blotter: Positions (close, Protect…), Working (cancel, cancel per market, cancel all), Orders, Fills, Trades, Activity. |
| **Trading → Order Flow** | Quick ticket bar: market buy/sell, flatten, position, P&L, equity. |
| **Trading menu** | Simulated Order Ticket (⇧⌘T), Cancel All Simulated Orders, Flatten All Simulated Positions (⌥⇧⌘F), Reset Simulated Account… (with confirmation). |
| **Simulation menu** | Reset Simulated Session… (markets and account, with confirmation). |
| **Settings → Account** | Starting balance, slippage, risk limits, buying-power check, per-market commission, fees and margin; Apply / Revert / Restore Defaults; Reset Account with These Settings… |

Every one of these carries a "Simulated" label or says "simulated" in its title, help text or confirmation.

## 8. Known limitations (deliberate for Stage 1)

| # | Limitation | Why / next step |
|---|---|---|
| L-1 | **Own orders do not consume simulated liquidity.** Two of your orders at the same price in the same update can each fill against the same displayed size, and repeated market orders while paused all see the same book. | Follows D-33 "No". A middle option is proposed in `OPEN_DECISIONS.md` (D-33c): orders consume displayed size within an update without changing the market path. |
| L-2 | No queue position for resting limits: a limit at the touch may fill up to the full displayed size at once. | Needs a queue model (D-34); proposed for Stage 3 alongside the DOM. |
| L-3 | **No margin calls or auto-liquidation.** If losses push buying power below zero, only new risk-increasing orders are rejected. | Founder decision (D-35 in `OPEN_DECISIONS.md`). |
| L-4 | One aggregated position per market, no hedging (long and short at once). | Standard for futures. |
| L-5 | No time-in-force (all orders are good until cancelled), no stop-limit, trailing stop, OCO between unrelated entries, or order modification (cancel and re-enter instead). | Not in the Stage 1 brief. Modify-order is a good Stage 5 candidate. |
| L-6 | A position protected with Protect… is sized to the position at that moment. If a partially filled entry fills further afterwards, the extra contracts are not protected by that pair. | Re-run Protect… after the entry completes. Bracket orders do follow later fills. |
| L-7 | Commission is charged per fill. A single order that fills in several updates is charged per contract each time (the total equals contracts × rate). | Matches per-contract pricing. |
| L-8 | All four instruments are USD, so the account is USD. There is no currency conversion. | Revisit only if a non-USD instrument is added. |
