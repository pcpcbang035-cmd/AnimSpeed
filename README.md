# AnimSpeed

A jailbreak tweak that speeds up iOS system animations by writing directly to
UIKitCore's `UIAnimationDragCoefficient` — the global multiplier every UIKit
animation duration is scaled by (1.0 = stock speed).

Instead of hooking dozens of animation entry points, AnimSpeed disassembles
`_SetUIAnimationDragCoefficient` at load time to locate the coefficient global
and writes `1/N` into it, where `N` is your desired speed multiplier. This
covers app open/close, folders, the app switcher, Control Center, and other
SpringBoard animations in one shot.

## Requirements

- A rootless or roothide jailbreak (tested target: iOS 15+)
- arm64e device (A12 and newer)

## Installation

Install the `.deb` with your package manager (Sileo / Zebra) and respring.
Two package flavors are built:

| Flavor | Architecture | Install path |
|---|---|---|
| rootless | `iphoneos-arm64` | `/var/jb/...` |
| roothide | `iphoneos-arm64e` | relative to the jailbreak root |

## Configuration

Create `/var/mobile/Library/Preferences/com.ho.animspeed.plist`:

```xml
<dict>
	<key>Speed</key>
	<real>80</real>
</dict>
```

`Speed` is the multiplier (default `80`). Respring after changing it.

Set `DiagnosticMarker` to `false` to disable the diagnostic marker
described below.

## Verifying installation

After installing and respringing, check the diagnostic marker the tweak
writes on load:

```sh
cat /var/mobile/Library/Preferences/com.ho.animspeed.loaded
```

Expected contents:

```
mult=80.000
coef=0.012500
drag_write=ok
2026-10-16 11:20:00 +0000
```

- `mult` — the speed multiplier read from your prefs
- `coef` — the coefficient actually written (`1/mult`)
- `drag_write` — `ok` (write succeeded), `failed` (global not located),
  or `skipped` (stock 1.0, intentionally untouched)

If this file exists, AnimSpeed injected into SpringBoard and ran.
If it is missing, the tweak never loaded — see Troubleshooting.

To confirm the speedup is active, open/close an app or pull down
Control Center: animations should be visibly faster than stock.
Don't trust feel alone — trust the marker file.

## Troubleshooting

**Marker file missing**

The tweak never got injected. Common causes:

- Wrong package flavor for your jailbreak: rootless jailbreaks
  (Dopamine) need the `iphoneos-arm64` build; roothide-based jailbreaks
  need the `iphoneos-arm64e` build. Installing the wrong one silently
  does nothing.
- Tweak injection itself is broken in your jailbreak environment.
  This has been observed on some Relaxin (roothide) setups where
  *no* SpringBoard tweak loads — not specific to AnimSpeed. If even
  well-known tweaks have no effect, the problem is environmental.
- Make sure you resprang after installing (not just respring via
  Settings — use your jailbreak app's userspace reboot if unsure).

**Animations feel unchanged**

- Check the marker file first (above). No marker = not loaded.
- `drag_write=failed` means the coefficient global could not be located
  on your iOS version — file an issue with your iOS version and device.
- Extremely high multipliers (200x+) can look identical to 80x on
  some animations because iOS clamps very short durations.
  If 80x feels the same as stock, the tweak is almost certainly
  not loaded rather than "not fast enough".

## Testing status & known limitations

Honest state of the project:

- **On-device verification of the speedup effect is still pending.**
  The coefficient technique is ported from SBTweaker (MIT), whose
  discovery code has shipped in production; the AnimSpeed packaging,
  preference wiring, and default 80x multiplier are exercised through the
  diagnostic marker path, not yet through a device report. Device reports
  welcome — see "Contributing".
- Requires a jailbreak with **working SpringBoard tweak injection**. If no
  SpringBoard tweak loads on your setup (broken or archived loader), AnimSpeed
  cannot work either — fix the loader first.
- The iOS 18+ revision-gate path is handled by the discovery code but
  untested on iOS 18/26 hardware.
- Speeds above ~200x make most animations effectively instant; some system
  UI may behave oddly — that's expected, not a bug.

## Building

`build.sh` builds with upstream clang + cctools-port ld64 on Linux
(no Xcode/theos required):

```sh
./build.sh              # rootless package
ROOTHIDE=1 ./build.sh   # roothide package
```

## How it works

`UIAnimationDragCoefficient` lives in UIKitCore. On iOS 17 it is a plain
32-bit float; on iOS 18+ it is a double behind a revision gate. Rather than
calling the private setter (which may be gated or absent), AnimSpeed
disassembles `_SetUIAnimationDragCoefficient`, finds the `STR` that stores the
value, and writes the coefficient directly — satisfying the revision gate on
newer iOS versions.

A stock value (1.0) is never written, so enabling the tweak at 1x cannot
clobber another tweak's override.

## Contributing

Device test reports are the most valuable contribution right now: install the
`.deb`, set a Speed, respring, and tell us whether animations actually got
faster (iOS version, device, jailbreak type — Dopamine rootless vs roothide,
and which package flavor you installed; paste the marker file contents).
Bug fixes, small features, and docs edits are welcome via pull request.

## Credits

- Drag-coefficient discovery code ported from [SBTweaker](https://github.com/kolbicz/sbtweaker) by kolbicz (MIT). See the `NOTICE` block in `Tweak.m`.

## License

MIT — see [LICENSE](LICENSE).
