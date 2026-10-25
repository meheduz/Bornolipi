"""Builds Data/loanword-lexicon.tsv, the lexicon of the experimental loanword retriever
(Sources/BanglaEngine/LoanwordRetriever.swift). Offline only; the keyboard never runs it. Python 3
standard library, no other input than its arguments.

    python3 -I -B scripts/build-loanword-data.py BN_FULL DICTIONARY SUFFIX [OUT]

BN_FULL is the OpenSubtitles Bangla frequency list bn_full.txt (hermitdave/FrequencyWords), DICTIONARY
and SUFFIX are Data/dictionary.json and Data/suffix.json. OUT defaults to Data/loanword-lexicon.tsv.

The retrieval lexicon is the dictionary plus the OpenSubtitles Bangla words the lab prototype adds
(lexicon retrieval with English-aware consonant keys), each with its OpenSubtitles count (the frequency
prior is 0.25 * -ln(count + 1)). The word set, the word order (which breaks score ties) and the counts
are the prototype's: its loader is ported below unchanged. See the header this script writes for the
line format.

The retriever's other data files are not built here: loanword-costs-en.json and loanword-costs-native.json
are the prototype's learned cost tables copied byte for byte, and loanword-english.txt names its source
in its header.
"""
import hashlib, json, os, sys

# Consonant classes (the engine's loose classes, WordIndex.looseClass) and independent vowels: a lexicon
# word must start with one of these letters. From the prototype's bnshape.py.
_CLASS = {}
for us, c in [((0x0995, 0x0996), 1), ((0x0997, 0x0998), 2), ((0x0999, 0x0982), 3), ((0x099A, 0x099B), 4),
              ((0x099C, 0x099D, 0x09AF), 5), ((0x099E,), 6), ((0x099F, 0x09A0, 0x09A4, 0x09A5, 0x09CE), 7),
              ((0x09A1, 0x09A2, 0x09A6, 0x09A7), 8), ((0x09A3, 0x09A8), 9), ((0x09AA, 0x09AB), 10),
              ((0x09AC, 0x09AD), 11), ((0x09AE,), 12), ((0x09B0, 0x09DC, 0x09DD), 13), ((0x09B2,), 14),
              ((0x09B6, 0x09B7, 0x09B8), 15), ((0x09B9,), 16)]:
    for u in us:
        _CLASS[chr(u)] = c
_VIND = {'অ', 'আ', 'ই', 'ঈ', 'উ', 'ঊ', 'এ', 'ঐ', 'ও', 'ঔ', 'ঌ'}
# য় ড় ঢ় written with a nukta and ো ৌ written in two halves, and their single code points (escaped, so
# that no editor normalises them away).
_NUKTA_FIX = [('\u09af\u09bc', '\u09df'), ('\u09a1\u09bc', '\u09dc'), ('\u09a2\u09bc', '\u09dd'),
              ('\u09c7\u09be', '\u09cb'), ('\u09c7\u09d7', '\u09cc')]

UNION_MIN_FREQ = 2            # OpenSubtitles words need at least this count to enter the lexicon
UNION_INFLECTED_MIN_FREQ = 1  # or this count when they are a lexicon word + a known suffix


def norm(w):
    for a, b in _NUKTA_FIX:
        w = w.replace(a, b)
    return w.replace('‌', '').replace('‍', '')


def starts_word(w):
    return bool(_CLASS.get(w[0])) or w[0] in _VIND


def bangla_only(w):
    return all('ঀ' <= ch <= '৿' for ch in w)


def inflection_check(suffix_path, dict_set):
    """w -> True when w is a lexicon word + a Bangla suffix from the engine's suffix table, allowing the য়
    the engine inserts between a vowel sign and a vowel suffix. `dict_set` grows while words are added, as
    in the prototype, so the stem may be a dictionary word or an OpenSubtitles word added before."""
    sfx = json.load(open(suffix_path, encoding='utf-8'))
    suffixes = sorted({norm(v) for v in sfx.values() if v}, key=len, reverse=True)

    def check(w):
        for s in suffixes:
            if len(w) > len(s) + 1 and w.endswith(s):
                stem = w[:-len(s)]
                if stem in dict_set or (stem.endswith('য়') and stem[:-1] in dict_set):
                    return True
        return False
    return check


def load(freq_path, dictionary_path, suffix_path):
    """The prototype's loader: (dictionary words, added words, counts)."""
    d = json.load(open(dictionary_path, encoding='utf-8'))
    dict_words = []
    seen = set()
    for v in d.values():
        for w in v:
            if not w:
                continue
            w = norm(w)
            if w in seen or not starts_word(w):
                continue
            seen.add(w)
            dict_words.append(w)
    freq = {}
    for l in open(freq_path, encoding='utf-8'):
        p = l.split()
        if len(p) == 2:
            w = norm(p[0])
            freq[w] = freq.get(w, 0) + int(p[1])
    dict_words = [w for w in dict_words if bangla_only(w)]
    added = []
    inflected = inflection_check(suffix_path, seen)
    for w, c in sorted(freq.items(), key=lambda kv: -kv[1]):
        if w in seen or not bangla_only(w) or not starts_word(w):
            continue
        if c >= UNION_MIN_FREQ or (c >= UNION_INFLECTED_MIN_FREQ and inflected(w)):
            seen.add(w)
            added.append(w)
    return dict_words, added, freq


def sha256(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    freq_path, dictionary_path, suffix_path = sys.argv[1:4]
    out = sys.argv[4] if len(sys.argv) > 4 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Data', 'loanword-lexicon.tsv')
    dict_words, added, freq = load(freq_path, dictionary_path, suffix_path)

    lines = [
        "# bornolipi.loanword-lexicon\t2",
        "# Lexicon of the experimental loanword retriever (Sources/BanglaEngine/LoanwordRetriever.swift), written by",
        "# scripts/build-loanword-data.py (the lab prototype's loader). Sources (sha256):",
        f"#   OpenSubtitles Bangla frequencies bn_full.txt (hermitdave/FrequencyWords, CC-BY-SA-4.0) {sha256(freq_path)}",
        f"#   Data/dictionary.json {sha256(dictionary_path)}",
        f"#   Data/suffix.json {sha256(suffix_path)}",
        "# Words are normalised as the prototype does: ড় ঢ় য় ো ৌ as single code points, no ZWJ/ZWNJ.",
        "# The lexicon is the dictionary words, then the added words. Its dictionary part is every word of",
        "# Data/dictionary.json, in file order, normalised, whose first letter is a consonant or an independent",
        "# vowel and whose letters are all Bangla, the first of equal words only. The loader rebuilds that",
        "# list from the dictionary it is given, so the file does not need to match it: a dictionary word",
        "# without a `=` line has count 0, a `=` word no longer in the dictionary is left out, and a `+` word",
        "# that is a dictionary word now is kept once, as the dictionary word (with this count if it has none).",
        "# Line formats (tab-separated):",
        "#   =  WORD  COUNT           OpenSubtitles count of a dictionary word (only words with a count), in lexicon order",
        "#   +  WORD  COUNT           an OpenSubtitles word added to the lexicon (count >= 2, or count 1 and a",
        "#                            lexicon stem, a dictionary word or one added before, + a suffix of",
        "#                            Data/suffix.json), in lexicon order",
        "# The frequency prior of a word is 0.25 * -ln(COUNT + 1).",
    ]
    listed = 0
    for w in dict_words:
        c = freq.get(w, 0)
        if c == 0:
            continue
        assert '\t' not in w and '\n' not in w
        lines.append(f"=\t{w}\t{c}")
        listed += 1
    for w in added:
        c = freq.get(w, 0)
        assert c >= 1 and '\t' not in w and '\n' not in w
        lines.append(f"+\t{w}\t{c}")
    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')

    print(json.dumps({'lexicon_words': len(dict_words) + len(added), 'dictionary_words': len(dict_words),
                      'dictionary_words_with_count': listed, 'added_words': len(added), 'bytes': os.path.getsize(out)},
                     indent=1))


if __name__ == '__main__':
    main()
