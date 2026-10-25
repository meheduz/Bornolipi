#!/bin/bash
# Builds build/Bornolipi.app: the app people open, with the input method inside it
# (Contents/Resources/BornolipiKeyboard.app). The input method alone is also left at build/BornolipiKeyboard.app.
#   scripts/build.sh                        Apple Silicon (arm64), ad-hoc signed
#   ARCHS="arm64 x86_64" scripts/build.sh   universal
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build.sh   signed for distribution
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat VERSION)}"
BUILD="${BUILD:-$(cat BUILD_NUMBER)}"
ARCHS="${ARCHS:-arm64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
# The separate "Bornolipi Test" identity was removed; refuse rather than silently build the release.
[ -z "${VARIANT:-}" ] || { echo "VARIANT is no longer supported: scripts/build.sh builds only Bornolipi"; exit 1; }
# The release identity, written into both Info.plists (KeyboardIdentity reads it back at run time).
NAME="Bornolipi"; APP_ID="io.github.meheduz.Bornolipi"; IME_ID="io.github.meheduz.inputmethod.Bornolipi"
CONNECTION="Bornolipi_Connection"; DATA_FOLDER="Bornolipi"; IME_BUNDLE="BornolipiKeyboard.app"; IME_EXEC="BornolipiKeyboard"; OUT="build"
IME="$OUT/$IME_BUNDLE"
APP="$OUT/$NAME.app"

ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done
# SwiftPM links with --sysroot only, so clang stamps the binary with the deployment target as its
# SDK version and AppKit then applies old-SDK compatibility behaviour. -isysroot records the real SDK.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_FLAGS=(-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK")

echo "==> Compiling ($ARCHS)"
for product in BornolipiKeyboard Bornolipi; do
    swift build -c release --product "$product" "${ARCH_FLAGS[@]}" "${SDK_FLAGS[@]}"
done
BIN_DIR="$(swift build -c release --product BornolipiKeyboard "${ARCH_FLAGS[@]}" "${SDK_FLAGS[@]}" --show-bin-path)"

fill() {
    sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" -e "s/__NAME__/$NAME/g" -e "s/__APP_ID__/$APP_ID/g" \
        -e "s/__IME_ID__/$IME_ID/g" -e "s/__CONNECTION__/$CONNECTION/g" -e "s/__DATA_FOLDER__/$DATA_FOLDER/g" \
        -e "s/__IME_BUNDLE__/$IME_BUNDLE/g" -e "s/__IME_EXEC__/$IME_EXEC/g" "$1" > "$2"
}
plist() { fill "$1" "$2"; }

echo "==> Icons"
ICONS="$OUT/icons"
swift scripts/make-icons.swift "$ICONS" 2>/dev/null && iconutil -c icns "$ICONS/AppIcon.iconset" -o "$ICONS/AppIcon.icns" \
    || echo "    icon generation failed, continuing without custom icons"

echo "==> Assembling $IME"
rm -rf "$IME"
mkdir -p "$IME/Contents/MacOS" "$IME/Contents/Resources/Data"
cp "$BIN_DIR/BornolipiKeyboard" "$IME/Contents/MacOS/$IME_EXEC"
plist Resources/Info.plist "$IME/Contents/Info.plist"
for l in Resources/*.lproj; do
    mkdir -p "$IME/Contents/Resources/$(basename "$l")"
    for f in "$l"/*; do fill "$f" "$IME/Contents/Resources/$(basename "$l")/$(basename "$f")"; done
done
cp Data/*.json "$IME/Contents/Resources/Data/"
# The experimental loanword retriever (off by default) reads these when it is turned on.
cp Data/loanword-lexicon.tsv Data/loanword-english.txt "$IME/Contents/Resources/Data/"
# Words never appended to the engine's list (SuggestionBlocklist).
cp Data/suggestion-blocklist.txt "$IME/Contents/Resources/Data/"
cp LICENSE NOTICE.md "$IME/Contents/Resources/"
[ -f "$ICONS/InputIcon.tiff" ] && cp "$ICONS/InputIcon.tiff" "$IME/Contents/Resources/"
[ -f "$ICONS/AppIcon.icns" ] && cp "$ICONS/AppIcon.icns" "$IME/Contents/Resources/"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Bornolipi" "$APP/Contents/MacOS/Bornolipi"
plist Resources/Setup-Info.plist "$APP/Contents/Info.plist"
cp LICENSE NOTICE.md "$APP/Contents/Resources/"
[ -f "$ICONS/AppIcon.icns" ] && cp "$ICONS/AppIcon.icns" "$APP/Contents/Resources/"

echo "==> Signing ($SIGN_IDENTITY), inside out"
sign() {
    if [ "$SIGN_IDENTITY" = "-" ]; then codesign --force --sign - "$1"
    else codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"; fi
}
sign "$IME"
cp -R "$IME" "$APP/Contents/Resources/$IME_BUNDLE"
sign "$APP"
codesign --verify --deep --strict "$APP"
for b in "$APP/Contents/MacOS/Bornolipi" "$IME/Contents/MacOS/$IME_EXEC"; do echo "$(basename "$b"): $(lipo -archs "$b")"; done
echo "Built $APP"
