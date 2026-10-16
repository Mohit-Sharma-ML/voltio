#!/usr/bin/env bash
#
# Render the app icon and compile it into Resources/AppIcon.icns.
# Requires macOS `sips` and `iconutil` (both ship with the OS).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MASTER="$ROOT/Resources/AppIcon-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

echo "==> Rendering master PNG"
# Use the Xcode toolchain's swift (a bare `swift` can resolve to a
# swiftly-managed shim that fails against the current SDK).
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" "$ROOT/scripts/make_icon.swift" "$MASTER"

echo "==> Building iconset"
mkdir -p "$ICONSET"
sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

echo "==> Compiling .icns"
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$(dirname "$ICONSET")"

echo "==> Done: $OUT"
