#!/bin/bash
# One entry point for Bornolipi's checks. Every suite uses temporary directories and in-memory or
# scratch storage; none of them touch the installed app, the active keyboard or personal data.
#   scripts/test.sh            all automated suites (what CI runs)
#   scripts/test.sh engine     engine tests: transliteration, suggestions, input, Unicode, data, properties
#   scripts/test.sh installer  installer, update-feed and restart-protocol tests
#   scripts/test.sh eval       suggestion quality: main corpus and held-out proper nouns
#   scripts/test.sh fuzz       long state-machine fuzzing (BORNOLIPI_FUZZ_ITERATIONS, default 200000)
#   scripts/test.sh security   repository security checks
#   scripts/test.sh lint       swift-format rules and a warning-free build
#   scripts/test.sh bench      latency, load time and memory (informational)
#   scripts/test.sh release    build a scratch release image and validate it (never overwrites)
# Real macOS integration (typing through the system into apps) is separate and manual:
#   scripts/e2e-test.sh and scripts/app-compat-test.sh; both use the installed keyboard (docs/TESTING.md).
set -euo pipefail
cd "$(dirname "$0")/.."
suite="${1:-all}"
case "$suite" in
    engine) swift test --filter BanglaEngineTests ;;
    installer) swift test --filter InstallKitTests ;;
    eval)
        swift run -c release bangla-eval
        swift run -c release bangla-eval --corpus Tests/Evaluation/heldout.tsv
        swift run -c release bangla-eval --corpus Tests/Evaluation/development.tsv
        swift run -c release bangla-eval --corpus Tests/Evaluation/independent.tsv ;;
    fuzz) BORNOLIPI_FUZZ_ITERATIONS="${BORNOLIPI_FUZZ_ITERATIONS:-200000}" swift test --filter StateMachineTests ;;
    security) scripts/check-security.sh ;;
    lint) scripts/lint.sh ;;
    bench) swift run -c release bangla-bench ;;
    release)
        out="build/rc-$(date +%Y%m%d-%H%M%S)/Bornolipi-$(cat RELEASE_LABEL).dmg"
        DMG_OUT="$out" scripts/make-dmg.sh
        scripts/check-release.sh "$out" ;;
    all)
        scripts/lint.sh
        swift test
        swift run -c release bangla-eval
        swift run -c release bangla-eval --corpus Tests/Evaluation/heldout.tsv
        swift run -c release bangla-eval --corpus Tests/Evaluation/development.tsv
        swift run -c release bangla-eval --corpus Tests/Evaluation/independent.tsv
        scripts/check-security.sh ;;
    *) sed -n 2,15p "$0"; exit 2 ;;
esac
