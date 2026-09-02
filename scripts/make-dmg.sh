#!/bin/sh
# Builds Papel (Release) and packages it into a compressed DMG with an
# /Applications shortcut. Output: dist/Papel-<version>.dmg
#
# With a "Developer ID Application" identity in the keychain the app is
# signed with the hardened runtime, and with notary credentials in the
# environment the app and the DMG are notarized and stapled:
#
#   NOTARY_KEY=~/.private/papel-notary.p8   App Store Connect API key (.p8)
#   NOTARY_KEY_ID=ABC123DEFG                 its Key ID
#   NOTARY_ISSUER_ID=xxxxxxxx-...            the team's Issuer ID
#
# Without the identity the build is ad-hoc signed, as before; without the
# credentials it is signed but not notarized. Either case is reported.
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.2.0}"
DERIVED="${DERIVED_DATA:-build/dd}"
STAGE="build/dmg-stage"
OUT="dist/Papel-$VERSION.dmg"

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"

xcodegen generate
if [ -n "$IDENTITY" ]; then
  TEAM="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
  echo "Signing as: $IDENTITY"
  xcodebuild build -project Papel.xcodeproj -scheme Papel -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet
else
  echo "No Developer ID Application identity in the keychain; ad-hoc signing."
  xcodebuild build -project Papel.xcodeproj -scheme Papel -configuration Release \
    -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet
fi

APP="$DERIVED/Build/Products/Release/Papel.app"

notarize() {
  # $1: the file to submit. Waits, then staples. Fails the build on rejection.
  xcrun notarytool submit "$1" --wait \
    --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  xcrun stapler staple "$1"
}

CAN_NOTARIZE=0
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
  CAN_NOTARIZE=1
fi

if [ "$CAN_NOTARIZE" = 1 ]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  ZIP="build/Papel-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
elif [ -n "$IDENTITY" ]; then
  echo "NOTARY_KEY / NOTARY_KEY_ID / NOTARY_ISSUER_ID not set; signed but not notarized."
fi

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/Papel.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Papel" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
rm -rf "$STAGE"

if [ -n "$IDENTITY" ]; then
  codesign --sign "$IDENTITY" --timestamp "$OUT"
fi
if [ "$CAN_NOTARIZE" = 1 ]; then
  notarize "$OUT"
  spctl -a -vv -t open --context context:primary-signature "$OUT" || true
fi

echo "$OUT"
shasum -a 256 "$OUT"
