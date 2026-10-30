# HCG ONE UNLEASHED — Security Boundaries

Status: **Phase 1 draft, with M1 controls recorded in §9.**
Labels (**VERIFIED / REPORTED / ASSUMPTION / PROPOSAL**) are defined in `ARCHITECTURE.md`.

> **Governance rule (founder brief):** any change to HCG system rules, security policies, roles, permissions or governance requires **explicit manual founder approval**. Nothing in this document changes those systems. Findings that touch them are recommendations only.

## 1. Trust boundaries

```
 ┌──────────── UNTRUSTED: the user's Mac ────────────┐        ┌────────── TRUSTED: HCG servers ──────────┐
 │ HCG ONE UNLEASHED                                  │        │ Supabase Auth  (identity, tokens)         │
 │  • UI, local preferences, layouts                  │ HTTPS  │ user_roles + RLS (raw roles)              │
 │  • simulated market + simulated account            │ ─────► │ Website mobile API (authorization,        │
 │  • tokens in Keychain (protected, but on device)   │        │   workspace directory, handoff, Connect)  │
 │  • cached display copy of server decisions         │        │ Web suites (ERP, CEO Suite, …) with their │
 │                                                    │        │   own server-side auth                    │
 └────────────────────────────────────────────────────┘        └───────────────────────────────────────────┘
```

**Principle: everything on the Mac can be read and modified by its owner.** Therefore:

| The client MAY | The client MUST NOT |
|---|---|
| Show server decisions (`permitted`, `available`, roles) as UI state | Grant, infer, elevate or extend any permission |
| Hide entry points the server has not authorized in the current run | Show privileged entry points based only on cached or local data |
| Cache the last server response **for display**, clearly marked as stale | Use cached data to perform privileged actions offline |
| Store tokens in the Keychain | Store tokens in files, `UserDefaults`, logs, URLs or web views |
| Offer optional local safeguards (Touch ID app lock) labeled as local | Present a local safeguard as authorization |
| Run the trading simulation entirely locally | Send simulated results anywhere as if they were real performance |

## 2. Authentication and session (PROPOSAL, implementation in M3 after approval)

- **Identity:** reuse the existing HCG Supabase identity. Same account system as the website and iOS. No second auth system.
- **Session lifecycle:** a `SessionController` actor owns the session.
  - **Single-flight refresh:** concurrent callers await one refresh task.
  - **Verification on every launch** and on app reactivation after more than N minutes. N is to be decided.
  - **Expiry and revocation:** a 401 after one refresh, or a hard refresh failure, leads to signed-out state. The Keychain item is deleted, and all workspace viewer windows are closed and their web data wiped.
  - **Offline:** the app stays usable for simulated content. Server-gated areas show "Unavailable"; they are never shown from cache.
- **Sign-out:** revoke the refresh token server-side (`/auth/v1/logout`), delete the Keychain item, close viewer windows, wipe `WKWebsiteDataStore.default()`, clear the in-memory directory.

## 3. Authorization (VERIFIED current behavior → PROPOSED Mac behavior)

| Concern | iOS today (VERIFIED) | UNLEASHED (PROPOSAL) |
|---|---|---|
| Source of workspace access | `GET /mobile/workspaces` `(permitted, available)` | Same; the only source |
| Role classification | Substring match on raw role strings (`Roles.swift:26`; also `hcgAuth.ts:76` on web) | Exact allow-list of known role strings, **display only**. The list comes from the founder (D-15). |
| Executive entry points | Shown when cached Keychain roles map to "executive". Account labels it "Available" before any server check (`AccountView:80`, `HomeView:142`). | Shown only after server verification **in this run** **and** when the directory permits a relevant workspace |
| Studio-style local capabilities | Require verification this run + executive role + `ceo_suite` permitted | Not carried over (D-05) |
| HCG Connect roles | Server returns `role` with threads | Same; UI follows the server's `role` |
| Owner request inbox | `isOwner` from raw roles; shows **device-local** requests | Not carried over until a server endpoint exists (S-07) |

## 4. Findings in the source application

Severity reflects risk to HCG. **None of these were exploited or tested against live systems.**

| ID | Severity | Finding | Evidence | Recommendation | Needs founder approval? |
|---|---|---|---|---|---|
| **S-01** | **High (unverified)** | All data protection depends on Supabase RLS and on how roles get into `user_roles`. Neither is in the repositories. If users can insert or update their own `user_roles` rows, or a signup trigger copies roles from client-supplied `user_metadata`, anyone can self-elevate. | No policies or migrations in either repo; signup sends `data.display_name` from the client | Audit RLS on `user_roles` and on all tables used by Connect, ERP and the client portal. Confirm the signup trigger never reads roles from metadata. | **Yes** (backend and security policy) |
| **S-02** | Medium | Substring role mapping: any raw role containing `admin`, `owner`, `director`, `exec`, `founder`, `ceo` maps to executive in the UI; `team` or `staff` maps to employee. | `Models/Roles.swift:22-28`; `web…/services/hcgAuth.ts:76` | Exact allow-list in UNLEASHED. Founder supplies the real role vocabulary. | **Yes** (role semantics) |
| **S-03** | Medium | Token refresh can run concurrently (timer, `verifyAccess`, `refreshWorkspaces`, `validAccessToken`). With refresh-token rotation, reuse may revoke the session, which appears as random sign-outs. Multi-window Macs make this more likely. | `ViewModels/SessionStore.swift` (four independent `auth.refresh` call sites) | Single-flight refresh in an actor | No (client-only) |
| **S-04** | Low–Medium | Server verification does not run on launch. A restored session shows cached roles; `.requiresVerification` renders as "Checking…" indefinitely on Account. | `SessionStore.init` (no verify); `AccountView.swift:116`; verify only from Executive/Studio | Verify on launch and activation | No |
| **S-05** | Medium | Privileged navigation entry points appear from **cached** roles (Executive Workspace "Available"). Tiles inside are server-gated, so no privilege is granted, but the UI states availability without a server decision. | `AccountView.swift:80-86`, `HomeView.swift:142-148` | Entry points only from verified-this-run state | No |
| **S-06** | Low | Raw server role strings are displayed to users. This exposes the internal role taxonomy, notably in screen shares. | `HomeView:122`, `AccountView:215`, `ClientView:73`, `ExecutiveWorkspaceView:157` | Show a friendly label only, or nothing | No |
| **S-07** | Medium (integrity / privacy) | The "Client requests" owner inbox lists requests stored on **the same device**. The copy claims client requests "arrive here". Requests contain name and email (personal data) and are never delivered. | `InboxView.swift:95-122`; `Models/Requests.swift` (`delivered` never set true) | Do not carry over. A real intake needs a server endpoint (D-07). | **Yes** (new backend endpoint) |
| **S-08** | Compliance | No privacy notice where personal data (name, email, request details) is collected | `Views/Shared/RequestViews.swift` | Add an Art. 13 GDPR notice and privacy policy link at every collection point. Wording reviewed by a legal advisor. | **Yes** (legal text) |
| **S-09** | Low | `isEmployee` is true whenever the user has *any* `user_roles` row, including plain clients | `HCGONEAuthService.isEmployee` | Remove. Not used in UNLEASHED. | No |
| **S-10** | Info | Only the Supabase **anon** key is in source (JWT `role: anon`). Pattern scan of the working tree and all 19 commits found no service-role key, private keys, AWS keys, `.p8`/`.p12` files or `.env` files. | Scan run this session (patterns: JWTs, `sk_live/test`, `service_role`, `sb_secret_`, `AKIA…`, `BEGIN … KEY`, password literals; file names `.env`, `secret`, `key`, `.p8`, `.p12`, `credentials`) | Keep it that way. UNLEASHED injects public config via `.xcconfig`. Secrets live only in Keychain or CI secrets. | No |
| **S-11** | Low | The per-workspace biometric gate on iOS passes when the device has no passcode or biometrics | `SecureWorkspaceViewer.authenticateLocally` | On Mac, `deviceOwnerAuthentication` falls back to the account password (ASSUMPTION, standard LocalAuthentication behavior). Keep it labeled as a local safeguard. | No |

## 5. macOS-specific controls (PROPOSAL)

| Control | Recommendation | Notes |
|---|---|---|
| App Sandbox | **Enable**, even for Developer ID distribution | Limits other processes and keeps Mac App Store compatibility open. Entitlements: `network.client`, user-selected file read/write (for exports). |
| Hardened Runtime | **Required** | Needed for notarization |
| Keychain | Generic password items in the **data protection keychain** (`kSecUseDataProtectionKeychain`), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ASSUMPTION to verify in M3: Developer ID apps need a provisioning profile / keychain-access-group entitlement for the data protection keychain. Fallback: the login keychain with an app-specific access control list (ACL). |
| File protection | `.completeFileProtection` has no iOS-equivalent effect on macOS (ASSUMPTION) | At-rest protection relies on FileVault plus the sandbox container. **No tokens or secrets in files.** |
| Local personal data | Minimise. Store nothing about other people. | Requests are not stored as an "owner inbox" (S-07) |
| Logging | `os.Logger` with privacy redaction; never log tokens, emails or message bodies | iOS uses `print` only for persistence errors |
| Web views | The `WorkspaceViewerModel` policy unchanged; no script injection; external links to the default browser | Close all viewer windows before the sign-out wipe |
| Screen sharing | No raw roles; optional "privacy mode" to blur Connect message previews | PROPOSAL, low priority |
| Updates | Sparkle 2 with an EdDSA-signed appcast over HTTPS | **Subject to approval** (D-11) |

## 6. Secrets that must never enter the repository

| Secret | Where it belongs |
|---|---|
| Supabase service-role key | Server only. Never in any client. |
| Developer ID Application certificate and private key | Founder's login Keychain; later, CI secret storage if approved |
| Notarization credentials (App Store Connect API key or app-specific password) | Keychain profile (`notarytool store-credentials`) or CI secrets |
| Sparkle EdDSA private key | Founder's Keychain / offline backup. The public key ships in the app. |
| Payment provider keys, license-signing keys | Server only, if and when approved |

The repository's `.gitignore` will exclude `*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.provisionprofile`, `.env*`, `Secrets.xcconfig` and `DerivedData/`. To be added in M1, with approval.

## 7. Licensing boundary (design constraints only; not implemented, not approved)

- **The entitlement is decided by the server**, bound to the HCG account.
- **The offline grace period** is represented by a **server-signed**, short-lived entitlement token with expiry. The client verifies the signature with an embedded public key. It never extends the period itself, and resists clock rollback by tracking the last-seen server time.
- **Licensing never touches authorization:** a valid license does not imply any role or workspace access.
- **No license or payment code is written without founder approval** (D-12, D-13).

## 8. What requires founder approval before any work

1. **S-01:** RLS and signup trigger audit, plus any resulting policy change.
2. **S-02 / D-15:** the approved role vocabulary and its display mapping.
3. **S-07 / D-07:** any new server endpoint (requests, projects, notifications, entitlement).
4. **S-08:** privacy notice wording.
5. **Implementing production authentication** in UNLEASHED (M3).
6. **Signing, notarization, Sparkle, licensing, payments, CI with secrets.**

## 9. Controls in place after M1 (2026-10-30)

| Control | M1 state | Verified how |
|---|---|---|
| App Sandbox | `com.apple.security.app-sandbox = true` (`HCGOneUnleashed/Resources/HCGOneUnleashed.entitlements`), plus `ENABLE_APP_SANDBOX = YES` | File contents. **Enforcement on macOS not yet observed.** |
| Network access | **None.** No `network.client` entitlement, so the sandbox blocks outgoing connections. No networking code. | Entitlements file; source search (no `URLSession`, URLs or endpoints) |
| Hardened Runtime | `ENABLE_HARDENED_RUNTIME = YES` (Debug and Release) | Build settings. **Not yet observed** in a signed binary. |
| Signing | "Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`), no team. No certificates in the repo. | Build settings |
| Credentials / tokens / Keychain | None used or stored | Source search |
| Secrets in repository | None. `.gitignore` excludes `*.p8`, `*.p12`, `*.cer`, provisioning profiles, `.env*`, `Secrets.xcconfig`. | Pattern scan of the working tree |
| Local storage | `UserDefaults` holds three preferences only: default speed, start-on-launch, DOM depth. `@SceneStorage` holds sidebar selection and symbol. No personal data. | Source (`Preferences.swift`, `MainWindow.swift`) |
| Authorization | No privileged UI. Executive Workspace is not listed; Account, Profile and Client Workspace show "requires sign-in". | Source (`Navigation.swift`, `UnavailableSectionView.swift`) |
| Telemetry | None | Source and dependency list (no packages) |

To verify on the Mac after the first build:

```bash
codesign -d --entitlements - --verbose=2 "$(xcodebuild -project HCGOneUnleashed.xcodeproj -scheme HCGOneUnleashed -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/HCGOneUnleashed.app"
```

The output should list `com.apple.security.app-sandbox`, and the code-signature flags should include `runtime` (ad-hoc builds show `adhoc,runtime`).
