# HCG ONE UNLEASHED — Architecture

Status: **Phase 1 baseline, updated after M1 (2026-10-30).** §9 records what M1 actually built and where it deviates. Sections 1–8 remain the plan; anything not listed in §9 is still unimplemented.
Source reference: `F1r3srp3nt/HCG-One` at commit `b4f0e29` (read-only).
Date: 2026-10-30

## Evidence labels

| Label | Meaning |
|---|---|
| **VERIFIED** | Read directly in the HCG-One source at `b4f0e29`. This means code reading, not execution: nothing was compiled, launched or called against a live server. |
| **REPORTED** | Stated in source comments or the in-repo CardX report. Not independently checked. |
| **ASSUMPTION** | Inferred. Must be confirmed before it is relied on. |
| **PROPOSAL** | A recommendation for UNLEASHED. Not built; requires founder approval. |

---

## 1. Product constraints (from the founder brief)

- Native macOS, SwiftUI, Swift, Apple Silicon. It must run smoothly on 16 GB machines; the primary development machine is an M4 Max with 128 GB.
- Direct download from HCG's website (about NOK 399, not final). Developer ID signing, notarization, and Sparkle subject to approval.
- Account-based license with a limited offline grace period. Not implemented in this phase.
- **Market data stays simulated.** No paid or live feeds.
- **The server is the only authority** for identity, roles and permissions. The Mac app never decides access.
- Guiding principle: **EVERYTHING IS INTERCHANGEABLE.** It is implemented as clear component boundaries and replaceable integrations, not as a plugin framework.

## 2. What the existing iOS app looks like (VERIFIED)

- **Code base:** a single Xcode target, about 15.7k lines of Swift in 71 files.
  - iOS 18, Swift language mode 5.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency.
  - No third-party packages.
- **Composition root:** `HCGONEApp` creates seven `@Observable` stores (`AppSettings`, `SessionStore`, `RequestStore`, `ExperienceStore`, `LabStore`, `ClientStore`, `StudioStore`) and injects them through `.environment`.
- **Navigation:** `MainTabView` uses a custom floating tab bar on iPhone and a `NavigationSplitView` sidebar on iPad. Tabs: Home, Trading, Explore, Projects, Inbox, Account.
- **Two experiences:** an embedded website browser (`WebsiteExperienceView`) and the native app. They are switched by a permanent "Website | App" control.
- **Layering:** views call stores, and stores call services directly. There are no protocols at service boundaries, so services cannot be swapped for fakes in tests.
- **Trading Lab:** a well-isolated simulation engine (`TradingLab/`). It is the strongest reusable asset.

Details: `IOS_COMPATIBILITY.md`.

## 3. Target architecture (PROPOSAL)

### 3.1 Layers

```
┌────────────────────────────── Presentation (SwiftUI, macOS) ──────────────────────────────┐
│ Scenes & windows · Sidebar · Toolbars · Inspectors · Menu commands · Keyboard shortcuts   │
│ Feature views: Home · Trading · Explore · Projects · HCG Connect · Account                 │
└──────────────────────────────────────────────┬─────────────────────────────────────────────┘
                                               │ observes / sends intents
┌──────────────────────────── Application (@MainActor, @Observable) ─────────────────────────┐
│ SessionController · AccessModel · SimulationHost · WorkspaceLayoutStore · ConnectInbox     │
│ ModuleRegistry · Settings                                                                  │
└──────────────────────────────────────────────┬─────────────────────────────────────────────┘
                                               │ protocols (the interchangeable seams)
┌──────────────── Domain (pure Swift) ───────────────┐   ┌──────── Infrastructure ───────────┐
│ HCGDomain: roles (raw), workspace directory,        │   │ HCGNetwork: HTTP client, auth     │
│   suites, products, services, requests, instruments │   │   client, website mobile API,     │
│ HCGMarketSim: engine, broker, scenarios, curriculum,│   │   HCG Connect client              │
│   GEX model, progress                               │   │ HCGPlatformMac: Keychain, Touch ID│
└─────────────────────────────────────────────────────┘   │   (LocalAuthentication), WKWebView│
                                                          │   viewer, file store, open-URL     │
                                                          └────────────────────────────────────┘
```

**Rules:**
1. Domain targets import **Foundation only**. No SwiftUI, Observation, WebKit, Security or LocalAuthentication. This keeps them unit-testable everywhere, and keeps a later Windows or Linux UI possible without promising one.
2. Infrastructure implements protocols that are declared in the application layer. Views never call a network client directly.
3. Only the Application layer is `@MainActor`. The simulation engine and network clients are not main-actor bound.
4. **No authorization logic in the client.** The client keeps a mapping from server decisions to UI states (for example `permitted/available` → Available / Access Denied). That mapping is presentation, not policy. See `SECURITY_BOUNDARIES.md`.

### 3.2 Packaging

The proposal is one Xcode project, one macOS app target, and one local Swift package `HCGKit` containing these library targets:

| Target | Contents | Depends on |
|---|---|---|
| `HCGDomain` | Value types: `RawRole`, `WorkspaceDirectory`, `HCGSuite`, products and services catalog, `ServiceRequest`, `InstrumentSpec` | Foundation |
| `HCGMarketSim` | `MarketSimulator` (ported from `MarketEngine`, with the order-book fix), `SimBroker` core, scenarios, curriculum, `GEXModel`, progress model | Foundation, `HCGDomain` |
| `HCGNetwork` | `HTTPClient`, `AuthClient` (Supabase auth REST), `WebsiteMobileAPI` (workspaces, handoff), `ConnectAPI`; error contract | Foundation, `HCGDomain` |
| `HCGDesignSystem` | Palette, typography, `Panel`, `StatRow`, `Tag`, button styles, adapted for pointer and keyboard use | SwiftUI |

**Feature code** (Home, Trading, Explore, Projects, Connect, Account) starts as folders inside the app target. A feature moves into its own package target only when a second consumer appears. That keeps the "interchangeable" principle without building abstraction nobody uses yet.

**Platform code** (Keychain, LocalAuthentication, WKWebView, `NSWorkspace`) lives in the app target under `Platform/`, behind protocols declared in the application layer.

### 3.3 Interchangeable seams

These are the only protocols planned. Each one has a real reason to be swappable.

| Seam | Why it must be swappable | First implementation |
|---|---|---|
| `CredentialStore` | Keychain on Mac, in-memory store for tests | macOS Keychain (data protection keychain; see `SECURITY_BOUNDARIES.md` §5) |
| `AuthProviding` | The identity provider could change; tests need it | Supabase auth REST, the same project the iOS app uses |
| `AccessDirectoryProviding` | Server-decided workspaces; fakes for UI states | `GET /api/public/mobile/workspaces` |
| `HandoffProviding` | One-time web workspace entry | `POST /api/public/mobile/handoff` |
| `ConnectProviding` | Messaging transport could later become push or websockets | Polling the `/connect/*` endpoints |
| `LocalStore` | JSON files today; a sync service could replace them later | JSON files in Application Support |
| `MarketDataSource` | Keeps the trading UI independent of where data comes from | **`SimulatedMarketSource` only.** A live source is explicitly not approved and will not be stubbed. |

### 3.4 Module registry (future products without rewrites)

Each primary area registers a lightweight descriptor:

```swift
// PROPOSAL — illustrative, not implemented
struct ModuleDescriptor: Identifiable {
    let id: ModuleID                 // .home, .trading, .explore, .projects, .connect, .account
    let title: String
    let symbol: String
    let sections: [SectionDescriptor]
    let availability: (AccessSnapshot) -> ModuleAvailability  // derived from server data only
}
```

- The sidebar, the Go menu and the ⌘1…⌘6 shortcuts are generated from the registry.
- Future HCG products (CardX, Asset Index, Signature Studios, News, and so on) are added by registering a descriptor and their own feature folder.
- **No placeholder modules are created for them now.**

### 3.5 Scenes and windows

| Scene | Purpose |
|---|---|
| `WindowGroup(id: "main")` | Main window: `NavigationSplitView` with sidebar → content → optional inspector |
| `WindowGroup(id: "trading.panel", for: PanelDescriptor.self)` | Detached trading panels (chart, DOM, footprint, tape, …), each bound to a symbol |
| `WindowGroup(id: "workspace.viewer", for: SuiteID.self)` | Secure Workspace Viewer windows for server-authorized web suites. Each window requests its own one-time handoff. |
| `Settings` | Standard ⌘, settings window |

Sheets, `fullScreenCover`s and `presentationDetents` from iOS become windows, sheets, popovers or the inspector, whichever is native for the task.

### 3.6 Sidebar (initial navigation)

```
Home
Trading
  Learn · Simulate · Order Flow · Market Lab · Progress
Explore
Projects
HCG Connect
Account
  Profile · Client Workspace · Executive Workspace* · Settings
```

\* Executive Workspace is listed only after the server has verified access **in the current app run**. It is never shown from cached roles (see `SECURITY_BOUNDARIES.md`, finding S-05).

### 3.7 Menu commands and shortcuts (initial set, PROPOSAL)

| Menu | Command | Shortcut |
|---|---|---|
| Go | Home / Trading / Explore / Projects / HCG Connect / Account | ⌘1 … ⌘6 |
| File | New Trading Panel Window | ⌘⇧N |
| Trading | Play / Pause simulation | ⌘⇧P (Space while a trading panel has focus) |
| Trading | Slower / Faster | ⌘[ / ⌘] |
| Trading | Save Layout… / Restore Layout | ⌘⇧S / — |
| Account | Refresh Access | ⌘⇧R |
| Account | Sign Out | — |
| App | Settings | ⌘, |

Simulated order-entry hotkeys (buy/sell) are **off by default** and opt-in only. They are an open decision.

## 4. Trading workstation (PROPOSAL)

### 4.1 What exists today (VERIFIED)

- **One `MarketEngine` per symbol** (GC, NQ, ES, CL), owned by `LabStore`. It is seeded and deterministic, so replays are exact.
- **Panels already take the engine as a parameter**, e.g. `OrderFlowSection.panel(.dom, engine:)`.
  - Panel kinds that exist: DOM, Footprint, Tape (time and sales), CVD, Volume Profile, Heatmap, Chart, Order Ticket (Simulate), Lesson, GEX Lab, Progress.
- **The iPad `TradingWorkspace`** shows two of these side by side with a draggable divider. The layout persists via `@AppStorage`.
- **Blocker:** the clock ticks only the *active* symbol (`LabStore.ensureClock`, `engines[self.symbol]`). Two windows on different symbols would freeze one of them.
- **Defect:** the order-book shift in `MarketEngine.advancePrice` widens the spread on every price move. See `IOS_COMPATIBILITY.md` §5.

### 4.2 Design

```
SimulationHost (@MainActor @Observable)        ← one per app
 ├─ clock: one timer, ticks every symbol with ≥1 open panel (or an open position/order)
 ├─ simulators: [Symbol: MarketSimulator]     ← HCGMarketSim, Foundation-only
 ├─ snapshots: [Symbol: MarketSnapshot]       ← immutable value published per tick
 └─ broker: SimBroker                         ← fills against each symbol's own bid/ask

WorkspaceLayoutStore
 └─ layouts: [WorkspaceLayout]  (Codable, saved in Application Support)

indirect enum LayoutNode: Codable { case panel(PanelDescriptor); case split(Axis, Double, LayoutNode, LayoutNode) }
struct PanelDescriptor: Codable, Hashable { let id: UUID; var kind: PanelKind; var symbol: Symbol }
```

**Rendering:**
- Panels render from `MarketSnapshot` values, not from the live mutable engine.
- Redraws are capped at the display refresh rate via `TimelineView(.animation)` or a throttle. Today's engine can tick up to 16 times per second at 8× speed.
- DOM, footprint and heatmap keep using `Canvas`.

**Interaction:**
- Mouse hover shows level details; this replaces iOS tap-to-sheet.
- Right-click context menus on DOM levels.
- Scroll to zoom charts.
- Keyboard: playback, speed, panel focus cycling.

**Multiple windows:** any panel can be detached into its own window (`openWindow(id: "trading.panel", value: descriptor)`). All windows share the same `SimulationHost`, so DOM, tape and footprint on GC in three windows show the same stream.

**Saved layouts:** named and restorable. Optionally, the windows that were open are restored on relaunch.

## 5. State, persistence and concurrency (PROPOSAL)

- **Swift 6 language mode with strict concurrency for new code.**
  - App target: default `MainActor` isolation, matching the iOS project setting.
  - `HCGKit` targets: nonisolated, `Sendable` value types.
- **`SessionController` is an `actor`** with single-flight token refresh (fixes finding S-03).
  - The UI sees a `@MainActor` `AccessModel` that mirrors its state.
- **Local data** lives as JSON in `~/Library/Application Support/<bundle id>/`, or inside the sandbox container if sandboxed (recommended).
  - Contents: simulated account, lesson progress, layouts, settings.
  - No tokens. Tokens are stored only in the Keychain.
- **No analytics, telemetry or crash-reporting SDKs** without a separate approval (privacy).

## 6. Performance targets (PROPOSAL, unmeasured)

These are targets, not results. No measurements exist yet.

| Metric | Target on a 16 GB Apple Silicon Mac |
|---|---|
| Cold launch to usable main window | < 2 s |
| Resident memory: main window + 4 trading panel windows | < 600 MB |
| CPU at 1× speed, 4 panels visible | < 15 % of one performance core |
| Frame pacing while the simulation runs | No dropped frames at 60 Hz on the reference panels |

**Validation requires a 16 GB test machine.** The primary development machine (128 GB) does not prove the 16 GB objective. See `OPEN_DECISIONS.md` D-21.

## 7. What is deliberately NOT in this architecture

- **No authorization logic, role elevation or permission caching across sign-outs.**
- **No payment, licensing, update or release automation code.** Planned in `DEVELOPMENT_ROADMAP.md`; each requires approval.
- **No live market data and no stubs for it.**
- **No placeholder modules** for future HCG products.
- **The "Website | App" dual experience** from iOS is not carried over by default. See D-04.
- **HCG Studio** (the iOS on-device design editor) is not carried over by default. See D-05.
- **Nothing related to the separately reserved hackathon project.**

## 9. M1 as built (2026-10-30)

M1 implemented the foundation described above, with these deviations. Details and test evidence: `M1_IMPLEMENTATION_REPORT.md`.

| Plan (§ above) | As built in M1 | Why |
|---|---|---|
| `HCGKit` targets `HCGDomain`, `HCGMarketSim`, `HCGNetwork`, `HCGDesignSystem` (§3.2) | `HCGDomain`, `HCGMarketSim`, `HCGDesignSystem`. **No `HCGNetwork`.** | M1 makes no network calls. The target is created in M3. |
| "Domain targets import Foundation only" (§3.1 rule 1) | `MarketSimulator`, `SimulationState` and `SimulationEngine` are Foundation-only. `SimulationHost` additionally imports **Observation** (a standard Swift module, also available on Linux). | Keeps one testable host next to the engine. Still no SwiftUI, AppKit or UIKit in the core. The rule is corrected to "Foundation and Observation only". |
| `SimulationHost` holds simulators and publishes snapshots (§4.2) | Four layers: `MarketSimulator` (value type, one market) → `SimulationState` (value type, all markets + account, one clock) → `SimulationEngine` (actor, off the main actor) → `SimulationHost` (`@MainActor @Observable`, publishes immutable `SimulationFrame`s). | The value-type state makes determinism directly testable; the actor keeps simulation work off the main actor. |
| Clock ticks only symbols with open panels (§4.2) | All four markets advance in lockstep on every update. | Simpler and cheap (four small books). Revisit if M2 profiling on 16 GB shows a cost. |
| Render throttling via `TimelineView` (§4.2) | Not implemented. Panels redraw per published frame (≤ ~16/s at 8×). | Deferred to M2 with the multi-panel workstation. |
| Interchangeable seams (§3.3) | Only `SimulationTicker` (clock injection for tests) exists. `MarketDataSource`, `CredentialStore` and the other seams are not created yet. | Created with the milestone that needs them, to avoid unused abstractions. |
| Prices (not specified) | Integer ticks (`Int64`) throughout the simulation. | Exact book and spread arithmetic for every tick size. |
| Scenes (§3.5) | Main `WindowGroup` + `Settings`. No trading-panel or workspace-viewer windows. | Panel windows are M2; viewer windows are M4. |
| Menu commands (§3.7) | Go (⌘1–⌘6) and a **Simulation** menu (play/pause ⇧⌘P, step ⌥⌘., faster ⌘], slower ⌘[, speed, market ⌥⌘1–⌥⌘4, reset). No New Panel Window, Save Layout or Account menu. | Those commands belong to M2 and M3. |
| Sidebar (§3.6) | As planned, plus an "HCG" section header grouping Explore, Projects and HCG Connect. Executive Workspace is not listed. | No sign-in exists, so server verification is impossible (S-05). |
| Bundle identifier (D-02 proposal `app.hakmi.capital.group.unleashed`) | `com.hakmicapitalgroup.hcgoneunleashed` | Founder decision for M1, subject to signing review. |
| App-layer state in the app target (§3.2) | **M2.0:** navigation (`PrimaryArea`, `SidebarItem` with development notes, `NavigationModel`) moved to a fourth HCGKit target, **`HCGAppModel`** (Foundation + Observation). The app keeps only SwiftUI glue (`KeyEquivalent`, `FocusedValues`). | Makes navigation and availability rules unit-testable on any platform (M1_AUDIT ARCH-1). |
| Per-frame rendering (§4.2) | **M2.0:** views that read the simulation frame are isolated (`OrderFlowPanels`, `SimulatedMarketsSection`), so toolbars and static content are not rebuilt on every market update. Throttling is still M2.3. | M1_AUDIT OF-3, HOME-1 |
| `HCGDesignSystem` | Wrapped in `#if canImport(SwiftUI) && os(macOS)`; compiles to an empty module elsewhere. | Lets the whole package build and test on Linux. |
| Swift settings | Swift 6 language mode in the package and the app. Default actor isolation is **not** set at project level; isolation is declared explicitly. | Behaves the same across Xcode versions. |
