#!/usr/bin/env bash
#
# Assemble a runnable macOS .app bundle from the SwiftPM `Voltio` executable.
# Local development build: signed with the personal Apple Development identity
# (team-ID-backed signatures are required for the widget's App Group access),
# non-sandboxed host, sandboxed widget extension.
#
# Usage: scripts/build_app.sh [debug|release]
#
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Voltio"
WIDGET_NAME="VoltioWidgets"

# Ensure the Xcode toolchain is used. A bare `swift` can resolve to the system
# CommandLineTools (5.9) or a swiftly-managed shim, both of which reject this
# package's swift-tools-version 6.0 — and DEVELOPER_DIR alone doesn't redirect
# those. Invoke the toolchain's swift binary directly instead.
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
	echo "error: DEVELOPER_DIR not found at $DEVELOPER_DIR" >&2
	echo "       Set DEVELOPER_DIR to your Xcode.app developer directory." >&2
	exit 1
fi
export DEVELOPER_DIR
SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
if [[ ! -x "$SWIFT" ]]; then
	echo "error: swift not found at $SWIFT" >&2
	exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- macOS SDK metadata ---
# SPM records the deployment target as the linked SDK in LC_BUILD_VERSION
# (sdk 15.0 instead of the real SDK). That stale metadata makes macOS enable
# legacy compatibility behavior, which breaks the widget extension: chronod
# fails the descriptor handshake and the widget never appears in the gallery.
# Supply both versions to the linker explicitly (same fix as CodexBar #1173).
MACOS_MINIMUM_VERSION="15.0"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MACOS_BUILD_ARGS=(
	--sdk "$MACOS_SDK_PATH"
	-Xlinker -platform_version
	-Xlinker macos
	-Xlinker "$MACOS_MINIMUM_VERSION"
	-Xlinker "$MACOS_SDK_VERSION"
)
echo "==> Building with SDK $MACOS_SDK_VERSION (deployment target $MACOS_MINIMUM_VERSION)"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
PLUGINS_DIR="$CONTENTS/PlugIns"
APPEX="$PLUGINS_DIR/${WIDGET_NAME}.appex"
INFO_PLIST_SRC="$ROOT/Resources/${APP_NAME}-Info.plist"
WIDGET_INFO_PLIST_SRC="$ROOT/Resources/${WIDGET_NAME}-Info.plist"
WIDGET_ENTITLEMENTS_SRC="$ROOT/Resources/${WIDGET_NAME}.entitlements"

# --- Team ID (build-time configuration) ---
# Every contributor signs with their own Apple Team ID. It is NOT hardcoded
# in source: put it in TeamID.local (gitignored — see TeamID.local.example).
# It is required because the App Group container must be team-ID-prefixed
# for the sandboxed widget extension to access it.
TEAM_ID_FILE="$ROOT/TeamID.local"
if [[ ! -f "$TEAM_ID_FILE" ]]; then
	echo "error: $TEAM_ID_FILE not found." >&2
	echo "       Create it with your Apple Team ID (10 chars, from" >&2
	echo "       Xcode → Settings → Accounts, or developer.apple.com → Membership)." >&2
	echo "       See TeamID.local.example." >&2
	exit 1
fi
TEAM_ID="$(tr -d '[:space:]' < "$TEAM_ID_FILE")"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
	echo "error: Team ID '$TEAM_ID' in TeamID.local doesn't look valid" >&2
	echo "       (expected 10 uppercase alphanumeric characters)." >&2
	exit 1
fi
echo "==> Using Team ID: $TEAM_ID"

# Generated (per-build) copies with the team ID substituted. The checked-in
# *.entitlements files stay as __TEAM_ID__ templates.
ENTITLEMENTS_BUILD_DIR="$ROOT/.build/entitlements"
mkdir -p "$ENTITLEMENTS_BUILD_DIR"
HOST_ENTITLEMENTS="$ENTITLEMENTS_BUILD_DIR/${APP_NAME}.entitlements"
WIDGET_ENTITLEMENTS_GENERATED="$ENTITLEMENTS_BUILD_DIR/${WIDGET_NAME}.entitlements"
sed "s/__TEAM_ID__/$TEAM_ID/g" "$ROOT/Resources/${APP_NAME}.entitlements" > "$HOST_ENTITLEMENTS"
sed "s/__TEAM_ID__/$TEAM_ID/g" "$WIDGET_ENTITLEMENTS_SRC" > "$WIDGET_ENTITLEMENTS_GENERATED"

# Stamp the Team ID into build-time COPIES of the Info.plists (the checked-in
# templates stay team-ID-free). WidgetConfiguration reads the key at runtime
# to build the App Group suite name.
VOLTIO_TEAM_ID_KEY="VoltioTeamID"
BUILD_RES_DIR="$ROOT/.build/resources"
mkdir -p "$BUILD_RES_DIR"
HOST_INFO_PLIST="$BUILD_RES_DIR/${APP_NAME}-Info.plist"
WIDGET_INFO_PLIST="$BUILD_RES_DIR/${WIDGET_NAME}-Info.plist"
cp "$INFO_PLIST_SRC" "$HOST_INFO_PLIST"
cp "$WIDGET_INFO_PLIST_SRC" "$WIDGET_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :$VOLTIO_TEAM_ID_KEY string $TEAM_ID" "$HOST_INFO_PLIST" 2>/dev/null ||
	/usr/libexec/PlistBuddy -c "Set :$VOLTIO_TEAM_ID_KEY $TEAM_ID" "$HOST_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :$VOLTIO_TEAM_ID_KEY string $TEAM_ID" "$WIDGET_INFO_PLIST" 2>/dev/null ||
	/usr/libexec/PlistBuddy -c "Set :$VOLTIO_TEAM_ID_KEY $TEAM_ID" "$WIDGET_INFO_PLIST"

echo "==> Building $APP_NAME ($CONFIG)…"
"$SWIFT" build -c "$CONFIG" --disable-sandbox --product "$APP_NAME" "${MACOS_BUILD_ARGS[@]}"

echo "==> Building $WIDGET_NAME ($CONFIG)…"
"$SWIFT" build -c "$CONFIG" --disable-sandbox --product "$WIDGET_NAME" "${MACOS_BUILD_ARGS[@]}"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
	echo "error: built binary not found at $BIN" >&2
	exit 1
fi

WIDGET_BIN="$ROOT/.build/$CONFIG/$WIDGET_NAME"
if [[ ! -f "$WIDGET_BIN" ]]; then
	echo "error: built widget binary not found at $WIDGET_BIN" >&2
	exit 1
fi

echo "==> Assembling bundle at ${APP}"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR" "$PLUGINS_DIR"

cp "$BIN" "$MACOS_DIR/$APP_NAME"
cp "$HOST_INFO_PLIST" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Optional icon: dropped in by scripts/make_icon.sh if present.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
	cp "$ROOT/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || true
fi

# --- Widget extension (.appex) ---
echo "==> Assembling widget extension at ${APPEX}"
APPEX_CONTENTS="$APPEX/Contents"
APPEX_MACOS_DIR="$APPEX_CONTENTS/MacOS"
APPEX_RES_DIR="$APPEX_CONTENTS/Resources"
mkdir -p "$APPEX_MACOS_DIR" "$APPEX_RES_DIR"

cp "$WIDGET_BIN" "$APPEX_MACOS_DIR/$WIDGET_NAME"
cp "$WIDGET_INFO_PLIST" "$APPEX_CONTENTS/Info.plist"
printf 'BNDL????' > "$APPEX_CONTENTS/PkgInfo"

# Sign the extension BEFORE the host app: embedding an unsigned appex makes
# the outer codesign fail, and re-signing the host would invalidate a
# previously-signed nested extension.
#
# Signed with the personal "Apple Development" identity, NOT ad-hoc: the
# sandboxed widget extension can only access its App Group container when the
# signature carries a Team ID (containermanagerd rejects team-less signatures).
# Override with CODE_SIGN_IDENTITY=… if needed; "-" (ad-hoc) breaks the widget.
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
# Hardened runtime is required: chronod (widget host daemon) classifies
# extensions signed without it as "restricted or unknown" and refuses to
# ingest their widget descriptors (widgets never appear in the gallery).
echo "==> Code signing with identity: $SIGN_IDENTITY (hardened runtime)"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none --entitlements "$WIDGET_ENTITLEMENTS_GENERATED" "$APPEX"
codesign --verify --verbose "$APPEX"

codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none --entitlements "$HOST_ENTITLEMENTS" "$APP"
codesign --verify --verbose "$APP"

echo "==> Done: $APP"
