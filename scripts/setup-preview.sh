#!/bin/bash
# Screenshots of every setup assistant screen and the status window, light and dark.
#   scripts/setup-preview.sh [output dir]      (default build/setup-preview)
# Runs build/Bornolipi.app in preview mode: it shows one screen, installs nothing and saves nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/setup-preview}"
mkdir -p "$OUT"
scripts/build.sh > /dev/null
# A copy with its own bundle identifier, so previews never read or write the real app's settings.
PREVIEW="build/preview/Bornolipi Preview.app"
rm -rf build/preview && mkdir -p build/preview && cp -R build/Bornolipi.app "$PREVIEW"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.meheduz.Bornolipi.preview" "$PREVIEW/Contents/Info.plist"
codesign --force --sign - "$PREVIEW" 2>/dev/null
BIN="$PREVIEW/Contents/MacOS/Bornolipi"
window_id() {  # an on-screen window of a process (SMALLEST=1: the smallest, for alerts)
    swift -e 'import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let small = CommandLine.arguments.count > 2   // alerts are modal panels (window layer 8)
var w = list.filter { ($0["kCGWindowOwnerPID"] as? Int32) == pid && (small || ($0["kCGWindowLayer"] as? Int) == 0) }
func area(_ d: [String: Any]) -> Double { let b = d["kCGWindowBounds"] as? [String: Double] ?? [:]; return (b["Width"] ?? 0) * (b["Height"] ?? 0) }
if small { w.sort { area($0) < area($1) }; if w.count < 2 { w = [] } }
print(w.first.map { "\($0["kCGWindowNumber"]!)" } ?? "")' "$1" ${SMALLEST:+small}
}
shoot() {  # step appearance text-size file
    BORNOLIPI_PREVIEW_STEP=$1 BORNOLIPI_PREVIEW_APPEARANCE=$2 env ${3:+"$3"} "$BIN" & pid=$!
    id=""; for _ in $(seq 40); do sleep 0.5; id="$(window_id $pid)"; [ -n "$id" ] && break; done
    sleep 1.5
    if [ -n "$id" ]; then screencapture -o -x -l "$id" "$OUT/$4.png"; else echo "no window for $4"; fi
    kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
}
for look in light dark; do
    for step in welcome install enable tryIt done home; do shoot $step $look "" "$step-$look"; done
done
# The update alert with a labelled sample release (no network), in both appearances.
for look in light dark; do SMALLEST=1 shoot home $look BORNOLIPI_PREVIEW_UPDATE=1 "update-alert-$look"; done
# The help shown when Bornolipi is missing from System Settings' list.
for look in light dark; do shoot enable $look BORNOLIPI_PREVIEW_HELP=1 "enable-help-$look"; done
echo "Screenshots in $OUT"
