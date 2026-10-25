# Decision records

Short records of choices that shape Bornolipi, with the evidence behind them. Newest first.

## D-09 ↑ on the first candidate wraps to the engine's last candidate

Words appended after the engine's list (loose words 0.1.0 could not reach, and the optional loanword
suggestions) would otherwise be what ↑ reaches from the first candidate. ↑ there wraps to the last
candidate of the engine's list as 0.1.0 showed it (`Suggestion.engineCount`): the typed English word
when that setting is on. Appended words are reached with ↓ or a click. With one engine candidate ↑
still does nothing, as before.

**Evidence.** `NavigationBoundaryTests`; `SuggestionContractTests.testUpFromTheFirstCandidateIsUnchanged`:
↑, pressed as the input handler presses it, leaves the session as it is with loanword suggestions
off, for every input and setting in the contract test, lists with one engine candidate included.
With loanword suggestions on, one ↑ from the first candidate selects 0.1.0's word for all 115,748
probe inputs (defaults, typed English, 3 candidates, personal words) and all 318,804 keystroke
prefixes.

## D-08 Informal spellings are offered after the exact conversion, only when they are close

Typists who do not use Avro's capitals write `bari` for বাড়ি, `taka` for টাকা, `sarkar` for সরকার.
Two generators add the meant word right after the exact conversion; Space is unchanged.

- Informal romanisation: the input with one or two habits rewritten in Avro notation (r for ড়
  after a vowel, t/d for ট/ড, chh/ch, j for য, gy for জ্ঞ, kkh for ক্ষ, st for ষ্ট, ri for ৃ),
  kept only when it is a dictionary word.
- Loose matching, for unrecognised lowercase words of four or more letters: words with the same
  consonant classes. Proper nouns are offered as found (65 of 66 correct on the development data);
  dictionary words only when, apart from same-class letters, at most one letter in five differs,
  a second one only as close as the first, and never a longer form of the conversion.

**Evidence.** `bangla-eval`, Top-3: development set (162, tuned against) 73% before, 90% after;
independent set (113, never tuned against) 63% before, 78% after; main corpus 98% unchanged, 0 of
17 false-suggestion probes; Space unchanged for all 20,160 recorded inputs (the 27 known
differences). Loose suggestions appear for 0.25% of the recorded inputs. Cost: dictionary load
36 ms to 40 ms, about 4 MB footprint, suggestion p99 47 µs to 87 µs. Trade-off: in about a third of
the cases where an informal rewrite adds a word, the exact conversion was already meant, and the
rewrite moves the previous second candidate down one place.

**Amendment (2026-10-25): loanword suggestions after recognised words.** The maintainer decided that
additive retrieval candidates are allowed even when the dictionary already matches, provided existing
engine candidates keep their positions, none is removed, Space output is unchanged, duplicates are
eliminated and learned-choice behaviour is preserved. With "Suggest English loanwords" on (optional,
off by default), a separate retriever appends up to three dictionary or loanword-lexicon words after
the engine's final list, also when the dictionary already matched the input. These words never come
before an engine candidate: every engine candidate keeps its index and none is removed. Space is
unchanged. A word already listed is not added again, and a learned choice stays first. D-08's own
generators are unchanged: the loose step still runs only for unrecognised words.

The policy change is confined to the retriever's appended words: the closeness rule and the
unrecognised-only scope above do not apply to them, and their precision depends on the retriever's own
release checks.

**Evidence.** `SuggestionContractTests`: over a few hundred inputs (informal Bangla, English
loanwords, their prefixes, punctuation, Avro capitals, addresses, digits) × maxCandidates 2-9 ×
typed English on and off × completions on and off, with personal words and learned choices, the list
with the retriever off is an exact prefix of the list with it on; Space, the exact and autocorrection
indices and the typed English word's index are unchanged; at most three additions, within the limit,
no duplicates under canonical equivalence. `LooseMatchingTests.testWordsTheDictionaryAlreadyMatchesAreNotLooselyExtended`
and `testRecognisedWordsGainNothing` still describe the engine with the retriever off;
`LoanwordRetrieverTests.testARecognisedWordMayGainWordsAfterTheEngineList` covers janota with it on,
and `testLearnedChoicesAndAutocorrectKeepPriority` and `testPersonalWordsAndTypedEnglishKeepTheirPlaces`
the learned choice, a personal word and typed English. Measured on the integrated branch with the
retriever off and on (115,748 probe inputs × 12 settings, 300,000 generated inputs, 318,804
keystroke prefixes): 0 engine candidates moved or removed, 0 Space changes, 0 lists with
duplicates; wherever a learned choice applies it is first (6,522 of 6,522 rows); every list still
starts with 0.1.0's list. The default commit is unchanged on all four `bangla-eval` recordings
(80,600 inputs), and no appended word matches the suggestion blocklist (1.79 million lists).

## D-07 Updates in 0.1.0 are a verified manual download, not an automatic installer

**Decision.** Bornolipi checks GitHub for a newer release (at launch and at most once a day, on by
default and switchable off, or when asked), shows the version and release notes with Download Update
and Later, and links to the release page. Later silences that version only. The user downloads
the disk image and drags Bornolipi to Applications. Sparkle is not included in 0.1.0.

**Evidence.** An isolated Sparkle 2.10.0 trial with ad-hoc signed test apps and a local server
rejected tampered archives, tampered or unsigned update lists, wrong keys, interrupted and corrupt
downloads, downgrades and incompatible versions before installing anything. It installed, without
complaint, a correctly signed archive containing a *different* app and one containing an app with a
broken code signature: with an ad-hoc signed host, Sparkle does not compare code-signing identity,
so the update key is the only gate. Sparkle offers no delegate hook that can refuse an extracted
update (`didExtractUpdate` cannot stop installation and does not expose the files), so an
independent identity check is not possible without modifying Sparkle. Sparkle also removes the
quarantine attribute from updates it installs, so macOS does not run its first-launch Gatekeeper
check on them.

**Trade-off.** A manual download keeps Gatekeeper's check on every update, at the cost of one
Open Anyway approval per update while Bornolipi is not notarized. Revisit when a Developer ID is
available: Sparkle then also requires the update to be signed by the same team.

## D-06 Release images are checked before they are attached

`scripts/check-release.sh` mounts the image read-only and without a Finder window, then requires:
only `Bornolipi.app` and an `Applications` link to `/Applications`; both bundle identifiers; the
version in `VERSION` in both apps; the data files; valid deep strict code signatures; universal
binaries; no entitlements. Developer ID, notarization and Gatekeeper checks apply when the app is
Developer ID signed. Development images (`DMG_TEST=1`) link to a scratch folder and fail this
check by design.

## D-05 Leading punctuation is converted in context

Avro converts punctuation in context: `.5` is `.৫` and `` .` `` is a plain full stop. Bornolipi split
punctuation off the start of a word and converted it alone, so Space inserted `।৫` and, for
`` .` ``, nothing. Found by a differential test against the rule engine. The exact candidate now
uses the conversion of the whole input, so it matches Avro for every input; dictionary candidates
keep their punctuation-wrapped form.

## D-04 Conventional spellings are offered, never substituted

The Avro rule conversion is the product's contract. `sust` converts to সুস্ত, and Space keeps
inserting the first candidate exactly as before. Conventional spellings (সাস্ট, the 64 districts,
frequent informal spellings such as `kmn` for কেমন, Bangla letter names for words typed in
capitals, suffixed loanwords such as কম্পিউটারের) come from `Data/conventional.json` and rule-based
generators, and are placed right after the exact conversion with reserved slots so dictionary
matches cannot crowd them out. Short university forms (ঢাবি for `DU`) apply only to input typed in
capitals, so `du` stays দু.

**Evidence.** `swift run -c release bangla-eval` on `Tests/Evaluation/suggestions.tsv`: top-3
recall 61% before, 98% after (153 cases); 0 false positives on 7 probes; Space unchanged for 20,159
of 20,160 recorded inputs, the exception being the E2 fix below. Placing the suggestions first was
rejected because it would change what Space inserts for ordinary words.

## D-03 Repeated letters are not word stems (E2)

The suffix step split `rrri` into the stem `rr` (matching a questionable dictionary entry রর) and
the suffix `ri`, and ranked রররই above the exact রররি. A run of one repeated letter (a held or
doubled key) is no longer treated as a stem; one-letter stems (`oke` = ও + কে) are unchanged.

## D-02 Candidates use one encoding per word

Ten dictionary entries are a bare vowel sign, which cannot be a word; they are skipped at load. 42
words are stored twice, with ো or ৌ as one code point or two; candidates always use the single
signs and Avro's single code points for ড় ঢ় য়, so a word is always inserted with the same bytes.
A differential test confirms the rule engine's output is unchanged by this.

## D-01 User data is versioned and never silently replaced

Personal words and learned choices are stored as `{"format", "version", "payload"}` and written
atomically. A file that cannot be read is copied (and the copy verified) before it can be
replaced; a file from a newer version is never written. Repeated loads reuse the same copy, and
temporary files left by an interrupted write are removed only when they match Foundation's exact
naming and are at least ten minutes old. Tested with killed processes, a full disk, read-only and
unreadable files, and concurrent writers.
