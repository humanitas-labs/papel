#!/bin/sh
# Builds Papel (Release, ad-hoc signed) and packages it into a compressed
# DMG with an /Applications shortcut. Output: dist/Papel-<version>.dmg
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.2.0}"
DERIVED="${DERIVED_DATA:-build/dd}"
STAGE="build/dmg-stage"
OUT="dist/Papel-$VERSION.dmg"

xcodegen generate
xcodebuild build -project Papel.xcodeproj -scheme Papel -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$DERIVED/Build/Products/Release/Papel.app" "$STAGE/Papel.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Papel" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
rm -rf "$STAGE"
echo "$OUT"
shasum -a 256 "$OUT"
