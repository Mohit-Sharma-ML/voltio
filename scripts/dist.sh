#!/usr/bin/env bash
#
# Build, Developer ID sign, notarize, staple, and package Voltio into a
# distributable, Gatekeeper-approved DMG.
#
# ── One-time setup (requires a paid Apple Developer Program membership) ───────
#   1. In Xcode > Settings > Accounts, or developer.apple.com, create a
#      "Developer ID Application" certificate and install it in your login
#      keychain. Confirm it's present:
#         security find-identity -v -p codesigning
#   2. Create an app-specific password for your Apple ID at appleid.apple.com,
#      then store notarization credentials as a reusable keychain profile:
#         xcrun notarytool store-credentials voltio-notary \
#           --apple-id "you@example.com" \
#           --team-id  "YOURTEAMID" \
#           --password "xxxx-xxxx-xxxx-xxxx"
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   DEV_ID_APP="Developer ID Application: Your Name (TEAMID)" \
#     [NOTARY_PROFILE=voltio-notary] scripts/dist.sh
#
# The result is dist/Voltio.dmg, signed + notarized + stapled.
#
set -euo pipefail

APP_NAME="Voltio"
CONFIG="release"
NOTARY_PROFILE="${NOTARY_PROFILE:-voltio-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
# Generated (team-ID-substituted) entitlements from the build step.
ENTITLEMENTS="$ROOT/.build/entitlements/${APP_NAME}.entitlements"
if [[ ! -f "$ENTITLEMENTS" ]]; then
	echo "error: $ENTITLEMENTS not found." >&2
	echo "       scripts/build_app.sh generates it from TeamID.local — run it first." >&2
	exit 1
fi

if [[ -z "${DEV_ID_APP:-}" ]]; then
	echo "error: DEV_ID_APP is not set." >&2
	echo "       Set it to your Developer ID Application identity, e.g.:" >&2
	echo "         DEV_ID_APP=\"Developer ID Application: Your Name (TEAMID)\" scripts/dist.sh" >&2
	echo "       Available code-signing identities:" >&2
	security find-identity -v -p codesigning >&2 || true
	exit 1
fi

# 1. Build the release bundle (ad-hoc signed; we re-sign below).
"$ROOT/scripts/build_app.sh" "$CONFIG"

# 2. Re-sign with Developer ID + hardened runtime + secure timestamp.
#    Nested code (the widget appex) keeps the signature build_app.sh gave it.
#    For notarization both signatures must carry the SAME Team ID — if your
#    Developer ID team differs from TeamID.local, re-run build_app.sh with
#    that Team ID first.
echo "==> Signing with Developer ID (hardened runtime)…"
codesign --force --options runtime --timestamp \
	--entitlements "$ENTITLEMENTS" \
	--sign "$DEV_ID_APP" \
	"$APP"
codesign --verify --strict --verbose=2 "$APP"

# 3. Assemble a DMG with a drag-to-Applications layout.
echo "==> Creating DMG…"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# 4. Notarize the DMG and wait for the result.
echo "==> Submitting for notarization (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# 5. Staple the ticket to both the DMG and the app (offline Gatekeeper).
echo "==> Stapling notarization ticket…"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

# 6. Final Gatekeeper assessment.
echo "==> Gatekeeper assessment:"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo "==> Done: $DMG"
