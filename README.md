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

## Verifying installation

After installing and respringing, check that the tweak actually loaded:

```sh
ls -l /var/mobile/AnimSpeed.loaded
```

If this file exists, AnimSpeed injected into SpringBoard successfully.
If it is missing, the tweak is not running — see Troubleshooting below.

To confirm the speedup is active, open/close an app or pull down
Control Center: animations should be visibly faster than stock.

## Troubleshooting

**Marker file missing (`/var/mobile/AnimSpeed.loaded` does not exist)**

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
- Extremely high multipliers (200x+) can look identical to 80x on
  some animations because iOS clamps very short durations.
  If 80x feels the same as stock, the tweak is almost certainly
  not loaded rather than "not fast enough".

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

## Credits

- Drag-coefficient discovery code ported from [SBTweaker](https://github.com/kolbicz/sbtweaker) by kolbicz (MIT). See the `NOTICE` block in `Tweak.m`.

## License

MIT — see [LICENSE](LICENSE).
