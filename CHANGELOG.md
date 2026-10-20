# Changelog

All notable changes to Voltio are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/); the project uses [Semantic Versioning](https://semver.org/).

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

[Unreleased]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.3.0...v0.3.2
[0.3.0]: https://github.com/Mohit-Sharma-ML/voltio/compare/v0.2.0...v0.3.0
