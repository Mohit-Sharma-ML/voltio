#!/usr/bin/env bash
#
# Package Voltio into a distributable DMG.
#
# Two signing modes:
#
# ── Free signing (default) ────────────────────────────────────────────────────
#   scripts/dist.sh
#   Uses the ad-hoc/development signature from build_app.sh. The DMG works,
#   but Gatekeeper warns on first launch — users right-click → Open (once).
#   This is how the GitHub release artifacts are built.
#
# ── Developer ID + notarization (requires paid Apple Developer Program) ──────
#   1. Create a "Developer ID Application" certificate (developer.apple.com or
#      Xcode → Settings → Accounts) and confirm it in your keychain:
#         security find-identity -v -p codesigning
#   2. Store notarization credentials as a reusable keychain profile:
#         xcrun notarytool store-credentials voltio-notary \
#           --apple-id "you@example.com" \
#           --team-id  "YOURTEAMID" \
#           --password "xxxx-xxxx-xxxx-xxxx"
#   3. Run:
#         DEV_ID_APP="Developer ID Application: Your Name (TEAMID)" \
#           [NOTARY_PROFILE=voltio-notary] scripts/dist.sh
#   The result is dist/Voltio.dmg, signed + notarized + stapled — Gatekeeper-
#   clean for end users. Both the app and nested appex must carry the SAME
#   Team ID: if your Developer ID team differs from TeamID.local, re-run
#   build_app.sh with that Team ID first.
#
# The result is dist/Voltio.dmg.
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
	echo "==> DEV_ID_APP not set — free signing mode (ad-hoc signature)."
	echo "    Users will need to right-click → Open on first launch."
	FREE_SIGN=1
else
	FREE_SIGN=0
fi

# 1. Build the release bundle (ad-hoc signed; Developer ID mode re-signs below).
"$ROOT/scripts/build_app.sh" "$CONFIG"

if [[ "$FREE_SIGN" -eq 0 ]]; then
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
fi

# 3. Assemble a DMG with a drag-to-Applications layout.
echo "==> Creating DMG…"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# 4. Notarize the DMG and wait for the result (Developer ID mode only).
if [[ "$FREE_SIGN" -eq 0 ]]; then
	echo "==> Submitting for notarization (this can take a few minutes)…"
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

	# 5. Staple the ticket to both the DMG and the app (offline Gatekeeper).
	echo "==> Stapling notarization ticket…"
	xcrun stapler staple "$DMG"
	xcrun stapler staple "$APP"

	# 6. Final Gatekeeper assessment.
	echo "==> Gatekeeper assessment:"
	spctl --assess --type open --context context:primary-signature -v "$DMG" || true
else
	echo "==> Skipping notarization (free signing mode)."
	echo "    First launch: right-click Voltio.app → Open (Gatekeeper)."
fi

echo "==> Done: $DMG"
