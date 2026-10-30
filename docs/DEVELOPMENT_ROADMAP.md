# HCG ONE UNLEASHED — Development Roadmap

Status: **Phase 1 plan, updated after M1 implementation (2026-10-30).** Every milestone requires founder approval before it starts. M1 was approved by the founder; M2 and later are not.
Labels (**VERIFIED / REPORTED / ASSUMPTION / PROPOSAL**) are defined in `ARCHITECTURE.md`. Everything below is **PROPOSAL** unless marked otherwise.

## Working rules

1. **All work happens in `F1r3srp3nt/hcg-one-unleashed`.** `F1r3srp3nt/HCG-One` is read-only: no commits, branches, tags, PRs or settings changes.
2. **No commit or push without explicit founder approval.** M1 work is on branch `feature/m1-native-macos-foundation` (D-22).
3. **No changes to live HCG backends, security policies, roles or governance.**
4. **Market data stays simulated.**
5. **"Built", "tested" and "verified" are claimed only with evidence** (build log, test output, screenshot), and stated with where they ran.
6. **The separately reserved hackathon project is out of scope in every milestone.**

## Build and verification constraint (VERIFIED)

The current agent environment is **Linux x86_64 with no Xcode**. Since M1, the Foundation-only HCGKit targets are built and tested there with the official `swift:6.2-noble` Docker image (option (c) below). macOS app code cannot be compiled or run here. Options (D-10):
- (a) The founder builds and tests on the M4 Max.
- (b) A GitHub Actions macOS runner builds and tests on each push. This is CI, not release automation.
- (c) Install the official Swift toolchain for Linux here, for Foundation-only packages (`HCGDomain`, `HCGMarketSim`, `HCGNetwork`). This gives real test runs for the core.

Until one of these exists, Mac code from this environment is **written, not built**, and is labeled as such.

---

## Phase 1: Repository verification, architecture, documentation (this phase)

- **Deliverables:** `docs/ARCHITECTURE.md`, `IOS_COMPATIBILITY.md`, `INTEGRATIONS.md`, `SECURITY_BOUNDARIES.md`, `DEVELOPMENT_ROADMAP.md`, `OPEN_DECISIONS.md`.
- **Exit:** founder review and approval of the architecture and of milestone M1 scope.

## M1: Native foundation and simulation core (no network, no auth)

**Goal:** a real, launchable Mac app with the native shell and a working simulated trading core. It is the first proof that the architecture holds.

**Scope:**
1. **Project setup.**
   - Xcode project with a macOS app target (Apple Silicon, deployment floor per D-01) and a local Swift package `HCGKit` with targets `HCGDomain`, `HCGMarketSim`, `HCGDesignSystem`.
   - Swift 6 language mode; App Sandbox and Hardened Runtime enabled from day one.
   - `.gitignore` for secrets and build output; `.xcconfig` scaffolding with **no secret values**.
2. **Port `MarketEngine` → `MarketSimulator`.**
   - Fix the order-book defect (`IOS_COMPATIBILITY.md` §5.1).
   - Snapshot publishing.
   - Unit tests: spread invariant, monotonic book, no empty side, seed determinism, scenario replay equality.
   - Port the existing GEX tests.
3. **`SimulationHost`:** one clock for all symbols in use; `SimBroker` core with fills against the corrected book.
4. **Main window.**
   - `NavigationSplitView` sidebar with the six areas from the brief.
   - Non-trading areas show an **honest "not yet available in this build" state**. No fake content and no demo data.
5. **Trading → Order Flow:**
   - a resizable split of **Chart | DOM** on the simulated engine;
   - symbol picker (GC, NQ, ES, CL);
   - play, pause and speed.
6. **Menus and settings:**
   - Go menu (⌘1…⌘6) and Trading menu (play/pause, speed);
   - a `Settings` scene with reporting currency and simulation defaults.
7. **Design system:** `Palette` and component styles ported to `HCGDesignSystem`, plus a Mac app icon request (`IOS_COMPATIBILITY.md` §4).

**Exit criteria:**
- The app builds and launches on the founder's Mac, or on a CI macOS runner, with logs.
- `HCGKit` tests pass, with output attached.
- The spread stays at one tick on GC through a 10,000-tick soak test.
- Founder review of the look and feel.

**Not in M1:** authentication, any HTTP call, licensing, signing for distribution, Sparkle.

**M1 status (2026-10-30): implemented; awaiting the founder's first macOS build and review.** Details: `M1_IMPLEMENTATION_REPORT.md`.

| Scope item | Status |
|---|---|
| 1. Project setup (Xcode project, macOS app target, `HCGKit`, Swift 6, sandbox, hardened runtime, `.gitignore`) | Done. The `.xcconfig` scaffolding was not needed (no configuration values exist yet). |
| 2. `MarketSimulator` port with the order-book fix, snapshots and tests | Done |
| 3. `SimulationHost` with one clock; `SimBroker` core | Done (basic broker: market orders) |
| 4. Main window with six areas and honest unavailable states | Done |
| 5. Order Flow: Chart and DOM split, symbol picker, play/pause/speed | Done (plus a basic simulated ticket) |
| 6. Go and Trading menus; Settings scene | Done (the "Trading" menu is named "Simulation") |
| 7. Design system and Mac icon | Design system done; **temporary** DEV icon only (D-27) |

| Exit criterion | Status |
|---|---|
| App builds and launches on the founder's Mac or CI, with logs | **Pending.** Not possible in this environment. |
| `HCGKit` tests pass, with output | **Passed on Linux** (Swift 6.2.4: 43 tests, 73 cases, 0 warnings). Pending on macOS. |
| GC spread stays at one tick through a 10,000-tick soak | **Passed** (executed) |
| Founder review of look and feel | Pending |

## M2: Trading workstation v1

**Goal:** the desktop differentiator, as a usable simulated workstation.

**Scope:**
- **Layout tree:** split panes, resizable, with nested horizontal and vertical splits.
- **Panels** (all exist in iOS today, VERIFIED): Chart, DOM, Footprint, Tape (time and sales), CVD, Volume Profile, Heatmap, Order Ticket + positions + orders + history, Lessons (Learn), Market Lab scenarios + debrief, GEX Lab, Progress.
- **Detachable panel windows** (`WindowGroup(for: PanelDescriptor.self)`), each bound to a symbol; several symbols run at once.
- **Saved named layouts**, and restoring open windows on relaunch.
- **Mouse and keyboard:**
  - mouse: hover details, context menus, scroll-zoom;
  - keyboard: focus cycling, shortcuts.
  - Simulated order hotkeys stay opt-in (D-20).
- **Render throttling and a performance pass:** Instruments traces on the M4 Max **and** a 16 GB Apple Silicon machine (D-21).

**Exit:**
- Four or more panel windows across two symbols run at 1×–8× speed, within the `ARCHITECTURE.md` §6 targets, **measured** on 16 GB hardware.
- Founder review.

## M3: Identity and session (requires explicit approval)

**Preconditions:**
- Founder approval to implement production authentication.
- S-01 RLS review completed or explicitly waived by the founder.
- Approved role vocabulary (D-15).
- Environment decision (D-24).

**Scope:**
- `AuthClient` (sign in, refresh, sign out, reset password, sign up per D-25).
- `SessionController` actor with single-flight refresh and verification on launch.
- Keychain `CredentialStore`.
- Sign-in sheet; Account → Profile (read-only).
- Workspace directory fetch, used only for display.

**Exit:** the test matrix from `SECURITY_BOUNDARIES.md` §2, run against the agreed environment and documented:
- sign in;
- launch restore;
- offline launch;
- forced 401 → refresh → retry;
- refresh-token revocation → signed out;
- sign-out wipes the Keychain and web data.

## M4: Server-gated workspaces

**Scope:**
- Secure Workspace Viewer windows, with the handoff contract unchanged.
- Account → Client Workspace (`client_workspace`).
- Account → Executive Workspace, listed only after verification this run, with tiles from the directory (`erp`, `ceo_suite`, `employee_suite`).
- No raw role names.

**Exit:**
- An account the server authorizes and an account it does not authorize behave correctly.
- Expired handoff, 503 and 401 states are demonstrated.

## M5: HCG Connect, Home, Explore, Projects

**Scope:**
- **HCG Connect:** thread list, message view, send, mark read, polling within agreed rate limits (D-23).
- **Home:** an ecosystem overview from existing data (product registry, Connect unread state, authorized workspaces). No invented activity.
- **Explore:** services and product catalog (content-reviewed), with the request flow **only** once D-07 is resolved, and a privacy notice (S-08).
- **Projects:** an honest empty state, or a server-permitted link into the client portal.

## M6: Distribution readiness (each item requires approval)

- **Signing and notarization:** Developer ID signing, Hardened Runtime, notarization via `notarytool`, stapling; a DMG or ZIP package (D-11).
- **Updates:** Sparkle 2 with an EdDSA-signed appcast hosted on HCG's website (D-11).
- **Licensing:** the account-based license check with an offline grace period, after a server entitlement endpoint exists (D-12).
- **Payments:** integration per the D-13 outcome. Merchant-of-record vs self-handled VAT and the Norwegian withdrawal-right handling must be confirmed with an accountant or lawyer first.
- **Legal pages:** privacy policy, EULA and terms reachable from the app.

## M7: Private beta

- **Distribution:** notarized builds to a small tester list, distributed through the HCG website.
- **Feedback:** a feedback channel through HCG Connect, or email (D-19: no telemetry SDK without approval).
- **Bug triage → 1.0.**

## After 1.0 (envisioned, not planned)

- Additional HCG products as modules via the module registry (CardX, Asset Index, Signature Studios, News, …), one at a time.
- Mac App Store submission (D-14).
- Windows or Linux (D-09): only the Foundation-only core is reusable; the UI would be rebuilt.

---

## Recommended iOS follow-ups (for the founder, in Rork; not done by this project)

HCG-One is read-only to this project. These findings also apply to the iOS app and can be ported there by the founder:
- Order-book spread fix (§5.1 of `IOS_COMPATIBILITY.md`).
- S-03 (single-flight refresh), S-04 (verify on launch), S-05 (no entry points from cache), S-06 (hide raw roles).
- `ClientDemo` off by default.
- S-07 owner-inbox copy.
- S-08 privacy notice.
- Found during the M1 port (`M1_IMPLEMENTATION_REPORT.md` §4):
  - aggressor-direction sign in `MarketEngine.executeOneTrade`;
  - `Int.random` slippage in `SimBroker.fill`;
  - commission attribution in `SimBroker.open/fill`;
  - the GEX test expectation `strikes.count == 3` (should be 21).
