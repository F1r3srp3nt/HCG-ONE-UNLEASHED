# HCG ONE UNLEASHED — Integrations

Status: **Phase 1 draft.**
Labels (**VERIFIED / REPORTED / ASSUMPTION / PROPOSAL**) are defined in `ARCHITECTURE.md`.

> **No HCG service was called during Phase 1.** Every endpoint below is documented from the HCG-One source (`b4f0e29`) and the in-repo report `HCG-CARDX-AUTH-INTEGRATION-REPORT.md`. "VERIFIED" means "present in source code", **not** "confirmed working against the live server". Live verification is part of milestone M3 and needs founder approval.

## 1. Backends

| Backend | Role | Base |
|---|---|---|
| Supabase Auth project (shared HCG identity) | Issues and refreshes tokens; `user_roles` table holds raw role strings | Project URL defined in `HCGONEAuthService.baseURL` (iOS). Not repeated here. In UNLEASHED it is injected via `.xcconfig`. |
| HCG website mobile integration API | Verifies the token server-side, reads roles, **decides** workspace authorization, issues handoffs, serves HCG Connect | `https://beta.hakmicapitalgroup.com` |

**Public client key:** the iOS app ships the Supabase **anon** key (JWT role `anon`, decoded during this review). It is public by design: the website ships the same key, and access is governed by sign-in plus row-level security (RLS).
- UNLEASHED will reference it through build configuration and will **not** copy it into documentation.
- **A service-role key must never appear in the app, the repo or CI logs.**

## 2. Identity endpoints (VERIFIED in source)

All requests send header `apikey: <anon key>`. Authenticated REST calls also send `Authorization: Bearer <access token>`.

| Purpose | Method & path | Notes |
|---|---|---|
| Sign in | `POST /auth/v1/token?grant_type=password` | body `{email, password}` |
| Refresh | `POST /auth/v1/token?grant_type=refresh_token` | body `{refresh_token}`. ASSUMPTION: Supabase rotates refresh tokens, so concurrent refreshes are unsafe (S-03). |
| Sign up | `POST /auth/v1/signup` | body `{email, password, data:{display_name}}`. Returns no session when email confirmation is required. |
| Password reset | `POST /auth/v1/recover` | body `{email}` |
| Sign out | `POST /auth/v1/logout` | revokes the refresh token server-side |
| Raw roles | `GET /rest/v1/user_roles?select=role&user_id=eq.<id>` | RLS-protected (REPORTED). The policies themselves are not in either repository. |

Friendly error mapping (VERIFIED): `invalid_credentials`, `email_not_confirmed`, `over_request_rate_limit`, `over_email_send_rate_limit`, `user_already_exists`, `weak_password`.

## 3. Website mobile API (VERIFIED in source)

Base `https://beta.hakmicapitalgroup.com`. Every call sends `Authorization: Bearer <Supabase access token>`.

| Purpose | Method & path | Response used by the client |
|---|---|---|
| Workspace directory | `GET /api/public/mobile/workspaces` | `{ user{id,email,displayName}, roles[String], workspaces[{id,title?,route?,url?,permitted,available,requires?}], integration{handoff?,version?} }` |
| Session handoff | `POST /api/public/mobile/handoff` body `{"target": "<route>"}` | `{ url, expiresAt / expires_at, target }`. The one-time code is in the URL **fragment**, single-use, user-bound, 60 s lifetime (REPORTED). |
| Connect threads | `GET /api/public/mobile/connect/threads` | `{ role, threads[{clientId/client_id, title/clientName, lastMessage, unread}] }`. Role-aware: staff see clients, clients see their own (REPORTED). |
| Connect messages | `GET /api/public/mobile/connect/messages?clientId=…&since=…` | `{ clientId, messages[{id, body/message/content, createdAt, fromStaff, authorName}] }`. Polling with a `since` cursor. |
| Send message | `POST /api/public/mobile/connect/messages` body `{body, clientId?}` | `{ message{…} }`. Max 4000 characters (REPORTED). |
| Mark read | `POST /api/public/mobile/connect/read` body `{clientId?}` | — |

**Known workspace ids** (REPORTED): `erp`, `ceo_suite`, `employee_suite`, `client_workspace`, `hcg_connect`. Also `hcg_studio`, which source says the server does not advertise today.

**Suite → route mapping** (VERIFIED, `HCGSuites.swift`):

| Workspace id | Web route |
|---|---|
| `erp` | `/erp` |
| `ceo_suite` | `/control-panel` |
| `employee_suite` | `/dashboard` |
| `client_workspace` | `/client-portal` |

**Error contract** (VERIFIED in the client mapping; the source refers to it as "integration contract §11"):

| Status | Meaning | Client behavior |
|---|---|---|
| `401` | Token missing or expired | One refresh, then retry. Sign in again on a second 401. |
| `429` | Rate limited | Wait about 60 s |
| `503` | Unavailable | Retry later |
| `410` | Handoff expired or reused | Request a fresh handoff |
| other | — | Generic retry message |

## 4. Web workspace viewer contract (VERIFIED in `SecureWorkspaceViewer.swift`)

- Load the handoff URL in a persistent `WKWebView` (`WKWebsiteDataStore.default()`). The page redeems the code itself.
- **The app never injects scripts, cookies or tokens.**
- Allowed origins: `beta.hakmicapitalgroup.com`, `hakmicapitalgroup.com` and their subdomains. Anything else is cancelled and opened externally (on Mac: the default browser via `NSWorkspace`).
- `http://` navigations are upgraded to `https://`.
- Navigation responses: `401/403` → Access Denied, `410` → link expired, `503` → unavailable.
- Refreshing a protected route (`/erp`, `/control-panel`, `/dashboard`, `/client-portal`) requests a **fresh handoff** instead of reloading.
- Sign-out wipes **all** website data in the default store.
- **Mac note (PROPOSAL):** each suite opens in its own window (`WindowGroup(for: SuiteID.self)`). Because all windows share the default data store, signing out must close every viewer window before the wipe.

## 5. Public web destinations (VERIFIED in `WebsiteModel.swift`)

| Destination | URL |
|---|---|
| HCG Website | `https://hakmicapitalgroup.com` |
| News Website | `https://news.hakmicapitalgroup.com` |
| AI Website | `https://ai.hakmicapitalgroup.com` (existing HCG destination; listed only as a link) |

Main-site routes used as shortcuts: `/`, `/services`, `/products`, `/about`, `/contact`, `/auth`.

## 6. What does NOT exist (VERIFIED by absence in source; do not invent)

| Capability | Status | Consequence for UNLEASHED |
|---|---|---|
| Service request submission and status endpoint | **None.** Requests stay on the device. | The Mac app must not show requests as delivered. It also must not present a local "owner inbox" as client intake (S-07). A backend endpoint is a founder or backend decision (D-07). |
| Projects, milestones, documents API | **None** ("served by the HCG enterprise system", not connected) | Projects shows an honest empty state, or links into `client_workspace` via handoff where the server permits it |
| Notifications or push | **None** | Home "authorized activity" is limited to what the existing endpoints return (Connect unread state, directory) |
| News feed API | **None** (in-code list) | Link to the News Website; no in-app feed until one exists |
| ERP data API | **None.** ERP is only reachable as the web suite via handoff. | No native ERP screens |
| License or entitlement endpoint | **None** | Required before licensing work (D-12). Not to be designed into HCG systems without approval. |
| Profile update endpoint | **None found.** Display name comes from `user_metadata`. | Profile is read-only in M3 |
| Integration contract document (§ numbers cited in source) | **Not present** in either repository | Request a copy (D-18). Until then the contract is reconstructed from client code only. |
| `hcg_session_bearer` | **Does not exist** in client code (REPORTED in the CardX report) | Do not use |

## 7. Integration plan for UNLEASHED (PROPOSAL)

| Milestone | Integration | Prerequisites |
|---|---|---|
| M1–M2 | **None.** Simulation only, no network. | — |
| M3 | Identity: sign-in, refresh, sign-out, roles read, workspace directory (read-only) | Founder approval; RLS review (S-01); approved role allow-list (D-15); config values for a non-production or production project (D-24) |
| M4 | Handoff and web suite windows; Client Workspace; Executive Workspace (server-gated) | M3 complete; confirmation that handoff targets accept desktop clients (ASSUMPTION: the endpoint is client-agnostic) |
| M5 | HCG Connect (threads, messages, send, read) via polling | Rate-limit guidance for polling interval (D-23) |
| Later | Requests, Projects, notifications, licensing | New backend endpoints. Each requires a founder decision. |

**Client identification (PROPOSAL):** UNLEASHED sends a descriptive `User-Agent` (e.g. `HCG-ONE-UNLEASHED/<version> (macOS <version>)`), so the backend can distinguish desktop traffic. No new headers carrying authority.
