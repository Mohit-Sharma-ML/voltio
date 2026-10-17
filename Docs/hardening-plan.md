# Voltio Hardening Plan — Technical Debt Remediation Roadmap

**Date:** 2026-10-17 · **Status:** proposed, not started · **Trigger:** project retrospective
identified 4 structural risks (see "Findings" in the retrospective: god-files, untested
orchestrator, platform fragility, private docs).

This plan applies industry-standard practices (SOLID, file-per-responsibility,
characterization testing, feature-flagged rollout, semantic versioning) scoped to a
solo-maintainer project. Every phase ships independently and leaves the app green.

---

## Guiding principles

1. **Refactor only behind green tests.** No behavior change and no commit without
   the full suite passing (86+ XCTests + Swift Testing suites).
2. **Characterization first.** For untested code, write tests that pin *current*
   behavior before touching it (Feathers, *Working Effectively with Legacy Code*).
3. **Strangler-fig, not big-bang.** Move code out of god-files incrementally;
   each move is one commit, reviewable, revertible.
4. **Public behavior is the contract.** Panel layout, menu-bar rendering, widget
   timelines, and the App Group schema are user-visible contracts — changes to
   them are features, not refactors, and get version bumps.
5. **Platform-fragile code gets isolation layers.** Every private/undocumented
   behavior we depend on sits behind a protocol so it can be swapped or stubbed
   when Apple changes the floor.

---

## Phase 0 — Safety net (before any refactor)

**Goal:** be able to change anything without fear. ~1 session.

### 0.1 Characterization tests for `BatteryModel` (highest value)

`BatteryModel` is the untested conductor (377 lines): polling, sleep/wake,
energy recording, widget publishing, alert dispatch, peripheral merging. This
session's two launch crashes both lived in exactly this layer.

- Extract its collaborators behind protocols so they can be faked:
  ```swift
  protocol BatteryReadingProviding { func read() throws -> BatterySnapshot }
  protocol WidgetPublishing {
      func publish(_ snapshot: BatterySnapshot, todayEnergy: EnergyAggregator.DayTotal?,
                   smoothedPowerWatts: Double?, forceReload: Bool)
  }
  ```
  `BatteryReader`, `WidgetSnapshotWriter`, `BluetoothBatteryScanner`, and
  `ChargeLimitReader` already have the right shapes — introduce protocols at the
  model's constructor and inject defaults. No behavior change.
- Then add characterization tests with a `FakeBatteryProvider`:
  - publish-on-tick writes a snapshot; reload fires only per throttle rules
  - state-flip (charging ↔ not) forces reload (the 2026-10-17 fix, pinned)
  - sleep/wake path caches pre-sleep reading and re-evaluates on wake
  - `chargeLimit` publishes only on change
- **Target:** ≥ 12 tests covering the model's decision logic.

### 0.2 Golden-image UI smoke for the panel

One test that renders `MenuPanelView` with a fixed snapshot into an image and
compares key texts (hero %, status pill, section headers, device row count).
Not pixel-perfect — just *did the layout break* detection for refactor safety.
Uses existing `MenuPanelWindowSizingTests` patterns.

**Exit criteria:** suite green with new tests; protocols in place; zero code
movement yet.

---

## Phase 1 — Dissolve the god-files (strangler-fig)

**Goal:** no file > ~400 lines; each type = one responsibility. ~2–3 sessions.

### 1.1 `AppSettings.swift` (778 lines → ~8 files)

The file is already MARK-sectioned (Alerts / Shortcuts / Appearance / Devices /
Notifications / Developer / Onboarding / Alert-rule helpers) — the sections are
the extraction plan:

| New file | Content | Est. lines |
|---|---|---|
| `Settings/AlertSettings.swift` | Alert thresholds, hysteresis, rules helpers | ~120 |
| `Settings/ShortcutSettings.swift` | Toggle-shortcut combos + bindings | ~100 |
| `Settings/AppearanceSettings.swift` | Appearance, notification appearance | ~60 |
| `Settings/DeviceSettings.swift` | Pins, hidden IDs, device helpers | ~90 |
| `Settings/DeveloperSettings.swift` | Fake battery %, diagnostics flags | ~50 |
| `AppSettings.swift` (kept) | Storage keys, schema migration, core wiring | ~250 |

Technique: Swift `extension AppSettings` per file (same type, multiple files) so
**zero call sites change** — pure code motion. Property-registration and
`didSet` wiring stay in the core file.

### 1.2 `MenuPanelView.swift` (752 lines → ~7 files)

Same trick — the MARK sections are one-to-one with SwiftUI view structs:

| New file | Content |
|---|---|
| `Panel/PanelHero.swift` | Hero ring + status pill + time line (192–230) |
| `Panel/HealthCards.swift` | Health, temperature, power, flow cards |
| `Panel/CapacityCards.swift` | Capacity bar, condition, charge-limit card |
| `Panel/EnergyCards.swift` | Energy today, per-app attribution |
| `Panel/DevicesSection.swift` | Devices section + rows + compartments |
| `MenuPanelView.swift` (kept) | Container, sizing, section ordering (~180) |

Each extracted view is a `private struct` in its own file taking
`(snapshot, settings?)` — no shared mutable state, so extraction is mechanical.
Phase 0's golden-image test guards the layout.

### 1.3 `BluetoothBatteryScanner.swift` (520+ lines → 4 collaborators)

Currently mixes five jobs. Split by responsibility:

| New type | Responsibility |
|---|---|
| `ContinuityOwnershipTracker` | The 2026-10-17 ownership gate: paired-names cache, connected-names confirmation, `isContinuityDeviceOwned`. Pure logic + injected `PairedNamesProviding` (so IOBluetooth is stubbed in tests — also removes the only IOBluetooth import from scanning flow) |
| `GATTBatteryReader` | `retrieveConnectedPeripherals(batteryService)` + characteristic reads |
| `ContinuityAdvertisementDecoder` (move) | The `didDiscover` handling: RSSI floor, manufacturer-data decode → already half in `ContinuityDecoder` (PowerCore); move the scanner-side glue |
| `BluetoothBatteryScanner` (kept) | CBCentralManager lifecycle + delegate plumbing (~200) |

**Exit criteria:** all extractions done, suite green, line counts ≤ 400/file,
no call-site changes outside the moved code.

---

## Phase 2 — Platform-fragility isolation (the Apple-moves-the-floor insurance)

**Goal:** every undocumented behavior behind a swappable seam. ~1–2 sessions.

### 2.1 The fragility inventory (audit result)

| Behavior | Where | Risk | Isolation |
|---|---|---|---|
| chronod interactive-query ingestion | `build_app.sh`, Docs | Apple changes pkd | Documented + build script (done) |
| SMC charge keys gated | Docs/gap2 | Apple policy | Read-only design (done) |
| WidgetKit reload budget | `WidgetSnapshotWriter` | Budget semantics change | `WidgetReloadThrottling` protocol over the static logic |
| `AvgTimeTo*` garbage values | `BatteryReader.timeEstimate` | Firmware-dependent | `TimeEstimateValidating` policy type with the 24 h rule as data |
| Continuity payload layout | `ContinuityDecoder` | RE layout breaks | Already isolated in PowerCore + per-model calibration log (done) |
| Audio-ACL invisibility | `BluetoothBatteryScanner` | CB behavior change | Behind `PairedNamesProviding` (Phase 1.3) |
| Sandbox entitlement needs | entitlements templates | New entitlements required | Checklist in Docs (done) |

### 2.2 Degradation testing

Add a `Docs/platform-drift-playbook.md`: for each row above — the symptom users
would report, the probe to run, the fallback. This is the doc you open at 2 AM
when a macOS update breaks something, instead of re-deriving everything.

### 2.3 Startup health checks (optional, developer mode)

Developer Mode pane shows pass/fail for each fragile seam (CB authorization,
paired-list fetch, chronod descriptor presence via PlistBuddy on the App Group).
Turns "Devices section is empty" into a 10-second diagnosis.

---

## Phase 3 — Publish & sustain

**Goal:** the docs earn their keep; contributors can help. ~1 session.

1. **Flip the repo public** (leak-swept history already verified; zero-risk).
2. **Ship v0.3.1** with the five queued fixes (BT entitlement, ownership gate,
   277h filter, reload throttle, no-limit hint) + DMG.
3. **Contributor onboarding:** the `Justfile`/make shim (`just build/test/run`);
   `Package.resolved` policy note in CONTRIBUTING.
4. **GitHub issues as the roadmap:** open one issue per item in this plan —
   public tracking, and issues double as the contribution menu.
5. **Cadence:** platform-drift re-check after each macOS point release
   (run the Phase 2.3 health checks, the probe scripts in Docs).

---

## Sequencing & effort

| Phase | Sessions | Depends on | Risk if skipped |
|---|---|---|---|
| 0 Safety net | 1 | — | Every later refactor is blind |
| 1 God-files | 2–3 | 0 | Debt compounds; every feature edit risks layout/state breaks |
| 2 Isolation | 1–2 | 0 (parallelizable with 1) | Next macOS update = multi-day archaeology |
| 3 Publish | 1 | 0 | Docs stay locked; solo maintenance forever |

**Total: ~5–7 focused sessions.** Phases 0 → 1 are strictly ordered; Phase 2 can
interleave; Phase 3 lands whenever you're ready to flip visibility.

## What this plan deliberately does NOT do

- **No CI** — final decision, unchanged; local suite is fast and sufficient.
- **No App Store target** — free-signing DMG + direct download stays.
- **No rewrite of `AlertManager`/alert rules** — tested and stable (TD4 closed).
- **No back-deploy below macOS 15** (TD6) — constraints accepted.
