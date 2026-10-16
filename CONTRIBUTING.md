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
- **No new third-party dependencies.** Voltio is deliberately
  dependency-free (see Package.swift). Frameworks that ship with macOS are
  fine.

## Code layout

```
Sources/PowerCore/     battery/energy telemetry engine (pure logic, tested)
Sources/Voltio/        the menu-bar app (SwiftUI + AppKit)
Sources/VoltioWidgets/ the WidgetKit extension
scripts/               build + packaging tooling
```

## Reporting issues

Include: macOS version, Mac model, and console output from
`log show --last 5m --predicate 'process == "Voltio"'` if the app itself is
misbehaving. Battery-data oddities (wrong %, missing peripherals) should
mention which device and how it's connected (internal / BLE / HID).

## License

By contributing, you agree that your contributions are licensed under the
MIT License alongside the rest of the project.
