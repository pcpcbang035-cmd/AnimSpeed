# Changelog

All notable changes to AnimSpeed are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.1] - 2026-10-16

### Added
- Diagnostic load marker: after init, the tweak writes
  `/var/mobile/Library/Preferences/com.ho.animspeed.loaded` recording the
  requested multiplier (`mult`), the coefficient written (`coef`), and
  whether the drag-global write succeeded (`drag_write`: `ok` / `failed` /
  `skipped`) — the anti-placebo device for on-device verification.
  Disable with `DiagnosticMarker = false` in the prefs plist.
- GitHub issue and pull-request templates (`.github/`)
- README: "Testing status & known limitations" and "Contributing" sections

### Fixed
- The installation-verification step documented since v2.0.1 referenced a
  marker file (`/var/mobile/AnimSpeed.loaded`) that the code never created;
  the README now documents the marker the code actually writes, and the
  troubleshooting section covers the new `drag_write=failed` case.

## [2.0.1] - 2026-10-13

### Added
- README: "Verifying installation" section (load-marker check at
  `/var/mobile/AnimSpeed.loaded`)
- README: "Troubleshooting" section covering wrong-flavor installs and
  broken tweak injection environments
- `CHANGELOG.md` (this file)

### Fixed
- `build.sh`: fail fast with a clear message when `clang`, the iOS SDK,
  or `ld` are missing, instead of dying halfway through the build

## [2.0] - 2026-10-08

### Changed
- Complete rewrite around the real animation-speed mechanism:
  `UIAnimationDragCoefficient` in UIKitCore, set via
  `_SetUIAnimationDragCoefficient` disassembly, instead of the
  `window.layer.speed` placebo used in v1
- Drag-coefficient discovery code ported from
  [SBTweaker](https://github.com/kolbicz/sbtweaker) by kolbicz (MIT);
  see the `NOTICE` block in `Tweak.m`
- Added load marker at `/var/mobile/AnimSpeed.loaded` so users can
  verify injection worked
- Never writes a stock value (1.0), so enabling at 1x cannot clobber
  another tweak's override

## [1.0] - 2026-10-06

### Added
- Initial release using `window.layer.speed` approach
- Later confirmed to be a placebo on iOS 26 (no visible difference
  even at 200x); superseded by v2.0
