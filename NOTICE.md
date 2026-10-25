# Notice

Bornolipi is licensed under the Mozilla Public License 2.0 (see LICENSE).

The files in `Data/` listed below as OpenBangla's were copied from the OpenBangla project, also
MPL-2.0, and are not modified in this repository (they were added in its first commit; the upstream
commit was not recorded):

| File | Source |
| --- | --- |
| `AvroPhonetic.json` | https://github.com/OpenBangla/rupantor-rs (`src/AvroPhonetic.json`) |
| `dictionary.json`, `autocorrect.json`, `suffix.json` | https://github.com/OpenBangla/riti (`data/`) |
| `conventional.json` | Bornolipi. District names: Bengali spellings from the teachers.gov.bd district list, English spellings from Wikipedia's Districts of Bangladesh. Each entry records its source. |
| `propernouns.json` | Bornolipi. Bangladeshi place, institution and personal names. Each Bengali spelling was read from Bengali Wikipedia (CC BY-SA 4.0), Banglapedia or a Bangladesh government portal and confirmed by a second, independent one of these; both are recorded per entry. Names are factual data. |

`Tests/BanglaEngineTests/Fixtures/avro_reference.json` holds input/output pairs taken from the rupantor-rs
test-suite, used to check that this engine behaves like the reference one.

`Tests/BanglaEngineTests/Fixtures/avro_upstream_extra.json` holds 37 short input/output pairs from the
test suites of other Avro Phonetic implementations (libavrophonetic, pyAvroPhonetic, okkhor,
jsAvroPhonetic, iAvro, riti and rupantor-rs); each pair names its project and location. They are used
only as test expectations.

`Tests/Evaluation/*.tsv` are lists of single words and names, each checked against the page it
cites (Bengali Wikipedia and Wiktionary, CC BY-SA 4.0; Banglapedia; news sites such as Prothom Alo
and BBC Bangla). Only these facts are used; no text from the pages is copied.

The conversion code in `Sources/BanglaEngine` is written independently in Swift. The idea of
matching the longest rule first, with prefix/suffix conditions, is the Avro Phonetic design.
"Avro Keyboard" is by OmicronLab; this project is not affiliated with them.

