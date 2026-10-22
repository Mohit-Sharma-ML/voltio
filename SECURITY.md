# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately via either:

- GitHub's [private vulnerability reporting](https://github.com/Mohit-Sharma-ML/voltio/security/advisories/new) (preferred), or
- Email **Mohit-Sharma-ML@users.noreply.github.com**

Include what you found, how to reproduce it, and the Voltio version (Settings → About or the menu-bar panel footer). You can expect an initial response within about a week; this is a personal project maintained in spare time.

## Supported versions

Fixes land on the latest released version. Older releases are not patched — please update before reporting.

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older releases | ❌ |

## Security design

Voltio is designed to hold a deliberately small attack surface. Useful context when evaluating a report:

- **No network access.** The app makes zero network calls; there is no networking code in the codebase and no network entitlement.
- **No third-party dependencies.** `Package.swift` declares none, so there is no supply-chain surface and no `Package.resolved`.
- **App Sandbox enabled** with three entitlements: `app-sandbox`, one App Group (widget data), and `device.bluetooth`. Custom alert-sound import additionally uses `files.user-selected.read-only`, and picked files are copied into the app container.
- **No Accessibility, Screen Recording, Input Monitoring, or Automation (Apple Events) permissions.** Global hotkeys use `RegisterEventHotKey`, which requires none of them.
- **One subprocess, with a fixed path and fixed arguments.** `pmset -g battlimit` is spawned to read the macOS charge limit. No shell is involved and no user-controlled value reaches its arguments.
- **All telemetry stays local.** Battery readings, device names, and energy history are stored in the app container and are never transmitted.

## Release integrity

The DMG is built and signed locally from the tagged commit — GitHub Actions has
no signing certificate, and ad-hoc signing breaks the widget extension, so CI
verifies the tag rather than producing the artifact.

Each release includes:

- a **`Voltio.dmg.sha256`** file, and
- the SHA-256 in the release notes.

CI independently checks that a tag matches the bundled version in both the app and
widget plists, that the changelog documents it, and that the tagged commit is on
`main`. That gates a bad tag, but it does not vouch for the uploaded binary — the
checksum is what ties the published file to the release notes.

Releases are currently **not notarized** (that requires a paid Apple Developer account), so Gatekeeper will warn on first launch. Verify the checksum before opening the DMG:

```bash
shasum -a 256 ~/Downloads/Voltio.dmg
# compare with the SHA-256 in the release notes
```
