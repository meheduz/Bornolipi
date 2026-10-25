#!/bin/bash
# Notarizes and staples the DMG made by scripts/make-dmg.sh from a Developer ID signed build.
# One-time setup (stores credentials in your keychain):
#   xcrun notarytool store-credentials bangla-phonetic --apple-id you@example.com --team-id TEAMID
# Then:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build.sh
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/make-dmg.sh
#   NOTARY_PROFILE=bangla-phonetic scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"
VERSION="${VERSION:-$(cat VERSION)}"
DMG="build/Bornolipi-$VERSION.dmg"
codesign --verify --deep --strict --verbose=2 "build/Bornolipi.app"
codesign -dvv "build/Bornolipi.app" 2>&1 | grep -q "Authority=Developer ID Application" \
    || { echo "build/Bornolipi.app is not signed with a Developer ID; see scripts/build.sh"; exit 1; }
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
shasum -a 256 "$DMG"
