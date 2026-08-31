#!/bin/sh
# Builds Paper (Release, ad-hoc signed) and packages it into a compressed
# DMG with an /Applications shortcut. Output: dist/Paper-<version>.dmg
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.2.0}"
DERIVED="${DERIVED_DATA:-build/dd}"
STAGE="build/dmg-stage"
OUT="dist/Paper-$VERSION.dmg"

xcodegen generate
xcodebuild build -project Paper.xcodeproj -scheme Paper -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$DERIVED/Build/Products/Release/Paper.app" "$STAGE/Paper.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Paper" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
rm -rf "$STAGE"
echo "$OUT"
shasum -a 256 "$OUT"
