#!/bin/bash
# Types into real apps (TextEdit, Safari, Chrome, Firefox, Terminal, Cursor, Xcode, Word) through the
# system keyboard path with Bornolipi selected, and checks the text with the Accessibility API.
# Needs: the keyboard installed and enabled, and Accessibility permission for the app running this
# script (System Settings > Privacy & Security > Accessibility). Do not touch the keyboard or mouse
# while it runs. Optional arguments: app names to test, e.g. scripts/app-compat-test.sh TextEdit Safari
set -euo pipefail
cd "$(dirname "$0")/.."
# It types with the installed Bornolipi keyboard, so it runs only when asked for explicitly:
#   BORNOLIPI_KEYBOARD=release BORNOLIPI_ALLOW_RELEASE=1 scripts/app-compat-test.sh [apps]
# BORNOLIPI_SMOKE=1 runs only a minimal TextEdit check that teaches the keyboard nothing. The run stops if
# Bornolipi's personal data or settings change; its learned choices are put back afterwards.
if [ "${BORNOLIPI_KEYBOARD:-}" != release ] || [ "${BORNOLIPI_ALLOW_RELEASE:-}" != 1 ]; then
    echo "This types with your installed Bornolipi keyboard: run it with BORNOLIPI_KEYBOARD=release BORNOLIPI_ALLOW_RELEASE=1"; exit 2
fi
SUPPORT="$HOME/Library/Application Support/Bornolipi"; PROC="Input Methods/BornolipiKeyboard.app/Contents/MacOS/BornolipiKeyboard"   # system-path-ok: only with the explicit opt-in above
mkdir -p build
cp Tests/E2E/AppCompat.swift build/app-compat-main.swift
swiftc -O -o build/app-compat build/app-compat-main.swift
# Learned choices, and the copy the keyboard keeps of them, as they were before the run.
KEEP="build/app-compat-kept"; rm -rf "$KEEP"; mkdir -p "$KEEP"
for f in selections.json selections.json.backup; do [ -f "$SUPPORT/$f" ] && cp -p "$SUPPORT/$f" "$KEEP/$f"; done
# The selected input source before the run, put back on any exit (also after a failure or Control-C).
TIS_ID='import Carbon; let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue(); print(Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue() as String)'
PREVIOUS_SOURCE="$(swift -e "$TIS_ID")"
restore_source() {
    swift -e 'import Carbon
let want = CommandLine.arguments[1]
if let s = (TISCreateInputSourceList([kTISPropertyInputSourceID as String: want] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource])?.first { TISSelectInputSource(s) }' "$PREVIOUS_SOURCE"
    echo "input source restored: $(swift -e "$TIS_ID") (was $PREVIOUS_SOURCE)"
}
restore() {
    restore_source
    for f in selections.json selections.json.backup; do
        if [ -f "$KEEP/$f" ]; then mv "$KEEP/$f" "$SUPPORT/$f"; else rm -f "$SUPPORT/$f"; fi
    done
    pkill -f "$PROC" 2>/dev/null || true   # only the keyboard under test: forget its in-memory choices
    # Start it again at once: macOS does not always start it on demand after it was ended.
    sleep 1; open -g "$HOME/Library/Input Methods/BornolipiKeyboard.app" 2>/dev/null || true   # system-path-ok: runs the installed keyboard, changes nothing
}
trap restore EXIT
build/app-compat build/app-compat-results.txt "$@"
