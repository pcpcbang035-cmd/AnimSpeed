# Changelog

All notable changes to AnimSpeed are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
