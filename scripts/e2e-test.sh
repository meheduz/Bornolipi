#!/bin/bash
# End-to-end typing test against the installed input method (see Tests/E2E/TypingHost.swift).
# A test window opens for about a minute; do not type until it closes.
#   scripts/dev-install.sh && scripts/e2e-test.sh
#   SHOTS=build scripts/e2e-test.sh      also save a screenshot of the candidate window
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="build/TypingHost.app"
BIN="$HOST/Contents/MacOS/TypingHost"
OUT="build/e2e-results.txt"
SUPPORT="$HOME/Library/Application Support/Bornolipi"
[ -d "$HOME/Library/Input Methods/BornolipiKeyboard.app" ] || { echo "Install first: scripts/dev-install.sh"; exit 1; }   # system-path-ok: read-only check

echo "==> Building $HOST"
rm -rf "$HOST"
mkdir -p "$HOST/Contents/MacOS"
cat > "$HOST/Contents/Info.plist" <<EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>TypingHost</string>
    <key>CFBundleIdentifier</key><string>io.github.meheduz.Bornolipi.TypingHost</string>
    <key>CFBundleName</key><string>TypingHost</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOT
swiftc -O -swift-version 5 -parse-as-library -o "$BIN" Tests/E2E/TypingHost.swift Sources/BanglaEngine/*.swift
codesign --force --sign - "$HOST"

# The tests pick candidates, which the input method learns. Put the user's own choices back after.
BACKUP="build/selections.json.backup"
rm -f "$BACKUP"
[ -f "$SUPPORT/selections.json" ] && cp "$SUPPORT/selections.json" "$BACKUP"
PREVIOUS="$("$BIN" --current)"
restore() {
    "$BIN" --select "$PREVIOUS" || true
    if [ -f "$BACKUP" ]; then mv "$BACKUP" "$SUPPORT/selections.json"; else rm -f "$SUPPORT/selections.json"; fi
    pkill -x BornolipiKeyboard 2>/dev/null || true   # forget the test's choices held in memory as well
}
trap restore EXIT

echo "==> Running (a test window opens; please do not type until it closes)"
rm -f "$OUT"
open -W -n "$HOST" --args --out "$PWD/$OUT" --data "$PWD/Data" ${SHOTS:+--shots "$PWD/$SHOTS"}
cat "$OUT"
grep -qE "^[0-9]+ passed, 0 failed$" "$OUT"
