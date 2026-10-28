# Changelog

All notable changes to AnimSpeed are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.5] - 2026-10-28

### Fixed
- `drag_discovery.h`: the scanner's ADD (immediate) branch now honors
  the LSL #12 shift bit (bit 22). Previously it used the raw imm12
  unconditionally, so a setter that reached its global with e.g.
  `ADD X8, X8, #1, LSL #12` resolved the base as page + 1 instead of
  page + 0x1000 — pointing the coefficient writer at the wrong
  address. Covered by a new host test (`double/gated ADD LSL #12` in
  `tests/test_discovery.c`), which fails against the old scanner
  (`g=...9001` instead of `...a000`) and passes with the fix.

## [2.4] - 2026-10-25

### Fixed
- `drag_discovery.h`: the iOS 18+ revision-gate sentinel (`STR Wt`) now
  resolves its base the same way the `STR Dt`/`STR St` branches do
  (ADD-computed value if present, otherwise the ADRP page). Previously
  it required an ADD-computed base, so a setter that used ADRP alone
  for the coefficient base left `revOff = 0` — and the gated writer
  would then stamp the revision value `0x7fffffff` onto the
  coefficient base itself instead of the revision field. Covered by a
  new host test (`double/gated ADRP-only` in `tests/test_discovery.c`),
  which fails against the old scanner and passes with the fix.
- `tests/test_discovery.c`: each test now reports its own pass/fail
  status instead of the cumulative failure count, so a failure in an
  earlier test no longer mislabels later passing tests as FAIL.

## [2.3] - 2026-10-22

### Added
- Host-side unit tests for the disassembly scanner
  (`tests/test_discovery.c`): synthetic ARM64 setter bodies for the
  iOS 17 float/ungated and iOS 18+ double/gated patterns plus a
  no-match negative case. Run with
  `cc -std=c99 -Wall -Wno-unused-function -I. tests/test_discovery.c -o /tmp/test_discovery && /tmp/test_discovery`
  — no device needed.

### Changed
- The drag-coefficient discovery core moved from `Tweak.m` into
  `drag_discovery.h` as pure C (`animspeed_scan_drag`), so the
  instruction-pattern matching is unit-testable on the host.
  Runtime behavior is unchanged (verified by the new tests and a
  full arm64e rebuild).
- `build.sh` now runs the host unit tests fail-fast before
  compiling; the build aborts if the scanner regresses
  (`SKIP_TESTS=1` to opt out).

## [2.2] - 2026-10-19

### Fixed
- `build.sh`: the `ld` linker lookup no longer hardcodes a
  `/home/hatch/...` path — it probes `$LD_BIN` (env override),
  `$HOME/toolchains/cctools/bin/ld`, `$HOME/toolchains/bin/ld`,
  then `PATH`, so the script works on a contributor's machine too.
- `build.sh`: the `.deb` filename now embeds the version from
  `control` (e.g. `AnimSpeed-v2.2-rootless-...`) instead of a
  hardcoded `v2`, so builds of different releases stay distinguishable.

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
