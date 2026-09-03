# Build Papel

Papel uses [XcodeGen](https://github.com/yonaskolb/XcodeGen); the project file is generated from `project.yml`.

```bash
xcodegen generate
xcodebuild -project Papel.xcodeproj -scheme Papel -configuration Release build
```

## Tests

```bash
xcodebuild -project Papel.xcodeproj -scheme Papel \
  -destination 'platform=macOS' test
```

The build is warning-free. Tests cover byte-exact round trips, concealment geometry (line and document height never change on reveal), list and quote layout, undo paths, and the invariant that styling never edits the text. Setting `TEST_RUNNER_PAPEL_PROBE_DIR=<dir>` additionally writes offscreen renders and restyle timings there for review. The README screenshot is one of those renders.

## Release

Pushing a tag `vX.Y.Z` runs [`.github/workflows/release.yml`](../.github/workflows/release.yml), which builds a universal Release, signs it with the Developer ID, notarizes and staples the app and the DMG through `scripts/make-dmg.sh`, and publishes a GitHub release named `Papel X.Y.Z` with the notes taken from that version's section of `CHANGELOG.md`. The DMG is attached twice: as `Papel-X.Y.Z.dmg` and as `Papel.dmg`, the name the landing page's Download button fetches from `releases/latest/download/`.

To cut a release: bump `MARKETING_VERSION` in `project.yml`, retitle the changelog's Unreleased section `## X.Y.Z — YYYY.MM.DD`, commit, then `git tag -a vX.Y.Z -m "Papel X.Y.Z" && git push origin master vX.Y.Z`.

The workflow reads five repository secrets, listed at the top of the workflow file: the Developer ID Application certificate as a base64 `.p12` with its export password, and the App Store Connect API key as a base64 `.p8` with its Key ID and Issuer ID. Locally, `scripts/make-dmg.sh X.Y.Z` does the same build with the identity from the keychain and `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` in the environment.
