# Changelog

All notable changes to Voltio are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/); the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- AirPods no longer disappear from Connected Devices. Ownership was judged by matching the advertisement's name against the paired-device name, but the same hardware reports different names on each side (`Mohit's AirPods - Find My` vs `AirPods 4 (ANC)`), so every advert was discarded. Ownership is now also proven by the paired phone's Bluetooth address carried in the advert, with name matching kept as a fallback.
- AirPods 4 (ANC) battery levels now match macOS. This model broadcasts precise per-compartment percentages in a form the classic nibble decode missed, which showed 50% where macOS reported 59% and dropped the right ear. All three readings — left, right and case — now match what macOS reports, including while charging.
- A single reporting AirPods compartment is labelled (`L 23%`) in the panel and in low-battery alerts, instead of reading as the whole device's charge — e.g. with one pod in its case.
- Denied Bluetooth access is now recoverable. The app previously said to allow Bluetooth without offering a way to do it; macOS never re-prompts after a denial, so the panel and Settings → Devices now offer **Open Bluetooth Settings**.
- "Bluetooth access denied" and "not asked yet" are now distinct states, so diagnostics no longer give a remedy for a prompt that hasn't appeared.

### Added
- BLE diagnostics now report how many nearby devices the ownership gate is hiding and how many paired addresses it can match — the blind spot that made the AirPods bug hard to diagnose.
- Onboarding explains the Bluetooth permission before macOS asks for it.

## [0.6.0] - 2026-10-20

### Fixed
- Battery Health now matches the "Maximum Capacity" percentage macOS reports in System Settings and `system_profiler`. Voltio previously divided the raw pack maximum by design capacity, which read several points low (e.g. 92% where macOS showed 95%).

### Changed
- Custom alert sounds are copied into the app container on import, so they keep working after relaunch and no longer break if the original file is moved or deleted. Missing sound files are now flagged in the picker instead of failing silently.

### Added
- Continuous integration: build and full test suite on every pull request, plus bundle-layout, version-match, and changelog checks.
- Release tag verification: a pushed `v*` tag is checked for version/changelog agreement and `main` ancestry, then a draft release is created for the signed DMG to be attached to.
- `scripts/release_checksum.sh` for generating and verifying DMG checksums, and `RELEASING.md` documenting the release procedure.

## [0.5.0] - 2026-10-20

### Added
- Smooth pulsing glow for the menu-bar bolt while charging.

### Changed
- Battery Indicator uses the same battery outline as Minimal, with large centered percentage digits; three-digit percentages use a more compact rounded style for breathing room.

## [0.4.0] - 2026-10-18

### Added
- Charge ring (and status pill, glow, and border) now take the color of the alert rule that matches the current level — e.g. orange at your 20% rule, red at 10%, or a custom charged color on AC. Falls back to the usual state colors when no rule matches.

### Fixed
- Panel no longer renders a mix of light and dark elements after switching appearance: the theme switch now applies instantly and completely, including Match System.
- Hard brightness line on the left side of the charge ring at high charge levels (~75% and up) — the ring now uses a clean solid fill with its glow.
- Capacity card now distinguishes the two charge scales: the headline percentage follows macOS's fuel gauge, while the Remaining stat shows "NN% of full" derived from the battery pack itself.
- Settings panes render with proper light-mode surfaces instead of hardcoded dark overlays.

## [0.3.2] - 2026-10-14

### Fixed
- Release packaging: attached DMG is built from the tagged commit.

## [0.3.0] - 2026-10-11

### Added
- Configurable battery alerts (low / charged) with custom threshold, color, position, sound, and optional border glow.
- Bluetooth accessory battery levels (AirPods, Magic devices) with per-device alerts.
- Power flow visualization with live wattage and adapter identification.

[Unreleased]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.3.0...v0.3.2
[0.3.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.2.0...v0.3.0
