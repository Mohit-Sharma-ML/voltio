#!/usr/bin/env bash
#
# Assemble release notes that include the DMG's SHA-256, and verify an existing
# checksum file.
#
#   scripts/release_checksum.sh dist/Voltio.dmg          # print SHA-256 + line for notes
#   scripts/release_checksum.sh --verify dist/Voltio.dmg # exit 1 on mismatch
#
# The checksum exists so users can confirm the DMG they downloaded matches the
# one we built — the app is not notarized, so Gatekeeper cannot vouch for it.
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage:
  scripts/release_checksum.sh <path-to-dmg>            print SHA-256
  scripts/release_checksum.sh --verify <path-to-dmg>   verify against <path>.sha256
EOF
	exit 2
}

verify=0
if [[ "${1:-}" == "--verify" ]]; then
	verify=1
	shift
fi
if [[ $# -ne 1 ]]; then usage; fi

DMG="$1"
if [[ ! -f "$DMG" ]]; then
	echo "error: $DMG not found" >&2
	exit 1
fi

actual="$(shasum -a 256 "$DMG" | awk '{print $1}')"

if [[ "$verify" -eq 1 ]]; then
	sumfile="$DMG.sha256"
	if [[ ! -f "$sumfile" ]]; then
		echo "error: $sumfile not found" >&2
		exit 1
	fi
	expected="$(awk '{print $1}' "$sumfile")"
	if [[ "$actual" == "$expected" ]]; then
		echo "✔ checksum matches: $actual"
	else
		echo "✘ checksum MISMATCH" >&2
		echo "  expected: $expected" >&2
		echo "  actual:   $actual" >&2
		exit 1
	fi
	exit 0
fi

printf '%s  %s\n' "$actual" "$(basename "$DMG")" > "$DMG.sha256"
echo "SHA-256: $actual"
echo "wrote $DMG.sha256"
