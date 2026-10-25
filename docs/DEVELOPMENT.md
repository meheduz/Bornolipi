# Developer guide

People never need any of this; the Bornolipi app does it all. These are for developers.

| Command | Purpose |
| --- | --- |
| `swift test` | unit, property and install-logic tests |
| `scripts/lint.sh` | swift-format rules, warnings as errors |
| `scripts/build.sh` | builds `build/Bornolipi.app` (setup app with the keyboard inside) |
| `scripts/make-dmg.sh` | the disk image |
| `BORNOLIPI_ALLOW_INSTALL=1 scripts/dev-install.sh` | replaces the installed keyboard straight away, without the assistant (refuses without the variable) |
| `DMG_TEST=1 scripts/make-dmg.sh` | a test image whose Applications link is a scratch folder (`build/dmg-test-applications`); open only these on a development Mac, since dragging the app in a release image replaces `/Applications/Bornolipi.app` |
| `scripts/check-system-paths.sh` | fails if a script mentions the real installation or system caches without a reason (part of lint) |
| `scripts/e2e-test.sh` | types through macOS into a test window |
| `BORNOLIPI_KEYBOARD=release BORNOLIPI_ALLOW_RELEASE=1 scripts/app-compat-test.sh [apps]` | types into real apps with the installed keyboard (refuses without both variables); needs Accessibility permission for the terminal's app |
| `scripts/ui-preview.sh` | screenshots of the keyboard's windows |
| `scripts/test.sh [suite]` | all automated checks, or one suite (engine, installer, eval, fuzz, security, lint, bench, release); see docs/TESTING.md |
| `scripts/setup-preview.sh` | screenshots of every setup screen and the status window, light and dark (a preview copy with its own bundle ID: installs and saves nothing) |
| `scripts/make-dmg.sh` | universal disk image; the drag-to-Applications window layout needs `dmgbuild` (`python3 -m venv build/.venv && build/.venv/bin/pip install dmgbuild==1.6.5`), otherwise a plain image is made |
| `swift run -c release bangla-bench` | latency, load time, memory |
| `echo word \| swift run bangla-convert [--raw]` | candidates, or the rule conversion only |

Hidden flags of the setup app (same code as its buttons):
`"Bornolipi.app/Contents/MacOS/Bornolipi" --health | --install | --uninstall | --uninstall-with-data`.
`BORNOLIPI_PREVIEW_STEP=welcome|install|enable|tryIt|done|home` shows one screen for screenshots.

The keyboard binary itself takes `--status` (0 ready, 1 not registered, 2 not enabled), `--install`,
`--uninstall` and `--settings`. Diagnostics (never typed text):
`log stream --level debug --predicate 'subsystem == "io.github.meheduz.inputmethod.Bornolipi"'`.

Install location: per user, `~/Library/Input Methods`. A system-wide PKG to `/Library/Input Methods`
was considered: it needs an administrator password, and the reported advantage (input methods in
`~/Library` greyed out under Secure Keyboard Entry) did not reproduce here. With secure input on,
Text Input Sources still reports the keyboard as selectable. So it was not built.

## Known macOS issue: keyboard missing from the Add sheet

The sandboxed Keyboard settings pane reads its own copy of the input-source cache,
`$(getconf DARWIN_USER_CACHE_DIR)/com.apple.Keyboard-Settings.extension/com.apple.IntlDataCache.le.kbdx`.
On the development Mac (macOS 27.0.1) that copy was written once and never refreshed: not by
re-registering, restarting System Settings, logging out, input-source changes or restarting the Mac.
Text Input Sources and IntlPreferences outside the sandbox listed Bornolipi correctly the whole time.
With the user's consent, moving that one file aside (System Settings closed) made macOS rebuild it
with Bornolipi at once. Check with `grep -c -a inputmethod.Bornolipi <that file>`. Not yet solved for end users.

On the development Mac the original stale files are kept, untouched since, at:
`$(getconf DARWIN_USER_CACHE_DIR)/com.apple.Keyboard-Settings.extension/com.apple.IntlDataCache.le.kbdx.stale` and
`$(getconf DARWIN_USER_CACHE_DIR)/com.apple.Keyboard-Settings.extension/com.apple.IntlDataCache.le.stale` (both dated 2026-10-23 19:24).
macOS does not read files with these names. Restoring them would bring the stale list back.
