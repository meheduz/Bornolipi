# Bornolipi

**Type Bangla. Naturally.**

Bornolipi is a free, open-source phonetic Bangla keyboard for macOS, compatible with Avro Phonetic and
built natively on InputMethodKit. Type `ami banglay gan gai`, get `আমি বাংলায় গান গাই`, in any app.
It suggests the word you meant when you type informally (`bari` offers বাড়ি, `sarkar` offers
সরকার), while Space always types what Avro would. Optionally, it also suggests known words for
English spellings (`computer` offers কম্পিউটার), after its own suggestions.

## Privacy

- The keyboard (`BornolipiKeyboard.app`) never connects to the internet: nothing in it calls the network.
  What you type, your personal words and learned choices stay on your Mac.
- The Bornolipi app connects to github.com only to check for a newer version: at most once a day while
  it runs (on by default, can be turned off in the app), or when you click **Check Now**. It sends no
  personal data or identifiers and downloads nothing by itself.
- Clicking **Source code and license** in Settings opens the project page in your browser.

## Status (0.1.0-beta.1, public beta)

Tested on macOS 27 on Apple silicon; the app is universal and built for macOS 13 or later. The test
suite also runs as x86_64 under Rosetta, but it has **not been tried on an Intel Mac or on macOS 13–26**.

| Area | State |
| --- | --- |
| Install | Drag **Bornolipi** to Applications and open it. A setup assistant installs the keyboard (no password), guides the one step macOS requires you to do yourself, detects when it is done, and offers a typing test. |
| Management | The app shows status, and handles repair, update, keyboard settings, diagnostics and uninstall (with an option to keep or delete your data). No Terminal anywhere. |
| Engine | Avro Phonetic conversion: Space inserts the Avro conversion (or the dictionary match Avro would offer first); suggestions follow it. 249 automated tests, including state-machine fuzzing and suggestion-quality corpora (`scripts/test.sh`, see docs/TESTING.md). |
| Performance | A key press takes about 11 µs typically and under 100 µs at p99 (Apple silicon); engine load about 60 ms; about 34 MB with the dictionary loaded. |
| Distribution | Free: a universal disk image on GitHub Releases. **Not Developer ID signed and not notarized**; first launch is allowed with Apple's Open Anyway button, see [docs/INSTALL.md](docs/INSTALL.md). |

## Beta feedback

This is a limited public beta. After installing, please file a short
[installation report](https://github.com/meheduz/Bornolipi/issues/new?template=install-report.yml)
with your macOS version, whether installation worked, and whether Bornolipi appeared under Bangla in
System Settings > Keyboard > Input Sources > Edit… > +. Reports from Macs where everything worked are
just as useful. Installation has been verified on one Mac (Apple silicon, macOS 27) only.

## Known limitations

- Not signed with a Developer ID and not notarized: the first launch needs Apple's **Open Anyway**
  approval, and so does each update (see [docs/INSTALL.md](docs/INSTALL.md)).
- Updates are a manual download; Bornolipi only checks for them and shows the release notes.
- On some Macs, System Settings' Add list does not show keyboards installed after it was first
  opened, so Bornolipi cannot be added there. This is a macOS problem with no supported fix found yet;
  please report it if it happens to you ([docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)).
- Not tested on Intel Macs or on macOS 13–26.
- Avro compatibility is kept even where Avro's own data is wrong: `chittagong` and `brahmanbaria`
  autocorrect to চট্রগ্রাম and ব্রাহ্মনবাড়িয়া (the standard spellings are offered next), and an
  explicit `:` (visarga) is dropped when a dictionary word without it matches (`shoto:` gives শত).
- Learned choices are not capped; each change rewrites the small choices file while typing.
- The menu bar icon stays ব in English mode: macOS gives an input source one icon and shows a cached
  copy of its menu, so the বাং/EN bubble shows the mode (Control-Shift-B, or Bangla / English in
  Bornolipi's menu).
- After an update, apps that were open (seen with Chrome and Terminal) may need to be reopened before
  Bornolipi types in them again ([docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)).

## Install

Download **Bornolipi-0.1.0.dmg** from the [Releases page](https://github.com/meheduz/Bornolipi/releases/latest) and follow [docs/INSTALL.md](docs/INSTALL.md):
it covers the one-time **Open Anyway** step, turning the keyboard on, updating and uninstalling.
Problems: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Develop

```sh
swift test                                    # unit and property tests (macOS and Linux)
scripts/lint.sh                               # swift-format rules, warnings as errors
swift run -c release bangla-bench             # latency, load time, memory
echo bhalobasha | swift run bangla-convert    # candidates for a word (--raw: rules only)
BORNOLIPI_ALLOW_INSTALL=1 scripts/dev-install.sh && scripts/e2e-test.sh # install, then type through macOS in a test window
BORNOLIPI_KEYBOARD=release BORNOLIPI_ALLOW_RELEASE=1 scripts/app-compat-test.sh  # type into real apps with the installed keyboard (needs Accessibility permission)
scripts/ui-preview.sh                         # screenshots of every window, light and dark
```

All developer commands: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Layout and design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Releases: [docs/RELEASING.md](docs/RELEASING.md).
Comparison with Avro, OpenBangla and Apple's Bangla input: [docs/COMPARISON.md](docs/COMPARISON.md).

## License

MPL-2.0. See `NOTICE.md` for the data sources.
