## What this changes

## Why

## Checks

- [ ] `scripts/lint.sh` and `swift test` pass
- [ ] Typing behaviour changes have a test with the expected Bangla output
- [ ] `swift run -c release bangla-eval` shows no new false positives, and Space is unchanged
      except where intended (`--compare-defaults`)
- [ ] Changes to `Data/` say where the data comes from
- [ ] No emojis, and user-facing text is English except Bangla examples
