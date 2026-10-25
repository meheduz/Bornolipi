#!/bin/bash
# Build, install into ~/Library/Input Methods and restart the running instance.
# This replaces the keyboard you type with, so it only runs when asked explicitly:
#   BORNOLIPI_ALLOW_INSTALL=1 scripts/dev-install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${BORNOLIPI_ALLOW_INSTALL:-}" != 1 ]; then
    echo "dev-install.sh replaces the installed keyboard. Run it as: BORNOLIPI_ALLOW_INSTALL=1 scripts/dev-install.sh" >&2
    exit 1
fi
scripts/build.sh
DEST="$HOME/Library/Input Methods"   # system-path-ok: guarded by BORNOLIPI_ALLOW_INSTALL
mkdir -p "$DEST"
pkill -x BornolipiKeyboard 2>/dev/null || true
rm -rf "$DEST/BornolipiKeyboard.app"
cp -R build/BornolipiKeyboard.app "$DEST/"
"$DEST/BornolipiKeyboard.app/Contents/MacOS/BornolipiKeyboard" --install
