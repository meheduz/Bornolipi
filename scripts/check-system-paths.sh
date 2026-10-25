#!/bin/bash
# Fails when a script mentions a location that holds the user's installed Bornolipi (/Applications,
# ~/Library/Input Methods) or private macOS caches, unless the line is marked "system-path-ok"
# with a reason. Keeps development tools from writing to the real installation by accident.
set -uo pipefail
cd "$(dirname "$0")/.."
pattern='/Applications|Input Methods|DARWIN_USER_CACHE_DIR|IntlDataCache|/var/folders'
hits=$(grep -nE "$pattern" scripts/*.sh scripts/*.py scripts/*.swift .github/workflows/*.yml 2>/dev/null \
    | grep -v 'system-path-ok' | grep -v '^scripts/check-system-paths.sh:' \
    | grep -vE ':[0-9]+:\s*#')
if [ -n "$hits" ]; then
    echo "Scripts reference the real installation or system caches without a system-path-ok reason:"
    echo "$hits"
    exit 1
fi
echo "    no unguarded system paths"
