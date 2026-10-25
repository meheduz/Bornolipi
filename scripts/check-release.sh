#!/bin/bash
# Checks a release disk image before it is attached to a draft release.
#   scripts/check-release.sh [path/to/Bornolipi-<version>.dmg]
# Integrity checks always apply: the image holds exactly Bornolipi.app and an Applications link, with
# the right identities, versions, architectures and valid code signatures. Distribution checks
# (Developer ID, notarization, Gatekeeper) apply when the app is Developer ID signed; an ad-hoc
# signed build is reported as the disclosed unsigned distribution instead of failing.
# The image is mounted read-only without a Finder window, so nothing can be dragged out of it.
set -uo pipefail
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
DMG="${1:-build/Bornolipi-$(cat RELEASE_LABEL 2>/dev/null || echo "$VERSION").dmg}"
[ -f "$DMG" ] || { echo "No disk image at $DMG"; exit 1; }
MNT="$(mktemp -d)"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null; rmdir "$MNT" 2>/dev/null' EXIT
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MNT" -quiet || { echo "Could not mount $DMG"; exit 1; }
APP="$MNT/Bornolipi.app"
IME="$APP/Contents/Resources/BornolipiKeyboard.app"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }

echo "Image contents"
# Every entry outside Bornolipi.app, recursively: exactly the link, the window layout and the background.
outside="$(cd "$MNT" && find . -mindepth 1 -not -path './Bornolipi.app' -not -path './Bornolipi.app/*' | sort | tr '\n' ' ')"
check "only Bornolipi.app, the Applications link and the window layout" \
    "[ \"\$outside\" = './.DS_Store ./.background.tiff ./Applications ' ] && [ -f '$MNT/.background.tiff' ] && [ -f '$MNT/.DS_Store' ]"   # system-path-ok: compares names inside the mounted image
check "Applications is a link to /Applications" "[ \"\$(readlink '$MNT/Applications')\" = /Applications ]"   # system-path-ok: checks the link target
echo "Bornolipi.app"
check "bundle identifier io.github.meheduz.Bornolipi" "[ \"\$(plutil -extract CFBundleIdentifier raw '$APP/Contents/Info.plist')\" = io.github.meheduz.Bornolipi ]"
check "version $VERSION" "[ \"\$(plutil -extract CFBundleShortVersionString raw '$APP/Contents/Info.plist')\" = '$VERSION' ]"
check "build number is a positive integer" "plutil -extract CFBundleVersion raw '$APP/Contents/Info.plist' | grep -qE '^[1-9][0-9]*$'"
check "minimum macOS 13.0" "[ \"\$(plutil -extract LSMinimumSystemVersion raw '$APP/Contents/Info.plist')\" = 13.0 ]"
echo "BornolipiKeyboard.app (inside)"
check "bundle identifier io.github.meheduz.inputmethod.Bornolipi" "[ \"\$(plutil -extract CFBundleIdentifier raw '$IME/Contents/Info.plist')\" = io.github.meheduz.inputmethod.Bornolipi ]"
check "version $VERSION" "[ \"\$(plutil -extract CFBundleShortVersionString raw '$IME/Contents/Info.plist')\" = '$VERSION' ]"
check "build number is a positive integer" "plutil -extract CFBundleVersion raw '$IME/Contents/Info.plist' | grep -qE '^[1-9][0-9]*$'"
check "minimum macOS 13.0" "[ \"\$(plutil -extract LSMinimumSystemVersion raw '$IME/Contents/Info.plist')\" = 13.0 ]"
check "dictionary and rules present" "[ -s '$IME/Contents/Resources/Data/dictionary.json' ] && [ -s '$IME/Contents/Resources/Data/AvroPhonetic.json' ] && [ -s '$IME/Contents/Resources/Data/conventional.json' ] && [ -s '$IME/Contents/Resources/Data/propernouns.json' ] && [ -s '$IME/Contents/Resources/Data/autocorrect.json' ] && [ -s '$IME/Contents/Resources/Data/suffix.json' ]"
# A missing blocklist blocks nothing and missing loanword data turns the setting into a no-op, both silently.
check "loanword data and suggestion blocklist present" "[ -s '$IME/Contents/Resources/Data/loanword-lexicon.tsv' ] && [ -s '$IME/Contents/Resources/Data/loanword-english.txt' ] && [ -s '$IME/Contents/Resources/Data/loanword-costs-en.json' ] && [ -s '$IME/Contents/Resources/Data/loanword-costs-native.json' ] && [ -s '$IME/Contents/Resources/Data/suggestion-blocklist.txt' ]"
for b in "$APP" "$IME"; do
    echo "$(basename "$b") signature and architecture"
    check "code signature valid (deep, strict)" "codesign --verify --deep --strict '$b'"
    check "universal (arm64 + x86_64)" "lipo -archs '$b/Contents/MacOS/'* | grep -qE 'x86_64 arm64|arm64 x86_64'"
    check "no entitlements requested" "[ -z \"\$(codesign -d --entitlements - '$b' 2>/dev/null | grep -v '^Executable')\" ]"
done

if codesign -dvv "$APP" 2>&1 | grep -q 'Authority=Developer ID Application'; then
    echo "Distribution (Developer ID)"
    for b in "$APP" "$IME"; do
        check "$(basename "$b"): Developer ID signature" "codesign -dvv '$b' 2>&1 | grep -q 'Authority=Developer ID Application'"
        check "$(basename "$b"): hardened runtime" "codesign -dvv '$b' 2>&1 | grep -q 'flags=.*runtime'"
        check "$(basename "$b"): secure timestamp" "codesign -dvv '$b' 2>&1 | grep -q '^Timestamp='"
    done
    check "notarization ticket stapled" "xcrun stapler validate '$DMG'"
    check "Gatekeeper accepts the disk image" "spctl -a -t open --context context:primary-signature '$DMG'"
else
    echo "Distribution: ad-hoc signed, not notarized (the disclosed free distribution; users approve it once with Open Anyway)"
fi
echo "SHA-256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)  $(basename "$DMG")"
[ $fail = 0 ] && echo "Release image checks passed." || echo "Release image checks FAILED."
exit $fail
