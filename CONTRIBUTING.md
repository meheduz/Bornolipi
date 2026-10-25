# Contributing to Bornolipi

Thank you for helping. Bornolipi is free and open source under the MPL-2.0 license.

- **Report a problem:** open an issue and include the diagnostic report from the Bornolipi app.
- **Suggest a word or correction:** open an issue with the English letters you typed, what Bornolipi
  produced, and what you expected.
- **Contribute code:** see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for building and testing.
  Before opening a pull request, run `scripts/lint.sh` and `swift test`. Changes to typing behaviour
  need a test that shows the expected Bangla output.

`Data/AvroPhonetic.json`, `dictionary.json`, `autocorrect.json` and `suffix.json` come unchanged
from the OpenBangla project (see `NOTICE.md`); please do not edit them without explaining why.
`Data/conventional.json` is Bornolipi's own list of conventional spellings: each entry records its
source, and new entries need a reliable spelling reference. Conventional spellings are offered after
the Avro conversion and never change what Space inserts (see `docs/DECISIONS.md`, D-04).

Commits use the contributor's own name and email. Please do not add AI assistants as authors or
co-authors.

See also [SECURITY.md](SECURITY.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
