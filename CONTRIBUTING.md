# Contributing to Voltio

Thank you for considering a contribution! Voltio is a personal project that
grew into something worth sharing — PRs that keep it clean and native-feeling
are very welcome.

## Getting started

```bash
git clone git@github.com:Mohit-Sharma-ML/voltio.git
cd voltio

# One-time build prerequisite: your Apple Team ID (free Apple ID works)
cp TeamID.local.example TeamID.local
# edit TeamID.local — replace the placeholder with your Team ID
# (Xcode → Settings → Accounts → team details)

swift build          # quick debug build
swift test           # full test suite
scripts/build_app.sh release   # runnable .app in dist/
open dist/Voltio.app
```

> **Note:** `swift test` must run with the Xcode toolchain. If your machine
> uses [swiftly](https://swift-lang.github.io/swiftly/) or a standalone Swift
> install that shadows Xcode's, prefix with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

After reinstalling the app, open the widget gallery once (Notification
Center → Edit Widgets) so macOS re-caches the widget descriptors — the
system purges third-party widget caches on every reinstall.

## Ground rules

- **Keep PRs focused** — one feature or fix per PR. Small PRs get reviewed
  and merged fast.
- **Test the logic you touch.** `PowerCore` (the telemetry engine) is fully
  unit-tested; keep it that way. App-layer (UI) changes are exempt but
  shouldn't break the build.
- **Run `swift test` before pushing.** CI doesn't exist by design — the
  test suite runs locally and takes seconds.
- **Swift 6 strict concurrency** is on. Avoid `nonisolated(unsafe)` and
  `@preconcurrency` unless you've thought it through; `MainActorIsolation`
  helpers exist for a reason.
- **Keep subprocess/IO work off the main actor** in callback-driven paths
  (IOKit/Bluetooth callbacks run on the main runloop; blocking it stalls
  or crashes the app). Background queue → publish to `@MainActor`.
- **No private API.** Public frameworks only. If a capability is gated
  (see `Docs/gap2-charge-limit.md` for a worked example), document it and
  work with what's public.
- **No new third-party dependencies.** Voltio is deliberately
  dependency-free (see Package.swift). Frameworks that ship with macOS are
  fine.
- **Never commit personal identifiers** — Team IDs go in the gitignored
  `TeamID.local`, never in tracked files (templates use `__TEAM_ID__`
  placeholders substituted at build time).

## Code layout

```
Sources/PowerCore/     battery/energy telemetry engine (pure logic, tested)
Sources/Voltio/        the menu-bar app (SwiftUI + AppKit)
Sources/VoltioWidgets/ the WidgetKit extension
scripts/               build + packaging tooling
Docs/                  engineering notes (widget ingestion, charge-limit)
```

## Versioning & releases

Versions follow [semver](https://semver.org) on **0.x** (minor = features,
patch = fixes). To cut a release:

1. Bump `CFBundleShortVersionString` in **both**
   `Resources/Voltio-Info.plist` and `Resources/VoltioWidgets-Info.plist`
   (keep the two in sync). Bump `CFBundleVersion` (build number) too.
2. Update the README if features/requirements changed.
3. Commit as `chore: bump version to X.Y.Z`, tag `vX.Y.Z`, push with tags:
   `git push --follow-tags`.
4. A maintainer builds the DMG (`scripts/dist.sh` or ad-hoc, see the
   release checklist in `scripts/dist.sh`) and attaches it to the GitHub
   release.

## Reporting issues

Include: macOS version, Mac model, and console output from
`log show --last 5m --predicate 'process == "Voltio"'` if the app itself is
misbehaving. Battery-data oddities (wrong %, missing peripherals) should
mention which device and how it's connected (internal / BLE / HID).

## License

By contributing, you agree that your contributions are licensed under the
MIT License alongside the rest of the project.
