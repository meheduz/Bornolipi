# Architecture

## How a macOS input method works

- An input method is a small background app in `~/Library/Input Methods` (or `/Library/Input Methods`).
- On launch it creates an `IMKServer` with the connection name from its Info.plist
  (`InputMethodConnectionName`). Host apps (browsers, VS Code, Word) talk to it over IPC, so it runs
  in its own process and does not care which architecture the host app uses.
- For every text field macOS creates an `IMKInputController` subclass named in
  `InputMethodServerControllerClass`. Its `handle(_:client:)` receives key events.
- The controller shows the word being typed with `setMarkedText` (the underlined text), and ends it with
  `insertText`. Returning `false` from `handle` hands the key back to the app.
- `ComponentInputModeDict` in Info.plist declares the input mode (language `bn`) that appears in
  System Settings. `TISRegisterInputSource` lets the app register itself without a logout.
- Password fields use secure input, and macOS switches away from third-party input methods there.
  That is expected.

## Phonetic engine

- Avro Phonetic is a rule table: for each roman pattern, a Bangla replacement plus optional conditions on
  the text before or after (vowel, consonant, punctuation, number, exact text). The converter tries the
  longest pattern at each position and takes the first rule whose conditions hold.
- The rule table (`Data/AvroPhonetic.json`, 289 patterns) comes from OpenBangla's rupantor-rs. The Swift
  converter is a fresh implementation and is checked against 413 input/output pairs from that project.
- Suggestions: each dictionary word (159k words from OpenBangla) is indexed by a skeleton that ignores
  differences typists cannot control: short/long vowels, শ ষ স, ন ণ, য় য, ং ঙ, ৎ ত, and a final ো.
  The typed word is converted, reduced to a skeleton and looked up. Results are ranked by edit distance to
  the literal conversion. A trailing `o` is treated as ো first (`bhalo` gives ভালো).
- Suffixes (`suffix.json`): `bondhuder` is split into `bondhu` + `der` and joined as বন্ধুদের, with the
  য় / ত / ঙ joining rules.
- AutoCorrect: roman-to-roman table (OpenBangla's plus the user's own entries).
- Learning: when the user picks a non-default candidate it is remembered for that typed word.
- Candidate order (`Suggester.suggest`): learned choice, autocorrect, personal words, dictionary
  matches and suffixed forms, then the exact conversion, then offered-only suggestions
  (`Data/conventional.json`, Bangla letter names for words typed in capitals, suffixes on
  autocorrected loanwords, web and e-mail addresses as typed), then broken conjuncts and completions.
  Space inserts the first. Everything after the exact conversion is offered only, with slots
  reserved for it, so it never changes what Space inserts (docs/DECISIONS.md, D-04).
- The exact candidate is the conversion of the whole input, punctuation included, so it matches Avro
  even where punctuation is converted in context (`.5` is `.৫`).
- Output form: the single signs ো ৌ, and by default Avro's single code points for ড় ঢ় য়
  (Settings can switch to NFC).
- Lookup is well under a millisecond. Loading the dictionary takes about 250 ms and runs in the background.

## Layers

```
BanglaEngine (Foundation only, tested on any OS)   BornolipiKeyboard (macOS app, thin)
  AvroParser        rules -> Bangla                  main.swift            IMKServer, CLI flags, source-change watch
  SplitWord         punctuation around words         InputController.swift NSEvent -> KeyPress, IMK lifecycle
  WordIndex         compact skeleton index           CandidatePanel.swift  candidate window, mode HUD
  Suggester         candidates, learning, words      SettingsView.swift    SwiftUI settings
  PhoneticSession   composition state                Engine.swift          shared engine, user data files
  InputHandler      the whole key policy             InputSourceInstaller  TIS registration and status
  CandidatePlacement, Settings, UserBackup           Log.swift             privacy-safe diagnostics
```

The controller only translates events and draws; every decision is in `InputHandler`, so it is
unit tested. The candidate window is drawn after `handle` returns, so host apps never wait on layout.

## Apple Silicon

The app is plain Swift with no third-party binaries. `scripts/build.sh` builds arm64 by default and
`ARCHS="arm64 x86_64"` gives a universal binary. The CI job uses a macos-15 (Apple Silicon) runner.

## Licensing

OpenBangla's rupantor-rs and riti are MPL-2.0, which is file-level copyleft. The data files are bundled
unchanged and the whole project is released under MPL-2.0 as well, so nothing conflicts. Attribution is in
`NOTICE.md`.

## Known gaps

1. Manual testing in Chrome, VS Code, Safari, Word and other apps (checklist in TESTING.md).
2. Developer ID signing and notarization need the maintainer's credentials.
3. No word-frequency data, so ties are broken by dictionary order. Fixed layouts are not included.
4. Optional: override the keyboard layout to ABC for non-Latin last-used layouts, and add an
   "Enter only commits" setting (both done by other input methods).
