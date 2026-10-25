# Comparison with other Bangla input methods

Only things measured on this Mac or read from source code are stated as facts. Everything else is
marked "not measured".

## Measured or verified

| | Bornolipi | Avro Keyboard for Mac 1.5 (installed) | Apple Bangla – Transliteration |
| --- | --- | --- | --- |
| Native on Apple Silicon | yes (arm64, universal available) | no (x86_64 only, needs Rosetta) | yes |
| Phonetic rule table | identical to Avro's | Avro | Apple's own |
| Output for 11 common words (ami, tumi, bangla, bhalo, biggan, kOrmo, shikkha, bidyaloy, dhonyobad, sentences) | correct | not measured | correct |
| Shows while typing | Bangla preview plus candidates | not measured | the roman letters |
| Return while composing | commits, then the key acts | commits only (source code) | commits only, no new line |
| Esc while composing | keeps English letters | not measured | commits Bangla |
| Memory footprint | 25 MB | not measured | 19 MB |
| Agreement with Avro's curated corrections | 98.1% of 1,933 | (source of the list) | not measured |
| Installation on macOS 27 | user adds it in System Settings | user adds it (verified: cannot be enabled by software) | built in |

## Features, by design

The Avro (Windows) and OpenBangla columns come from their documentation and source. They were not
tested on this Mac.

| Feature | Bornolipi | Avro Keyboard (Windows) | OpenBangla Keyboard (Linux) |
| --- | --- | --- | --- |
| Avro Phonetic rules | yes | yes | yes |
| Dictionary suggestions | yes, 159k words | yes | yes, same data |
| Autocorrect table, user entries | yes | yes | yes |
| Learns chosen words | yes, viewable and deletable | yes | yes |
| Personal dictionary | yes | no | no |
| Backup and restore of settings | yes | no | no |
| Unicode NFC option | yes | no | no |
| Fixed layouts (Probhat, National) | no | yes | yes |
| Offline, no telemetry | yes | yes | yes |

## Where Bornolipi can do better

- **Native on Apple Silicon:** the only installed Avro for Mac needs Rosetta.
- **Apple's guidance:** follows Apple's input method guidance and current macOS design (Liquid Glass
  panel, SwiftUI settings).
- **Data controls:** a personal dictionary, and learned words you can review and delete.
- **Measured quality:** latency and accuracy are measured and published, with reproducible scripts.
