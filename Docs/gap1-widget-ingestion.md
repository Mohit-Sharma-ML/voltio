# Gap #1: Widget gallery ingestion — RESOLVED (macOS 26.7.1)

## Status: SHIPPED — widgets appear in the Edit Widgets gallery (16 Oct 2026)

Both kinds (`VoltioBatterySmall`, `VoltioBatteryMedium`) are cached in
chronod's descriptor DB and render. **The final "trust gate" turned out to
govern only the passive/background cache path.** The gallery's interactive
query (`host requested: NotificationCenter`) launches the extension directly,
and once the extension actually works, chronod caches its descriptors
regardless of signature trust class — free-team dev signing is fine.

**Operational note:** after reinstalling a build, chronod's "extension added"
handler purges the cached descriptors (`shouldn't cache it ... isApple? false`
— harmless). Open the widget gallery once (Notification Center → Edit
Widgets) to re-trigger the interactive fetch, which re-caches. No Xcode or
notarization needed.

## Verified pipeline stages (all passing)

| Stage | Gate | Evidence |
|---|---|---|
| Bundle registration | pkd requires the appex sandboxed | `plug-ins must be sandboxed` when sandbox removed; gone with sandbox |
| App Group container | containermanagerd requires Team-ID prefix + real signing | `<TEAMID>.group.com.voltio.app` APPROVED |
| Sandbox entitlement handshake | host AND appex must both declare `com.apple.security.app-sandbox` | `Extension is not entitled to run in the App Sandbox` until host was sandboxed; gone after |
| Entry point | appex must link `-e _NSExtensionMain` | direct run crashed `Unrecognized extension type` → now prints `An XPC Service cannot be run directly.`; `nm` shows `U _NSExtensionMain` |
| SDK metadata | LC_BUILD_VERSION sdk must be real SDK | `-Xlinker -platform_version macos 15.0 27.0` (CodexBar #1173 fix) |
| Descriptor fetch (interactive) | extension must actually serve descriptors when the gallery queries | chronod log: `Found: <CHSWidgetDescriptor ... VoltioBatteryMedium>`, `inserting metadata`, 2017 bytes in `Descriptors` table |
| Background cache (passive) | purged for dev signatures — BYPASSED via gallery interaction | `purging instead because we shouldn't cache it ... isApple? false` on install; gallery fetch re-caches |

## Mis-diagnosis on the way (don't repeat)

Earlier revisions of this doc claimed chronod requires notarized/MAS
signatures. That was wrong: ~20 headless tests only ever observed the
*passive* purge and never opened Notification Center (the pre-agreed manual
step). The first successful interactive gallery query — done by the user at
10:54 — cached descriptors from the same dev-signed binaries. The Correlation
with limit-monitor/CodexBar ("notarization required") was survivorship:
their tests also never exercised the interactive path, and their binaries
additionally had a crashing entry point (missing `-e _NSExtensionMain`,
CodexBar #1095).

## Fixes applied (keep!)

1. `Package.swift`: VoltioWidgets target `linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]`
2. Both entitlements: `com.apple.security.app-sandbox` true + team-prefixed App Group
3. `scripts/build_app.sh`: Apple Development identity + hardened runtime + `-platform_version` SDK args
4. Host app is now SANDBOXED (IOKit battery reads, App Group snapshot, energy
   store auto-migrated to container, 75 tests green). Sandbox spawn noise
   (`nvram-get`, `process-info-listpids` denies) is benign. `swift test` must
   run with `DEVELOPER_DIR=/Applications/Xcode.app/...` (a swiftly-managed
   Swift 5.9 shadows the Xcode toolchain in bare PATH).

## Tooling kept

- `scripts/gen_real_project.rb` → `build/xcode-real/Voltio.xcodeproj`: full
  Xcode project wrapping the real sources (PowerCore as a static-lib target —
  xcodebuild rejects duplicate basenames across source roots in one target).
  Useful for GUI debugging; NOT required for shipping.
- `scripts/gen_provisioning_project.rb`: profile-factory stub (moot for free
  teams; harmless to keep for a future paid team).

