#!/bin/bash
# Code checks: swift-format rules (configured in .swift-format to the project's existing style) and a
# warning-free build. Whitespace-only layout preferences are not enforced, to avoid churn.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
echo "==> swift-format rules"
if swift format lint --recursive Sources Tests 2>&1 \
    | grep -vE '\[(Indentation|LineLength|Spacing|AddLines|RemoveLine|TrailingComma)\]' | grep -E 'warning|error'; then
    status=1
else
    echo "    no findings"
fi
echo "==> build with warnings as errors"
# The build's own status decides too: with pipefail, a failed build used to make this line print
# "no warnings", and with -warnings-as-errors every warning fails the build.
if build="$(swift build -Xswiftc -warnings-as-errors 2>&1)" \
    && ! printf '%s\n' "$build" | grep -E 'error|warning: [^'"'"']' | grep -qv "unhandled"; then
    echo "    no warnings"
else
    printf '%s\n' "$build" | grep -E 'error|warning: [^'"'"']' | grep -v "unhandled"
    status=1
fi
echo "==> accessibility (static checks)"
scripts/check-accessibility.sh || status=1
echo "==> scripts never touch the real installation"
scripts/check-system-paths.sh || status=1
echo "==> folder names match Git's (a case-insensitive disk hides new files otherwise)"
mismatch="$(git ls-files | cut -d/ -f1 | sort -u | while read -r d; do ls -1A | grep -iFx -- "$d" | grep -qvFx -- "$d" && echo "$d"; done)"
if [ -n "$mismatch" ]; then echo "    tracked as $mismatch but named differently on disk"; status=1; else echo "    match"; fi
exit $status
