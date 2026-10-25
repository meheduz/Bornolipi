#!/bin/bash
# Packs build/Bornolipi.app into build/Bornolipi-<version>.dmg: the app and a shortcut to
# Applications, so installing is a drag. Opening the app then installs and sets up the keyboard.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(cat VERSION)}"
# The public label (for example 0.1.0-beta.1) names the image; the bundles carry the numeric VERSION.
LABEL="${LABEL:-$(cat RELEASE_LABEL 2>/dev/null || echo "$VERSION")}"
# Always rebuild, so the image carries this VERSION and SIGN_IDENTITY rather than an older build.
ARCHS="${ARCHS:-arm64 x86_64}" scripts/build.sh   # release images are universal (Apple Silicon and Intel)
APP_SRC="build/Bornolipi.app"

# Test images (DMG_TEST=1) link "Applications" to a scratch folder and use another volume name, so
# dragging the app in Finder, as the window invites, can never replace the real /Applications/Bornolipi.app.
if [ "${DMG_TEST:-}" = 1 ]; then
    APPS_LINK="$PWD/build/dmg-test-applications"; mkdir -p "$APPS_LINK"
    VOLNAME="Bornolipi Test $LABEL"; DMG="build/Bornolipi-$LABEL-test.dmg"
else
    APPS_LINK="/Applications"   # system-path-ok: the link users drag to; nothing is written there
    VOLNAME="Bornolipi $LABEL"; DMG="build/Bornolipi-$LABEL.dmg"
fi
# DMG_OUT writes the image elsewhere (release candidates), leaving existing images untouched.
if [ -n "${DMG_OUT:-}" ]; then DMG="$DMG_OUT"; mkdir -p "$(dirname "$DMG")"; [ -e "$DMG" ] && { echo "$DMG exists; not overwriting"; exit 1; }; fi
rm -f "$DMG"
# The window layout (background, icon positions) is written by dmgbuild, without scripting Finder:
#   python3 -m venv build/.venv && build/.venv/bin/pip install dmgbuild==1.6.5
DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || echo build/.venv/bin/dmgbuild)}"
if [ -x "$DMGBUILD" ]; then
    ART="build/dmg-art"
    swift scripts/make-dmg-background.swift "$ART"
    tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff" > /dev/null
    "$DMGBUILD" -s scripts/dmg-settings.py -D app="$APP_SRC" -D background="$ART/background.tiff" -D applications="$APPS_LINK" "$VOLNAME" "$DMG" > /dev/null
else
    echo "    dmgbuild not found: building a plain image without the window layout"
    STAGE="build/dmg"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    cp -R "$APP_SRC" "$STAGE/"
    ln -s "$APPS_LINK" "$STAGE/Applications"   # system-path-ok: link inside the image
    hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
fi
if [ "${SIGN_IDENTITY:--}" != "-" ]; then codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"; fi
shasum -a 256 "$DMG"
echo "Built $DMG"
