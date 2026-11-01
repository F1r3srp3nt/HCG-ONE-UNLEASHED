# HCG ONE: UNLEASHED

The native macOS edition of HCG ONE by Hakmi Capital Group: simulated order-flow trading training for advanced traders.

**Status: development build, M2 Stage 2** (charting). This build contains:
- the native shell and the simulated market engine;
- Order Flow, with candlestick charts from 1m to 1D built from the simulated trades, and indicators verified against TA-Lib;
- a simulated evaluation-style trading account (Trading → Simulate).
- No sign-in, no network connections, no payments or licensing.
- **All market data and all trading are simulated.** No order ever leaves the Mac.

Planning and status documents are in [`docs/`](docs). Start with [`docs/M2_STAGE2_REPORT.md`](docs/M2_STAGE2_REPORT.md), [`docs/CHARTING.md`](docs/CHARTING.md), [`docs/M2_STAGE1_REPORT.md`](docs/M2_STAGE1_REPORT.md), [`docs/TRADING_ENGINE.md`](docs/TRADING_ENGINE.md) and [`docs/M2_IMPLEMENTATION_PLAN.md`](docs/M2_IMPLEMENTATION_PLAN.md).

## Requirements

| | |
|---|---|
| Mac | Apple Silicon (arm64) |
| macOS | 15 or later |
| Xcode | 16 or later. The project uses file-system synchronized groups (project format 77) and was written against Xcode 26 project settings. |
| Dependencies | None. No third-party packages. |

## Open and run in Xcode

```bash
git clone https://github.com/F1r3srp3nt/HCG-ONE-UNLEASHED.git
cd HCG-ONE-UNLEASHED
git checkout feature/m2-stage2-charting   # current development branch, once pushed
open HCGOneUnleashed.xcodeproj
```

In Xcode, select the **HCGOneUnleashed** scheme and **My Mac**, then press **⌘R**.

Signing is set to **Sign to Run Locally** (ad-hoc, no team required). Developer ID signing and notarization are milestone M6 and need founder approval.

## Build and test from Terminal

Build the app:

```bash
xcodebuild -project HCGOneUnleashed.xcodeproj -scheme HCGOneUnleashed -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

Run all HCGKit tests through the app scheme:

```bash
xcodebuild -project HCGOneUnleashed.xcodeproj -scheme HCGOneUnleashed -destination 'platform=macOS,arch=arm64' test
```

Run the HCGKit tests directly with Swift Package Manager:

```bash
cd HCGKit && swift test
```

If local signing is not available on your machine, build without signing to check compilation only:

```bash
xcodebuild -project HCGOneUnleashed.xcodeproj -scheme HCGOneUnleashed -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

### Core tests without a Mac

`HCGDomain`, `HCGTrading`, `HCGCharting`, `HCGMarketSim` and `HCGAppModel` use only Foundation (and Observation), and `HCGDesignSystem` compiles to an empty module off macOS. The core tests also run in the official Swift Docker image:

```bash
docker run --rm -v "$PWD/HCGKit":/pkg -w /pkg swift:6.2-noble swift test
```

## Project layout

```
HCGOneUnleashed.xcodeproj    macOS app project (one target, shared scheme)
HCGOneUnleashed/
  App/                       entry point, main window, navigation, menu commands
  Features/                  Home, Trading/Simulate, Trading/OrderFlow, Settings
  Components/                shared app views (unavailable-section state, brand mark/wordmark, session banner, confirmations)
  Platform/                  bundle information
  Resources/                 asset catalog (temporary DEV icon), entitlements
HCGKit/                      local Swift package
  Sources/HCGDomain/         instruments, formatting, HCG product catalog
  Sources/HCGTrading/        simulated account and order engine (orders, fills, positions, risk, costs)
  Sources/HCGCharting/       candles 1m–1D from trades, indicators, chart geometry
  Tools/                     reference-data generator for the charting tests (TA-Lib, pandas)
  Sources/HCGMarketSim/      simulated market, order book, clock, session persistence, GEX model
  Sources/HCGAppModel/       navigation model (destinations, Go menu, window state)
  Sources/HCGDesignSystem/   colors, typography, panels, buttons, badges
  Tests/                     Swift Testing suites
docs/                        architecture, security, roadmap, decisions, trading engine, M1 report and audit, M2 plan, results and Stage 1 report
```

## Boundaries

- **`F1r3srp3nt/HCG-One` is a read-only reference.** Code is ported from it deliberately, file by file. Ported files name their source path and commit.
- **No production services are contacted.** Authentication, HCG Connect, workspaces, licensing and payments are future milestones, each requiring founder approval.
- **No secrets.** Signing keys, notarization credentials and update-signing keys never enter this repository.
- **Platforms.** The app is macOS only. Everything below the app layer (domain, trading engine, simulation, navigation model) is platform-neutral Swift and is tested on Linux, so a later Windows or Linux edition could reuse it. The UI (SwiftUI, AppKit, `HCGDesignSystem`) would be rebuilt for that platform. No Windows or Linux work is planned.
