#!/bin/bash
# Repository security checks (run in CI and by scripts/test.sh security):
#   - no private keys, tokens or signing material in tracked files
#   - no network calls in the keyboard's or the engine's source (only the Bornolipi app checks for updates;
#     the keyboard links InstallKit, which contains that check, but never calls it)
#   - every workflow declares token permissions, and every action is pinned to a commit SHA
#   - scripts never touch the real installation or system caches (check-system-paths.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
check() { if eval "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }

secrets=$(git grep -nIE '(BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[bp]-[0-9A-Za-z-]{20,})' -- . ':!scripts/check-security.sh' || true)
check "no private keys or tokens in tracked files" '[ -z "$secrets" ] || { echo "$secrets"; false; }'
signing=$(git ls-files | grep -iE '\.(p12|pem|key|cer|mobileprovision|keychain-db)$' || true)
check "no signing material tracked" '[ -z "$signing" ] || { echo "$signing"; false; }'
network=$(grep -rnE 'URLSession|URLRequest|NWConnection|CFNetwork|socket\(' Sources/BornolipiKeyboard Sources/BanglaEngine || true)
check "keyboard and engine sources make no network calls" '[ -z "$network" ] || { echo "$network"; false; }'
for wf in .github/workflows/*.yml; do
    check "$(basename "$wf"): token permissions declared" "grep -qE '^\s*permissions:' '$wf'"
    unpinned=$(grep -nE 'uses: [^@]+@' "$wf" | grep -vE '@[0-9a-f]{40}( |$)' || true)
    check "$(basename "$wf"): actions pinned to commit SHAs" '[ -z "$unpinned" ] || { echo "$unpinned"; false; }'
done
check "scripts never touch the real installation" "scripts/check-system-paths.sh >/dev/null"
[ $fail = 0 ] && echo "Security checks passed." || echo "Security checks FAILED."
exit $fail
