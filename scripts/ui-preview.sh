#!/bin/bash
# Screenshots of the candidate panel, mode HUD and Settings tabs in light and dark mode.
#   scripts/ui-preview.sh [output dir]      (default build/ui-preview)
# Windows appear on screen for a few seconds. Uses a scratch support directory, not your data.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/ui-preview}"
LIB="build/ui-preview-lib"
mkdir -p "$OUT" "$LIB"
swiftc -O -swift-version 5 -parse-as-library -module-name BanglaEngine -emit-library -static \
    -emit-module -emit-module-path "$LIB/BanglaEngine.swiftmodule" -o "$LIB/libBanglaEngine.a" Sources/BanglaEngine/*.swift
swiftc -O -swift-version 5 -parse-as-library -module-name InstallKit -emit-library -static \
    -emit-module -emit-module-path "$LIB/InstallKit.swiftmodule" -o "$LIB/libInstallKit.a" Sources/InstallKit/*.swift
APP_SOURCES=$(ls Sources/BornolipiKeyboard/*.swift | grep -v '/main.swift$')
swiftc -O -swift-version 5 -parse-as-library -module-name UIPreview -I "$LIB" -L "$LIB" -lBanglaEngine -lInstallKit \
    -o build/ui-preview-bin Tests/E2E/UIPreview.swift $APP_SOURCES
SUPPORT="$(mktemp -d)"
trap 'rm -rf "$SUPPORT"' EXIT
BORNOLIPI_DATA_DIR="$PWD/Data" BORNOLIPI_SUPPORT_DIR="$SUPPORT" build/ui-preview-bin "$OUT"
echo "Screenshots in $OUT"
