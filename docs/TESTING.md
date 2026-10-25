# Testing and verification record

Recorded on 2026-10-23: macOS 27.0.1, Apple Silicon, Xcode 27.0, Swift 6.4.
The status labels mean:
- **Automated:** a test in this repository checks it and passes.
- **Measured:** a number taken on this Mac.
- **Manual:** someone has to check it by hand.
- **Unverified:** nobody has checked it yet.

## Test architecture

Tests follow Swift Package Manager's layout: one test target per library under `Tests/`, organised
inside by responsibility. Correctness tests run in `swift test`; benchmarks, the evaluation corpus
and real-system tests are separate tools.

| Location | What it checks | How it runs |
| --- | --- | --- |
| `Tests/BanglaEngineTests/Transliteration` | Avro rule conversion: 413 reference pairs and 37 upstream pairs (`Fixtures/`) | `swift test` |
| `Tests/BanglaEngineTests/Suggestions` | dictionary, suffixes, autocorrect, conventional spellings, proper nouns, addresses, ranking limits, the evaluation corpus as a quality floor | `swift test` |
| `Tests/BanglaEngineTests/Input` | every key path, candidate placement, autocorrect undo, Shift and Caps Lock, per-app memory | `swift test` |
| `Tests/BanglaEngineTests/Unicode` | dictionary entry validity, one encoding per word, output form against the rule engine | `swift test` |
| `Tests/BanglaEngineTests/Data` | user data files (crash, full disk, permissions, concurrency, recovery), the dictionary reader, backups | `swift test` |
| `Tests/BanglaEngineTests/Properties` | state-machine fuzzing with invariants, fixed seeds, failure shrinking and replay; differential and metamorphic properties | `swift test`; longer with `scripts/test.sh fuzz` |
| `Tests/InstallKitTests` | versions, the keyboard restart protocol, release metadata, keyboard identity | `swift test` |
| `Tests/Evaluation` | suggestion corpus (`suggestions.tsv`), a held-out proper-noun set (`heldout.tsv`) and a development set (`development.tsv`), both studied and tuned against, and an independent set (`independent.tsv`, never tuned against: report it, do not fix cases from it) | `scripts/test.sh eval` |
| `Tests/E2E` | typing through macOS into a test window and real apps; UI screenshots | manual: `scripts/e2e-test.sh`, `scripts/app-compat-test.sh` (types with the installed keyboard; needs `BORNOLIPI_KEYBOARD=release BORNOLIPI_ALLOW_RELEASE=1`), `scripts/ui-preview.sh` |

All automated tests use temporary directories and in-memory stores. None of them touch the
installed app, the active keyboard or personal data; `scripts/check-system-paths.sh` (part of lint
and of the security checks) keeps scripts away from them too.

### Commands

| Command | Runs |
| --- | --- |
| `scripts/test.sh` | everything automated: lint, all tests, all evaluations, security checks (what CI runs) |
| `scripts/test.sh engine` | engine tests only |
| `scripts/test.sh installer` | installer, update-feed, restart-protocol and identity tests |
| `scripts/test.sh eval` | suggestion quality on the corpus and on the held-out, development and independent sets |
| `scripts/test.sh fuzz` | 200,000 state-machine sequences (`BORNOLIPI_FUZZ_ITERATIONS`, `BORNOLIPI_FUZZ_SEED`) |
| `scripts/test.sh security` | secrets, signing material, network code in the keyboard, workflow permissions and pinning, system paths |
| `scripts/test.sh lint` | swift-format rules and a warning-free build |
| `scripts/test.sh bench` | latency, load time, memory |
| `scripts/test.sh release` | builds a scratch release image (never overwrites one) and validates it |

## Automated: `swift test` (249 tests in two bundles, all pass)

157 engine tests and 30 installer tests, in the folders above.

## Automated: Avro compatibility evidence

- The rule table is semantically identical to `data.json` in OmicronLab's Avro Keyboard for Mac.
- An independent Python port of the original jsAvroPhonetic `parse()` passes 413/413 and the JS
  project's own 414 tests. Against the Swift parser it found **0 differences** on 4,644,635 inputs: all
  strings of length up to 3 over 95 typing characters, all length-4 strings over 43, random and
  structured strings, and real words. Mutation testing shows the comparison catches real bugs.
- Differences remain only for non-ASCII input to the parser (combining marks after a letter,
  non-ASCII capitals), which the keyboard never sends.

## Automated: system-level typing (`scripts/e2e-test.sh`)

A test app sends key events through its own text input context, which is the real path to the
installed input method (no Accessibility permission needed). Three runs were made.

**Passed in every run:**
- composition and commit;
- sentences, conjuncts, digits and punctuation;
- Return and Tab pass through after committing;
- Esc and Delete;
- choosing candidates and learning;
- a client discarding marked text;
- the candidate window is placed under the caret and hidden after a commit;
- an NSTextField, including Return sending the committed word;
- 352 fast keys with nothing lost.

**Checks with mixed results:**

| Check | Run 1 | Run 2 | Run 3 | Notes |
| --- | --- | --- | --- | --- |
| Password field gets plain letters | pass | pass | pass | |
| Focus change mid-word commits it | pass | — | — | Runs 2 and 3 failed after earlier tests disturbed the session; see below. |
| App switch mid-word commits it | pass | — | — | As above. |
| Switching input source mid-word commits it | pass | pass | — | As above. |
| Bangla/English toggle | — | pass | pass | Failed in run 1, which found a real bug: macOS swallowed the old Control-Shift-Space shortcut. Changed to Control-Shift-B. |

- **Key round trip:** the median from key event to marked text was 1.8–4.5 ms (measured).
- **Run 3 lost keys** partway through the 20-switch test. The input method did not crash: the log
  shows it running throughout. That points to the test window losing focus, not the input method.
  Retest before release.
- **WKWebView checks are inconclusive:** the page's JavaScript bridge stalls inside the test app,
  though it works on its own, so results could not be read back. Web fields need the manual test below.

## Measured: performance (`bangla-bench`, release build)

Times in microseconds, over 68,660 keystrokes of real words:

| Step | p50 | p95 | p99 |
| --- | --- | --- | --- |
| Rule conversion | 3.0 | 9.6 | 12.7 |
| Suggestions | 9.0 | 27.7 | 42.2 |
| Whole key press | 8.5 | 27.3 | 41.7 |

- **Loading:** the dictionary loads in 33 ms, off the input path.
- **Memory:** the input method process uses 25 MB (46 MB before this work; Apple's Bangla
  Transliteration uses 19 MB).
- **CPU:** 0.0% when idle.
- **Leaks:** `leaks` reports none over a 22,000-keystroke run.

## Measured: suggestion relevance

Our top suggestion equals the intended word in Avro Keyboard's own autocorrect dictionary for
**98.1%** of 1,933 entries. The rest are data differences, for example OpenBangla writes কেব্‌ল
where Avro writes কেবল. Without the autocorrect table, broken-conjunct suggestions raise the
recovery of real misspellings from 11.4% to 22.9% (intended word anywhere in the list), and the
first suggestion is unchanged.

## Automated: installation

- **Install:** registration, the localised name, and a status of 0, 1 or 2 work.
- **Uninstall and reinstall:** both work.
- **Upgrade:** reinstalling over an installed copy keeps it enabled.
- **Programmatic enabling:** blocked by macOS, so the user adds the input source once in System
  Settings. This was verified both ways on this Mac.

## Automated: real apps (`scripts/app-compat-test.sh`, Accessibility granted)

Keys are posted at the system HID level (the physical keyboard path) with Bornolipi selected;
results are read back with the Accessibility API. Checks: sentence, candidate window beside the
caret, Space, ↓ pick, Delete, arrows, Control-Shift-B, Return (new line, or a send-on-Enter chat box).

| App | Result |
| --- | --- |
| TextEdit | 8/8 |
| Safari (textarea, chat box) | 8/8 |
| Google Chrome (textarea, chat box; same text engine as Electron apps) | 8/8 |
| Terminal (typing into `cat`) | 5/5 applicable (arrow and Return checks do not apply; caret position not reported, window placement unchecked) |
| Xcode, Cursor | not run: another window stole focus, and the safety stop sent no keys |
| Firefox, Microsoft Word | not installed |

Findings:
- After the keyboard process restarts (Repair, Update), the next single key arrives unconverted
  while macOS relaunches it; later keys are fine.
- In Safari, the first key after another program switches input sources is not converted.
- The intermittent focus loss in earlier runs came from other windows taking focus (Xcode showed one
  mid-run). In the real-app runs the safety check caught it every time and no keys went astray.

## Automated: setup app and installation (same calls as its buttons)

- Fresh install, upgrade from an older build (your words kept byte for byte, keyboard stays on).
- Detecting and repairing a missing word list, files changed after signing, and a deleted keyboard.
- Uninstall keeping data, and uninstall deleting data (support folder and settings removed).
- Reinstalling after either: macOS keeps the keyboard turned on.
- "Open Keyboard Settings" lands on Keyboard > Text Input in macOS 27.
- Every assistant screen was screenshotted and reviewed.

Not tested: a brand-new macOS user account (creating one needs an administrator password), and the
graphical flow clicked through by a person from start to finish.

## Manual checks (not done for the current build)

The checks that need a person (typing in real apps, Gatekeeper on first install, installing,
updating and uninstalling, Intel hardware, macOS 13 and 14) are listed with their status in
[RELEASE-READINESS.md](RELEASE-READINESS.md). Never drag a release image's app into `/Applications`
on a Mac whose Bornolipi must stay as it is: that replaces the installed copy. Also worth covering when
possible: Google Docs and WhatsApp Web in a browser, Pages, Mail, Messages, Slack, iTerm2,
Spotlight, a full-screen app and a second monitor.

