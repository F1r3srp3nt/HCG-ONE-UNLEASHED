# HCG ONE UNLEASHED — Open Decisions

Status: **Phase 1 draft.** Each decision belongs to the founder. "Recommendation" is a **PROPOSAL**, not a decision.
"Blocks" names the earliest milestone that needs the answer (see `DEVELOPMENT_ROADMAP.md`).

| ID | Decision | Options | Recommendation | Blocks |
|---|---|---|---|---|
| **D-01** | macOS deployment floor | macOS 15 Sequoia+ · the current release only | **macOS 15+.** Matches the iOS 18-era APIs already used (e.g. the `Tab` API), and Apple Silicon customers on 16 GB are typically on 15 or later (ASSUMPTION) | M1 |
| **D-02** | Bundle identifier and display name | e.g. `app.hakmi.capital.group.unleashed` / "HCG ONE UNLEASHED" | A separate bundle ID from iOS (`app.hakmi.capital.group`). It is a separate paid product, and there is no shared Keychain or data with iOS. | M1 |
| **D-03** | Package granularity | One `HCGKit` package with 3–4 targets · one package per feature | **One package, few targets.** Features stay in the app until a second consumer exists. | M1 |
| **D-04** | iOS "Website ‖ App" dual experience on Mac | Drop · a "Website" window inside the app · links open in the default browser | **Drop the dual mode.** Website links open in the default browser. Authorized web *suites* still open in in-app viewer windows (needed for handoff). | M1 |
| **D-05** | HCG Studio (iOS on-device design/content editor) | Exclude · port later | **Exclude.** It is local-only, its server capabilities are "denied", and it is not a customer feature. | M1 |
| **D-06** | First-run experience | Port the cinematic intro · a short native welcome window · none | **A short native welcome window** (brand, sign-in or continue as guest, simulated-data notice) | M1 |
| **D-07** | Service request delivery | Build a backend endpoint · route requests through HCG Connect · keep "local draft" only | Founder or backend decision. **Until decided, the Mac app does not offer request submission** (no fake "sent"). | M5 |
| **D-08** | Code sharing with the iOS app | Fork (copy into UNLEASHED) · extract `HCGKit` into its own repo used by both | **Fork now, review later.** HCG-One is read-only and Rork-managed. Revisit after M2. Fixes made here (e.g. the spread bug) do not reach iOS automatically. | — |
| **D-09** | Keep the core platform-neutral for possible Windows or Linux | Foundation-only core · allow Apple frameworks in core | **Foundation-only core.** It is cheap insurance; no Windows or Linux UI is planned. | M1 |
| **D-10** | How builds and tests are verified | Founder's Mac · GitHub Actions macOS runner · Linux Swift toolchain here for core tests | **All three, in that order of authority.** CI runs build and test only: no signing, no secrets, no release. Needs approval. | M1 |
| **D-11** | Packaging and updates | DMG · ZIP; Sparkle 2 yes/no; appcast host | **Notarized DMG + Sparkle 2** with an EdDSA-signed appcast on the HCG website. Approval needed. | M6 |
| **D-12** | Licensing | Grace period length; device limit; entitlement endpoint (does not exist); who builds it | Server-signed entitlement token; grace period 7–14 days; 2–3 Macs per account. **All founder decisions; nothing built without approval.** | M6 |
| **D-13** | Payments and consumer law | Merchant of record (e.g. Paddle, Lemon Squeezy) · own Stripe + VAT handling | **Get accountant or legal advice first.** Includes VAT on digital services and the Norwegian withdrawal right (angrerett) for digital content: the immediate-delivery consent and acknowledgement flow must be correct. | M6 |
| **D-14** | App Sandbox / Mac App Store path | Sandbox on · off | **On from M1.** Keeps the MAS option open and improves local data isolation. | M1 |
| **D-15** | Role vocabulary | The exact raw role strings in `user_roles` and the label each should show | **Founder provides the list.** UNLEASHED maps only exact matches, for display only. | M3 |
| **D-16** | Trading scope vs the "Trader Mission" product | Trading stays inside HCG ONE · it becomes Trader Mission later | The product registry lists "Trader Mission — trading education and simulated markets" as in development (VERIFIED). **Founder to confirm whether UNLEASHED Trading is, or later becomes, that product.** | M2 |
| **D-17** | Features that justify ~NOK 399 | e.g. multi-window simulated workstation, saved layouts, deeper scenarios, structured curriculum | **Decide before M2 polish**, so effort goes to what sells | M2 |
| **D-18** | Missing reference documents | The "integration contract" cited as §4–§12 in source; `.rork/DESIGN.md` | **Founder supplies copies** (or confirms they don't exist) | M3 |
| **D-19** | Telemetry and crash reporting | None · Apple-native crash reports only · third-party SDK | **None in M1–M7 without approval.** Feedback through HCG Connect or email. | M7 |
| **D-20** | Simulated order hotkeys | Off · opt-in · on | **Opt-in, off by default** | M2 |
| **D-21** | 16 GB test hardware | Borrow or buy a 16 GB Apple Silicon Mac · tester devices | **Required to claim the 16 GB objective.** The M4 Max 128 GB cannot prove it. | M2 |
| **D-22** | Branch and commit workflow | `claude/cool-wozniak-l78dyb` → PR into `main` · direct to `main` | **Feature branch + PR**, merged by the founder. No commit or push without approval. | Now |
| **D-23** | HCG Connect polling interval | e.g. 15 s foreground / 60 s background | **Ask the backend owner** what is acceptable given `429` limits | M5 |
| **D-24** | Backend environment for development | Production (`beta.hakmicapitalgroup.com` + production Supabase) · a staging copy | **A staging environment with test accounts**, if one exists. If it doesn't, the founder decides whether development may use production with dedicated test accounts. | M3 |
| **D-25** | Account creation in the Mac app | Sign-up in app · sign-in only (sign-up on website) | **Sign-in only.** Sign-up links to the website, so consent and terms stay in one place. | M3 |
| **D-26** | Server-side test data cleanup | "test" display name, "Client"/"Test" Connect threads | Founder or backend task. Not done by this project (no backend changes). | Before beta |
| **D-27** | Mac app icon | Adapt the brand icon to the macOS icon shape · new design | **Designer adapts the existing mark** to the macOS icon template | M1 (placeholder: brand logo, clearly temporary) |

## Decisions already made (from the founder brief, recorded for traceability)

| Decision | Source |
|---|---|
| macOS, SwiftUI, Swift, Apple Silicon; smooth on 16 GB | Phase 1 brief §3 |
| Direct download from HCG's website; about NOK 399 (not final); Developer ID + notarization; Sparkle subject to approval | Brief §3, §9 |
| Account-based license with a limited offline grace period | Brief §9 |
| Market data stays simulated; no paid live feeds | Brief §7 |
| The server enforces all roles and permissions; the app never decides | Brief §8 |
| HCG-One is read-only; all work goes in hcg-one-unleashed; no commits or pushes without approval | Brief §1, §11 |
| HCG ONE first as a shell; other HCG products later, as modules, not all at once | Brief §6 |
| Mac only for now; Windows or Linux possibly later | Founder message, 2026-10-30 |
| The separately reserved hackathon project is excluded from this project entirely | Brief §2 |
