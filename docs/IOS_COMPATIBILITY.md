# HCG ONE (iOS/iPadOS) → HCG ONE UNLEASHED (macOS): Compatibility Analysis

Status: **Phase 1 draft.**
Source: `F1r3srp3nt/HCG-One` at `b4f0e29`, path `ios-hcg/HCGONE/` (read-only).
Labels (**VERIFIED / REPORTED / ASSUMPTION / PROPOSAL**) are defined in `ARCHITECTURE.md`.

> Nothing here was compiled. This environment is Linux with no Swift toolchain or Xcode. Compatibility verdicts come from reading the source and from known SwiftUI platform availability. The first macOS build will confirm or correct them.

## 1. Summary

| Bucket | Share of code (approx., by lines) | Meaning |
|---|---|---|
| Reuse as-is | ~35 % | Pure Swift logic: simulation, curriculum, models, formatting |
| Reuse with changes | ~30 % | Logic is sound; needs a fix, a decoupling, or platform guards |
| Rebuild for macOS | ~25 % | App shell, navigation, screen layouts, web view hosting |
| Exclude (not carried over by default) | ~10 % | iOS-only or out-of-scope features (Studio, dual experience, legacy migration) |

**VERIFIED:** UIKit is used directly in only **5 files**. iOS-only SwiftUI modifiers are concentrated in view files. The domain and simulation code has **no** UIKit dependency.

**Rule for UNLEASHED (PROPOSAL):** code is **ported deliberately, file by file**, through review. It is never bulk-copied.
- Each ported file gets a header comment naming its HCG-One source path and commit.
- Data is never copied from the source repo or from any device: no demo fixtures, test accounts, release notes or legacy data.

## 2. File-by-file verdict

### 2.1 Reuse as-is (pending the first macOS build)

| Source file | Content | Target |
|---|---|---|
| `TradingLab/Curriculum.swift` | Lessons, key terms, quizzes | `HCGMarketSim` |
| `TradingLab/MarketScenario.swift` | Scripted scenario phases and events | `HCGMarketSim` |
| `TradingLab/GEXModel.swift` | Synthetic GEX/DEX model | `HCGMarketSim` |
| `TradingLab/LabInstruments.swift` | GC, NQ, ES, CL simulated symbols | `HCGMarketSim` |
| `TradingLab/LabProgress.swift` (data struct) | Lessons, quiz, scenario and practice progress | `HCGMarketSim` (the `@Observable` wrapper goes to the app) |
| `Models/InstrumentSpec.swift` | Tick size / point value specs | `HCGDomain` |
| `Models/HCGSuites.swift` | Suite ids → web routes (`erp`, `ceo_suite`, `employee_suite`, `client_workspace`) | `HCGDomain` |
| `Utilities/Fmt.swift`, `Utilities/FX.swift` | Formatting, manual FX conversion | `HCGDomain` |
| `HCGONETests/HCGONETests.swift` (GEX and determinism tests only) | Swift Testing tests | `HCGKit` tests |

### 2.2 Reuse with changes

| Source file | Required change |
|---|---|
| `TradingLab/MarketEngine.swift` | (1) **Fix the order-book shift defect** (§5). (2) Remove `@MainActor @Observable` from the core and publish immutable snapshots instead (`ARCHITECTURE.md` §4.2). (3) Add unit tests for book invariants. |
| `TradingLab/SimBroker.swift` | Split the core (Foundation) from the `@Observable` wrapper. P&L history produced under the spread defect is not carried over. |
| `TradingLab/LabStore.swift` | Rebuild as `SimulationHost`: one clock ticking **every** symbol in use, not only the active one. |
| `TradingLab/Charts/ChartViews.swift`, `OrderFlow/DomTapeHeatmap.swift`, `OrderFlow/FootprintView.swift` | Keep the `Canvas` and Charts rendering. Replace `.sheet` + `presentationDetents` level details with hover popovers or the inspector. Add context menus and scroll-zoom. |
| `TradingLab/Views/*` (Learn, Simulate, Market Lab, Progress, Exercises, Scenario Runner, GEX Lab, Market Header) | Re-lay out for wide windows and keyboard use. Keep the logic. Remove haptics (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator` in `SimulateSection.swift`) and `keyboardType`. |
| `Services/HCGONEAuthService.swift` | Base URL and anon key move to build configuration (`.xcconfig`). Remove the legacy `isEmployee` probe. Rename `HCGONESession` → `HCGSession`. Errors stay friendly. |
| `Services/HCGWorkspaceService.swift` | Endpoints and error contract reused as-is. Move to `HCGNetwork`. Optionally replace the tolerant `JSONSerialization` parsing with `Codable` once the contract document is available (see `INTEGRATIONS.md` §6). |
| `ViewModels/SessionStore.swift` | Keep the state model (`verified / requiresVerification / checking / expired / unavailable`). Rebuild as an `actor` with **single-flight refresh** and **verification on launch** (findings S-03, S-04). |
| `Models/Roles.swift` | Replace substring role matching with an exact, founder-approved allow-list (finding S-02). Display only, never authorization. |
| `Services/Persistence.swift` | The JSON file store is reused. The Keychain wrapper is reworked for macOS (data protection keychain). `.completeFileProtection` has no iOS-equivalent effect on macOS (ASSUMPTION; see `SECURITY_BOUNDARIES.md` §5). |
| `Views/Website/WebsiteModel.swift` (`HCGWebsiteConfig`) | Allowed hosts and the three official destinations are reused. The browser model itself is not (D-04). |
| `Views/Website/SecureWorkspaceViewer.swift` (`WorkspaceViewerModel`) | The navigation and security policy is reused: HTTPS upgrade, origin allow-list, 401/403/410/503 states, fresh handoff on protected refresh. The view is rebuilt with `NSViewRepresentable` and hosted in its own window. iOS-only: `scrollView.contentInsetAdjustmentBehavior`, `topBarTrailing`, `navigationBarTitleDisplayMode`. |
| `Models/Company.swift` | The company, services catalog and product registry content is reused after a content review. The HCG ONE product entry says "iPhone · iPad", and the news list is in code. |
| `Models/Requests.swift` | The model is reused. **Submission does not exist** (no backend endpoint, §6 and `INTEGRATIONS.md`). |
| `Models/ClientModels.swift` | Types reused. **`ClientDemo` fixtures are not copied.** |
| `Utilities/Theme.swift`, `Views/Components/Components.swift` | Palette tokens and component styles reused in `HCGDesignSystem`, tuned for pointer, hover and focus rings. `ChromeInsetKey` (floating tab bar inset) is dropped. |
| `ContentView.swift` (`LockView`, `authenticate`) | The optional app-lock pattern carries over: `LAContext.deviceOwnerAuthentication` works on macOS with Touch ID or password fallback. Re-arming moves from `scenePhase` to app activation and screen-lock notifications. |

### 2.3 Rebuild for macOS

| Source | Why |
|---|---|
| `HCGONEApp.swift` | `UINavigationBar.appearance`, `UIColor`, `UIFont`. The Mac app needs multiple scenes and `Commands`. |
| `Views/MainTabView.swift` | Floating tab bar, `toolbar(.hidden, for: .tabBar)`, the chrome-inset system. Replaced by the sidebar plus Go menu. |
| `Views/Trading/TradingView.swift` (`TradingWorkspace`) | The two-pane iPad split uses `UIApplication…keyWindow` for divider math. Replaced by the layout tree and detachable windows. |
| `Views/Home`, `Explore`, `Projects`, `Inbox`, `Account`, `Client` | Single-column phone layouts. Mac versions use multi-column content, tables and inspectors. Server-state mapping logic (e.g. `ExecutiveWorkspaceView.tileStatus`) is extracted into the application layer and reused. |
| `Views/Account/AuthView.swift` | Sign-in form: `keyboardType`, `textInputAutocapitalization`. Mac version: a sheet in the main window with standard text fields and password autofill. |
| `Views/Shared/RequestViews.swift`, `Views/Shared/SearchView.swift` | Re-laid out. Search becomes a toolbar search field. |
| `Views/Website/WebsiteExperienceView.swift` | `UIViewRepresentable`, `UIActivityViewController` → `NSViewRepresentable`, `ShareLink`. Only needed if D-04 keeps an in-app website window. |

### 2.4 Exclude by default (founder decision in `OPEN_DECISIONS.md`)

| Source | Reason |
|---|---|
| `Views/Studio/*`, `Models/StudioSchema.swift`, `ViewModels/StudioStore.swift` | HCG Studio: an on-device editor for the iOS app's own content and design. Its repository, publish and release capabilities are explicitly "denied, no endpoint exists" in source. Not core to UNLEASHED (D-05). |
| `ViewModels/ExperienceStore.swift`, Website/App switcher | Dual-experience concept is phone-specific (D-04). |
| `Views/Welcome/CinematicIntroView.swift`, `OnboardingView.swift` | Phone-first full-screen intro (`tabViewStyle(.page)`). The Mac needs a short first-run window (D-06). |
| `Utilities/LegacyData.swift`, `AccountView.legacyPanel` | Migration of the retired iOS 4.0 trading data. No Mac equivalent exists. |
| `Models/AppReleaseNotes.swift`, `Models/Company.swift` news items | iOS release history. The Mac gets its own notes. |
| `Models/ClientModels.swift` → `ClientDemo` | Hard-coded demo project, documents and threads; `showDemo` defaults to `true` on iOS. |
| `Config.swift` | Rork build-time placeholder. UNLEASHED uses `.xcconfig` files instead. |

## 3. iOS-only API inventory (VERIFIED by search)

| API | Files | macOS replacement |
|---|---|---|
| `UINavigationBar.appearance`, `UIColor`, `UIFont` | `HCGONEApp.swift` | SwiftUI `.toolbar`, `.navigationTitle`, design-system fonts |
| `UIApplication.shared.connectedScenes` | `Views/Trading/TradingView.swift` | `GeometryReader` or the layout tree |
| `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator` | `TradingLab/Views/SimulateSection.swift` | Remove. Optional `NSHapticFeedbackManager` on Force Touch trackpads only. |
| `UIViewRepresentable` (WKWebView) | `Website/WebsiteExperienceView.swift`, `Website/SecureWorkspaceViewer.swift` | `NSViewRepresentable` |
| `UIViewControllerRepresentable` (`UIActivityViewController`) | `Website/WebsiteExperienceView.swift` | `ShareLink` or `NSSharingServicePicker` |
| `WKWebView.scrollView` | `Website/WebsiteModel.swift`, `Website/SecureWorkspaceViewer.swift` | Not available on macOS; drop the inset tweaks |
| `.navigationBarTitleDisplayMode` | `MainTabView`, `ClientSheets`, `SecureWorkspaceViewer`, Studio views | Remove |
| `.fullScreenCover` | `AccountView`, `ExecutiveWorkspaceView`, Studio views | Unavailable on macOS → separate window (`openWindow`) or sheet |
| `.presentationDetents` | `ClientView`, `WebsiteExperienceView`, `DomTapeHeatmap`, `FootprintView`, `ScenarioRunnerView`, `LearnSection` | Popover or inspector |
| `.keyboardType`, `.textInputAutocapitalization` | `AuthView`, `AccountView`, `RequestViews`, `SimulateSection`, Studio | Remove; use `.textContentType` where applicable |
| `ToolbarItemPlacement.topBarTrailing` | `HomeView`, `ExploreView`, `SecureWorkspaceViewer` | `.primaryAction` or `.automatic` |
| `.tabViewStyle(.page)` | `OnboardingView` | Not used on Mac (D-06) |
| `.toolbar(.hidden, for: .tabBar)` | `MainTabView` | Not applicable |
| `.sensoryFeedback` (11 uses) | Several views | Compiles on macOS but has little effect. Drop for clarity. |
| `.refreshable` | `InboxView` | A ⌘R "Refresh" command plus a toolbar button |

**Cross-platform as-is (ASSUMPTION, standard SwiftUI availability):** `Canvas`, Swift Charts, `NavigationSplitView`, `@Observable`, `LocalAuthentication`, `WKWebsiteDataStore`, `.fileImporter`, `.swipeActions`.

## 4. Assets and branding (VERIFIED)

| Asset | Status |
|---|---|
| `AppIcon.appiconset/icon.png` (1024×1024, full-bleed square) | **Not suitable as-is.** macOS icons use the rounded-rectangle Mac icon shape with padding and their own size set. A Mac icon needs to be produced from the brand source. |
| `HCGLogo.imageset/HCGLogo.png` (1024×1024) | Reusable for the about window, sign-in and first run |
| `AccentColor` | Reusable (silver accent) |
| Typography | System serif (`.design(.serif)`) for display text, system sans for UI. Both are available on macOS. No custom font files exist. |
| Design guide | `Theme.swift` references `.rork/DESIGN.md`, which is **not in the repository** (`.rork/` is git-ignored). Request a copy (D-18). |

## 5. Defects found in reusable code

### 5.1 Order-book spread widens on every price move (VERIFIED by code reading; logic reproduced)

- **Location:** `TradingLab/MarketEngine.swift`, `advancePrice(ticks:)`, lines ~413–436.
- **Up-move:** the code removes the *best* bids (`bidLevels.removeFirst`) and appends new bids priced from the *worst* bid (`bidLevels.last + tick`). The bid moves down while the ask moves up.
- **Down-move:** the code removes the *best* asks (`askLevels.removeFirst`) and inserts lower bids, so the spread widens again.
- **Evidence:**
  - A Python port of just this function was run in this session's scratch space. The Swift code itself was **not** executed.
  - GC spread from the initial 0.10 (one 0.10 tick): 0.30 after 1 move, 1.10 after 5, 3.50 after 20, 54.70 after 400. It only resets on scenario load or session reset.
  - This matches the iOS observation "GC spread 4.30 vs 0.50".
- **Impact:** DOM and spread display are wrong, and **simulated fills pay the inflated spread**. That distorts P&L, statistics and Progress.
- **Related risk (code reading, not reproduced):** the down-move path never refills `askLevels`. A long run of net down-moves could empty it, and `askLevels[0]` in `executeOneTrade` would then crash.
- **Fix approach (PROPOSAL):**
  - Shift both sides of the book so that the invariant `bestAsk − bestBid == spec.tickSize` holds by default, and `bidLevels` / `askLevels` are each strictly monotonic.
  - Widening becomes an **explicit scenario parameter** (e.g. the "news" scenario that intends "spreads blow out") that decays back.
  - Covered by unit tests.

### 5.2 Other known iOS issues: relevance to the Mac

| iOS issue (founder-reported) | Cause found? | Mac relevance |
|---|---|---|
| "test" greeting | **VERIFIED:** the greeting uses the account's `displayName` (`HomeView.greeting`). It is account data on the server, not code. | Same on Mac until the test account is renamed. Server-side cleanup. |
| "Testtest" request | **VERIFIED:** requests are stored **only on the submitting device** (`RequestStore` → `service.requests.json`). The owner's "Client requests" inbox reads that local file. | The Mac will not show iOS-local data. The underlying gap (no request endpoint) affects both (§6). |
| "Client" / "Test" chats | ASSUMPTION: server HCG Connect threads from test accounts (`connect/threads`); `ClientDemo` thread names differ. | Server-side cleanup. |
| Website/App bar overlaps content | iOS floating chrome | Not applicable (no tab bar on Mac) |
| Ticker chips wrap digits | Not investigated in detail (chip rows in `OrderFlowSection`, `MarketHeader`, `ClientView`) | Mac layouts are rebuilt; use `.monospacedDigit()` with `.fixedSize()` |
| GC spread inconsistent | **VERIFIED:** §5.1 | **Affects Mac:** fixed during the port |
| Empty area on Order Flow | Not investigated | Rebuilt on Mac |
| Duplicate back button on Executive Workspace | Not investigated (likely nested `NavigationLink` inside `NavigationStack` plus a custom title modifier; ASSUMPTION) | Not applicable (sidebar navigation) |
| Visible role names | **VERIFIED:** raw roles shown in `HomeView:122`, `AccountView:215`, `ClientView:73`, `ExecutiveWorkspaceView:157` | Do not carry over (S-06) |
| "Checking…" never finishes | **VERIFIED:** `.requiresVerification` is rendered as "Checking…" while `verifyAccess()` runs only from the Executive Workspace and Studio screens (the Executive one only if `executivePermissionSync` is on), never on launch | Fixed in `SessionController` (S-04) |
| No privacy notice on request forms | **VERIFIED:** the request flow collects name and email without a notice | Mac must include one (S-08) |

## 6. Functional gaps in the source app (VERIFIED)

These are things the iOS app **does not actually do**. UNLEASHED must not claim them either.

- **Service requests are never delivered to HCG.** `HCGServiceRequest.delivered` is never set to `true`. The source comments say "No HCG request endpoint is connected yet".
  - The owner inbox copy ("When a client … requests a service … it arrives here") is misleading: it only shows requests made on the same device.
- **Projects** has no data source. It is honestly empty in iOS ("That connection isn't available to the app yet").
- **Notifications preferences** (`HCGNotifyPrefs`) exist, but no notification transport is wired.
- **"HCG Today" news** is an in-code list, not a feed.
- **Employee and Partner tools** show "ERP not linked" / "Not linked".
- **HCG Connect** is polling-based. No push.

## 7. The web app in the same repo (VERIFIED, reference only)

`web-hcg-hakmi-capital-group/` is a Vite/React "rork-web-app". It mirrors HCG ONE: `/home`, `/trading`, `/client`, `/partner`, `/employee`, `/executive`, …, plus a TypeScript port of the Lab engine (`src/lab/*.ts`).
- It uses the **same substring role mapping** as iOS (`hcgAuth.ts`, `mapRole`) and gates workspaces client-side from those roles (`domain/workspaces.ts`).
- It is not used by UNLEASHED. It is noted here because the same findings apply to it.
