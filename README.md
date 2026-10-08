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
