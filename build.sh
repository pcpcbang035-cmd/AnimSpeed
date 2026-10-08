#!/bin/bash
# AnimSpeed 构建脚本：Linux 上游 clang + cctools-port ld64，arm64e 单架构（A12+，含 SE2 的 A13）
# rootless（Dopamine），纯 ObjC，无 Logos/theos
set -e
cd "$(dirname "$0")"

for d in "$HOME"/toolchains/llvm/clang+llvm-*/bin "$HOME"/toolchains/bin; do
    [ -d "$d" ] && export PATH="$d:$PATH"
done
command -v clang >/dev/null || { echo "找不到 clang"; exit 1; }
export LD_LIBRARY_PATH="$HOME/toolchains/lib:$HOME/toolchains/dispatch/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

SDK="${SDK:-$HOME/toolchains/sdks/iPhoneOS9.3.sdk}"
LD_BIN="${LD_BIN:-/home/hatch/toolchains/cctools/bin/ld}"
FAKESDK="${FAKESDK:-$HOME/toolchains/fakesdk}"
OUT="$PWD/build"
STAGE="$OUT/stage"

[ -d "$SDK" ] || { echo "找不到 SDK: $SDK"; exit 1; }
[ -x "$LD_BIN" ] || { echo "找不到 ld64: $LD_BIN"; exit 1; }
[ -f "$FAKESDK/usr/lib/libSystem.dylib" ] || { echo "找不到 stub sysroot: $FAKESDK"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT" "$STAGE"

COMMON="-miphoneos-version-min=15.0 -isysroot $SDK -fno-objc-arc -fblocks -O2 -Wall"
LINKFLAGS="-fuse-ld=$LD_BIN -Wl,-syslibroot,$FAKESDK -undefined dynamic_lookup"

# 打包模式：
#   ROOTHIDE=1 → 隐根包：文件装到 ./Library/...（相对随机根目录），Architecture=iphoneos-arm64e，
#                 用 Sileo/Zebra/Filza 直接安装，无需转换器（照抄 sbtweaker 隐根包格式）
#   默认      → 标准 rootless：./var/jb/...，Architecture=iphoneos-arm64
if [ "${ROOTHIDE:-0}" = "1" ]; then
    DESTDIR="Library/MobileSubstrate/DynamicLibraries"
    ARCH_FIELD="iphoneos-arm64e"
    TAG="roothide"
    INSTALL_NAME="/Library/MobileSubstrate/DynamicLibraries/AnimSpeed.dylib"
else
    DESTDIR="var/jb/Library/MobileSubstrate/DynamicLibraries"
    ARCH_FIELD="iphoneos-arm64"
    TAG="rootless"
    INSTALL_NAME="/var/jb/Library/MobileSubstrate/DynamicLibraries/AnimSpeed.dylib"
fi

echo "== 编译 Tweak.m (arm64e) =="
clang --target=arm64e-apple-ios $COMMON -arch arm64e -c Tweak.m -o "$OUT/Tweak-arm64e.o"
echo "== 链接 AnimSpeed.dylib =="
clang --target=arm64e-apple-ios $COMMON -arch arm64e -dynamiclib \
    -o "$OUT/AnimSpeed.dylib" "$OUT/Tweak-arm64e.o" \
    $LINKFLAGS \
    -install_name "$INSTALL_NAME"

# 签名（workspace 文件系统不支持 mmap 写入，经 /tmp 中转）
if command -v ldid >/dev/null 2>&1; then
    echo "== ldid 签名 =="
    if cp "$OUT/AnimSpeed.dylib" /tmp/ldid_tmp.bin && ldid -S /tmp/ldid_tmp.bin; then
        cat /tmp/ldid_tmp.bin > "$OUT/AnimSpeed.dylib"
    else
        echo "ldid 签名失败（继续，未签名在越狱环境通常也可加载）"
    fi
    rm -f /tmp/ldid_tmp.bin
else
    echo "== 未找到 ldid，跳过签名 =="
fi

echo "== 组装 deb 目录（$TAG: $DESTDIR） =="
mkdir -p "$STAGE/$DESTDIR"
cp "$OUT/AnimSpeed.dylib" "$STAGE/$DESTDIR/"
cp AnimSpeed.plist        "$STAGE/$DESTDIR/"
mkdir -p "$STAGE/DEBIAN"
sed "s/^Architecture:.*/Architecture: $ARCH_FIELD/" DEBIAN/control > "$STAGE/DEBIAN/control"
chmod 0755 "$STAGE/DEBIAN"
chmod 0644 "$STAGE/DEBIAN/control"
chmod 0755 "$STAGE/$DESTDIR/AnimSpeed.dylib"
chmod 0644 "$STAGE/$DESTDIR/AnimSpeed.plist"
find "$STAGE/$(echo "$DESTDIR" | cut -d/ -f1)" -type d -exec chmod 0755 {} +

# 文件名每次构建都唯一（用户要求：每次发的包换个新名字）
STAMP="$(date +%Y%m%d-%H%M%S)"
RAND="$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
DEB="$OUT/AnimSpeed-v2-${TAG}-${STAMP}-${RAND}.deb"
dpkg-deb -Zgzip -b "$STAGE" "$DEB" >/dev/null
echo "== 完成 =="
ls -la "$DEB"
file "$OUT/AnimSpeed.dylib"
