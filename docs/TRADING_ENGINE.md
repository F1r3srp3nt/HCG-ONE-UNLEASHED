# HCG ONE: UNLEASHED — Simulated Trading Engine

Status: **M2 Stage 1, implemented (2026-10-30); order-flow realism and risk rules added after founder review (2026-10-31)**. Code: `HCGKit/Sources/HCGTrading` (the engine) and `HCGKit/Sources/HCGMarketSim` (clock, markets, persistence). Tests: `HCGKit/Tests/HCGTradingTests`, `HCGKit/Tests/HCGMarketSimTests/TradingIntegrationTests.swift`. Results: `M2_STAGE1_REPORT.md`.

**Design intent (founder, 2026-10-31):** training for mostly advanced traders moving from candlestick charts to order-flow tools. The engine therefore behaves like a real futures order book where it matters to them: queue position at a price, the book being walked, and the risk rules of an evaluation account.

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
| **Limit** | If marketable when placed (buy limit ≥ ask, sell limit ≤ bid), it takes liquidity up to its price, like a market order capped at the limit (slippage never pushes it past the limit). Any remainder **rests** at the limit **with a queue position** (below). |
| **Stop** | Must be beyond the market when placed: buy stop **above the ask**, sell stop **below the bid**. Triggers when the ask reaches a buy stop (ask ≥ stop) or the bid reaches a sell stop (bid ≤ stop), then fills like a market order on that update. It can fill worse than the stop if the market gaps. |
| **Bracket** (on any entry) | Take-profit (limit) and/or stop-loss (stop), given as **tick distances** from the entry's average fill. They wait as `accepted` until the entry fills, then work for the filled quantity, priced from the average fill. They follow later partial fills of the entry. Cancelling an unfilled entry cancels its waiting children. |
| **Close position** | Market order for the whole position, opposite side (role `close`). |
| **Protect position** (stop-loss / take-profit) | Reduce-only OCO pair sized to the current position. It **replaces** every working stop-loss and take-profit on that position, including working bracket orders. Both prices are validated first: if either is invalid, both are rejected and the existing protection stays. Passing neither removes the protection. |
| **Cancel / Cancel all / Flatten all** | Cancel one order, all orders (optionally per market), or cancel everything and close every position. Cancelling never changes a position. |

### Resting limit fills and queue position (D-34)

A working limit fills **at its own price** (maker), in time priority:

- **Queue on arrival.** An order that joins an existing price level waits behind the size displayed there, plus your own earlier orders at that price. An order that improves on the best price is at the front. An order beyond the visible depth (10 levels) joins the back of the queue when its price comes into view. That is a conservative estimate: it assumes the size you then see was there first.
- **Prints work through the queue.** Each update the simulator prints 2–6 trades with price, size and aggressor. Prints at your price from the other side (sellers hitting a buy limit's price) first reduce the queue ahead, and only the excess fills you.
- **Pulled size shortens the queue.** If the displayed size at your price drops below your queue estimate, the estimate drops with it.
- **The market reaching you crosses directly.** If the opposite quote rests at your price, you fill against it, up to its size. A same-side print at your price also crosses directly.
- **Trade-through fills completely:** a print beyond your price, or the opposite quote past it.
- **Touch alone does not fill.** Sitting at the best bid while no trades print there leaves the order unfilled, as in a real queue.
- **Moving a price loses priority.** Bracket take-profits whose price moves with the entry's average fill re-join the queue.

The Working tab shows each limit's estimate ("12 ahead", "front of queue", "queue when in view"), and the ticket previews it before you place the order.

### Shared liquidity within an update (D-33c)

Your own orders share the displayed liquidity of one update. Two market orders sent in the same update cannot both take the same 10 contracts: the second walks deeper. Stops triggered together and touch fills share it too. A new update shows fresh liquidity. Your orders still never change the simulated market path (D-33).

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
2. **Quantity** must be between 1 and the configured maximum order size (default 5).
3. **Prices** must be positive, finite and on the instrument's tick grid. Market orders take no price. Stops must be beyond the market (above).
4. **Bracket** needs at least one leg; distances are at least 1 tick.
5. **Position limit** (default 5 per market): checked against the **worst case**, which is the current position plus every working entry order on one side, plus this order. Reduce-only orders never count.
6. **Buying power** (on by default): the extra worst-case contracts × the instrument's initial margin must not exceed buying power.
7. **Trading lock:** while a risk rule has locked the account (§3a), new orders are rejected with the reason and when trading unlocks.

Unsafe numbers (NaN, ±∞, ≤ 0, ≥ 10⁹) are rejected before any integer tick conversion, so malformed input cannot crash the engine.

## 3a. Account risk rules (D-35), checked after every update and order

| Rule | Default | When it triggers | What happens |
|---|---|---|---|
| **Margin liquidation** | on | Equity below the margin of the open positions | Every position is closed at market and working orders are cancelled. **No lock.** |
| **Trailing drawdown** | $2,000 | Equity ≤ floor. The floor is the equity high minus $2,000, and it **stops trailing at the starting balance**. The high is tracked on every update, including unrealized P&L ("intraday trailing"). | Everything is closed and **trading is locked until the account is reset**, as when an evaluation account fails. |
| **Daily loss limit** | $1,000 | Equity change since the session began ≤ −$1,000 (realized and unrealized) | Everything is closed and **trading is locked until the next session**. Sessions roll over at **22:00 UTC** (17:00 Chicago in daylight time; daylight saving is not modelled). |

Each breach is logged in Activity ("Liquidation", "Trading locked", "Trading unlocked"). The account panel shows session P&L against the limit, the room left to the drawdown floor, and a lock banner. While locked, the ticket is disabled. Changing the rules in Settings does not lift an existing lock; a reset does. Each rule can be switched off.

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
| Intraday margin / contract (simulated) | $1,000 | $1,000 | $500 | $1,000 |

**A $50,000 evaluation-style account** (founder decision 2026-10-31, D-32/D-35): this is the setup most futures traders practise order flow on.
- Rules: max order 5 contracts, max position 5 per market, buying-power check on, $1,000 daily loss limit, $2,000 trailing drawdown, liquidation below margin. Slippage is 0 ticks, because the book walk and the queue already supply realistic execution cost.
- Commissions match HCG ONE's Trading Lab.
- Margins are typical **intraday** day-trading levels, not exchange overnight margins, and are not any broker's figures.
- "Use Evaluation Account Rules" in Settings restores the rules.
- **The starting balance applies at the next account reset.** Costs, slippage and limits apply to new orders and fills immediately.

## 5. Determinism and simulated time

- The engine is a value type with no clock, randomness or I/O of its own. The same requests and market updates always produce the same account (tested).
- Simulated time comes from `SimulatedClock`: the session starts at **2026-01-05 14:30:00 UTC** and each update is **1 simulated second**, whatever the playback speed. Every order, fill, trade and event carries the update's sequence number and simulated time. The app shows simulated time **in UTC**, labelled as such.
- **Orders do not move the market (D-33).** The simulated market path is identical with or without trading (tested). Within one update your orders share its displayed liquidity (D-33c). Each market update is processed at most once per market, and an update whose liquidity an order already used on submission is not processed again.

## 6. Persistence

- The whole session (all four markets, the scenario state, the clock and the account) is saved as JSON to `Application Support/HCGOneUnleashed/session.json`. With the App Sandbox this is inside the app's container (`~/Library/Containers/com.hakmicapitalgroup.hcgoneunleashed/Data/Library/Application Support/`). Markets and account are saved together, so a restored position is never marked against a restarted market.
- **When it is saved:** about one second after any account change; at most every 30 seconds for market-only changes; and when the app quits (quitting waits for the write). Writes are atomic and happen off the main actor.
- **On launch:** a saved session is restored and a banner says so. An unreadable file, or one written by a newer schema version, is moved aside as `session.unreadable-<timestamp>.json` (not deleted), a fresh session starts, and the banner says why.
- File format: `schemaVersion` 1, `accountSchemaVersion` 1, ISO 8601 dates. Sessions saved before the 2026-10-31 additions still load: queue estimates start "when in view", and the session keeps the costs and limits it was saved with. The risk rules start **off** until "Use Evaluation Account Rules" or "Restore Defaults" is applied in Settings → Account. Nothing in it is a credential or account detail; it contains only simulated data.
- **Bounded history:** order history keeps the last 2,000 orders, fills and trades the last 5,000, and the activity log the last 500 events. The oldest entries are dropped first; balances and P&L are unaffected.

## 7. Where the user sees it

| Place | What |
|---|---|
| **Trading → Simulate** | Market picker, quote strip (bid/ask/last, simulated UTC time, tick value), order ticket (side, market/limit/stop, quantity, price with ±tick and use-bid/ask, bracket in ticks with $ per contract), live preview (execution, queue estimate for limits, costs, margin after order, bracket prices, warnings), account summary with risk rules (session P&L vs limit, drawdown room, lock banner), Flatten All, Reset Account… (with confirmation), and the blotter: Positions (close, Protect…), Working (queue position, cancel, cancel per market, cancel all), Orders, Fills, Trades, Activity. |
| **Trading → Order Flow** | Quick ticket bar: market buy/sell, flatten, position, P&L, equity. |
| **Trading menu** | Simulated Order Ticket (⇧⌘T), Cancel All Simulated Orders, Flatten All Simulated Positions (⌥⇧⌘F), Reset Simulated Account… (with confirmation). |
| **Simulation menu** | Reset Simulated Session… (markets and account, with confirmation). |
| **Settings → Account** | Starting balance, slippage, size limits, buying-power check, daily loss limit, trailing drawdown, margin liquidation, "Use Evaluation Account Rules", per-market commission, fees and margin; Apply / Revert / Restore Defaults; Reset Account with These Settings… |

Every one of these carries a "Simulated" label or says "simulated" in its title, help text or confirmation.

## 8. Known limitations (deliberate for Stage 1)

| # | Limitation | Why / next step |
|---|---|---|
| L-1 | Your orders do not change the simulated market across updates: a large order does not leave a hole in the next update's book. | D-33. Within an update liquidity is shared (D-33c). |
| L-2 | The queue is an estimate from displayed size and prints. The simulator has no individual orders (no market-by-order data), so cancellations ahead of you are inferred only when displayed size drops below your estimate. | Good enough for queue intuition. A per-order simulator would be a later project. |
| L-3 | Liquidation uses initial margin; there is no separate maintenance margin, and it closes everything, not the minimum needed. | Simple and predictable for training. |
| L-4 | One aggregated position per market, no hedging (long and short at once). | Standard for futures. |
| L-5 | No time-in-force (all orders are good until cancelled), no stop-limit, trailing stop, OCO between unrelated entries, or order modification (cancel and re-enter instead). | Not in the Stage 1 brief. Modify-order is a good Stage 5 candidate. |
| L-6 | A position protected with Protect… is sized to the position at that moment. If a partially filled entry fills further afterwards, the extra contracts are not protected by that pair. | Re-run Protect… after the entry completes. Bracket orders do follow later fills. |
| L-7 | Commission is charged per fill. A single order that fills in several updates is charged per contract each time (the total equals contracts × rate). | Matches per-contract pricing. |
| L-8 | All four instruments are USD, so the account is USD. There is no currency conversion. | Revisit only if a non-USD instrument is added. |
