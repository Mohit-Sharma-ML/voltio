# Releasing Voltio

The release DMG is built and signed **locally**, on a machine with a signing
certificate. GitHub Actions verifies the tag but never builds the artifact — see
"why not in CI" below.

## Prerequisites

- An **Apple Development** certificate in your keychain
  (`security find-identity -v -p codesigning`).
- `TeamID.local` present with your 10-character Team ID.
- `gh` authenticated to `github.com` as the repo owner.
- Working tree on `main`, clean, and up to date.

## 1. Prepare the version

Both plists must match, and the changelog must have an entry — CI enforces all
three, so do it before tagging.

```bash
git switch main && git pull
```

Edit `Resources/Voltio-Info.plist` **and** `Resources/VoltioWidgets-Info.plist`:

- `CFBundleShortVersionString` → the new version (e.g. `0.6.0`)
- `CFBundleVersion` → the next integer build number

Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md` with user-visible
changes only, and update the `[Unreleased]`/version comparison links at the
bottom.

Commit through a PR (direct pushes to `main` are blocked by the pre-push hook
and branch protection):

```bash
git switch -c chore/release-X.Y.Z
git add Resources/Voltio-Info.plist Resources/VoltioWidgets-Info.plist CHANGELOG.md
git commit -m "chore(release): prepare version X.Y.Z"
git push -u origin chore/release-X.Y.Z
gh pr create --fill && gh pr merge --merge
```

## 2. Build the DMG from merged `main`

```bash
git switch main && git pull
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/dist.sh
```

**Do not set `CODE_SIGN_IDENTITY=-`.** Ad-hoc signing breaks the widget
extension: `containermanagerd` rejects team-less signatures, the widget never
appears in the gallery, and the App Group stops resolving.

Verify what you are about to publish:

```bash
hdiutil attach dist/Voltio.dmg -nobrowse -quiet
plutil -extract CFBundleShortVersionString raw /Volumes/Voltio/Voltio.app/Contents/Info.plist
hdiutil detach /Volumes/Voltio -quiet
codesign -d --entitlements - dist/Voltio.app | grep -c user-selected  # expect 1
```

## 3. Tag and push

The tag triggers the `Release checks` workflow, which verifies the tag matches
the plists, the changelog documents the version, and the commit is on `main`. It
then creates a **draft** release.

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
gh run watch    # confirm "Release checks" passed
```

## 4. Compute the checksum

Every release publishes a SHA-256; the README and `SECURITY.md` both tell users to
verify against it, so this step is not optional.

```bash
scripts/release_checksum.sh dist/Voltio.dmg
cat dist/Voltio.dmg.sha256
```

## 5. Upload and publish

```bash
gh release upload vX.Y.Z dist/Voltio.dmg --clobber
gh release upload vX.Y.Z dist/Voltio.dmg.sha256 --clobber
```

Write the release notes with:

```markdown
### Added / Changed / Fixed
- (one line per user-visible change)

### Install note
This build uses free signing and is not notarized. On first launch, right-click
**Voltio.app → Open** to approve it in Gatekeeper.

**SHA-256**
`<paste the hash>`

[Full changelog](https://github.com/Mohit-Sharma-ML/voltio/blob/vX.Y.Z/CHANGELOG.md)
```

Then publish the draft:

```bash
gh release edit vX.Y.Z --draft=false --notes-file /tmp/notes.md \
  --title "vX.Y.Z — <headline>"
```

## 6. Verify

```bash
gh api repos/Mohit-Sharma-ML/voltio/releases/latest --jq '.tag_name, .assets[].name'
shasum -a 256 ~/Downloads/Voltio.dmg   # compare with the release note
```

Install the published build and confirm the widget appears in the gallery — the
most likely thing to break silently.

---

## Why the DMG is not built in CI

`scripts/build_app.sh` signs with `CODE_SIGN_IDENTITY` (default
`Apple Development`). GitHub-hosted runners have no signing certificate, so the
only option there is ad-hoc (`-`), which the same script documents as breaking the
widget. A CI-built DMG would therefore be a **broken artifact** uploaded under a
correct-looking version number — worse than no automation.

An earlier draft of `.github/workflows/release.yml` did exactly that. It was
replaced with verification-only before it could ship.

Making CI build *real* artifacts requires storing a Developer ID certificate and
its password as repository secrets, plus a rotation plan. That becomes worthwhile
together with notarization (see `Docs/plans/plan-security-release.md` S4).

## Notarized releases (once a paid Apple Developer account exists)

```bash
DEV_ID_APP="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE=voltio-notary \
  scripts/dist.sh
```

`scripts/dist.sh` then signs with the Developer ID, submits to `notarytool`,
staples the ticket, and runs an `spctl` assessment. When this lands you must also:

- remove the right-click-to-open instruction from `README.md`,
- update the release-integrity section of `SECURITY.md`,
- drop the "Install note" paragraph above,
- consider moving signing into CI now that a real certificate is in play.
