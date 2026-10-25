import Foundation

/// Fuzzy dictionary lookup. Words are indexed by a "skeleton" that collapses the spelling
/// ambiguities phonetic typists cannot control (short/long vowels, শ/ষ/স, ন/ণ, য়/য, inherent o).
///
/// Storage is compact: every word's UTF-8 sits in one buffer and every skeleton in another, and the
/// word ids are sorted by skeleton, so exact and prefix lookups are binary searches. Ids follow the
/// order of the dictionary file, so equally good candidates always come out in the same order.
public final class WordIndex {
    private var utf8: [UInt8] = []
    private var wordEnd: [UInt32] = []
    private var skel: [UInt16] = []
    private var skelEnd: [UInt32] = []
    /// Word ids ordered by skeleton, then id.
    private var bySkeleton: [Int32] = []
    /// Loose keys (consonant classes only, see `looseKey`) with the word id in the low bits, sorted.
    private var looseIndex: [UInt64] = []
    private static let looseIDBits: UInt64 = 20

    public init() {}

    /// Loads Data/dictionary.json: an object whose values are arrays of words.
    public convenience init(dictionaryURL: URL) throws {
        self.init()
        try load(dictionaryURL)
    }

    public var count: Int { wordEnd.count }

    public func load(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        reset()
        utf8.reserveCapacity(data.count)          // the words are a little less than the file
        skel.reserveCapacity(data.count / 3)      // about one unit per 3-byte Bengali letter
        try WordIndex.forEachWord(in: data) { if WordIndex.isPlausibleWord($0) { add($0) } }
        finish()
    }

    /// A dependent vowel sign, hasanta or nukta attaches to a letter before it, so an entry that
    /// starts with one (the data has ি, া and others as entries) cannot be a word.
    static func isPlausibleWord(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first else { return false }
        switch first.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return false
        default: return true
        }
    }

    func build(_ list: [String]) {
        reset()
        for w in list { add(w) }
        finish()
    }

    private func reset() {
        utf8 = []; wordEnd = []; skel = []; skelEnd = []; bySkeleton = []
    }

    private func add(_ word: String) {
        utf8.append(contentsOf: word.utf8)
        wordEnd.append(UInt32(utf8.count))
        WordIndex.appendSkeleton(of: word, to: &skel)
        skelEnd.append(UInt32(skel.count))
    }

    private func finish() {
        // Drop the spare capacity left by growing the arrays.
        utf8 = WordIndex.compacted(utf8); skel = WordIndex.compacted(skel)
        wordEnd = WordIndex.compacted(wordEnd); skelEnd = WordIndex.compacted(skelEnd)
        var order = Array(0..<Int32(count))
        skel.withUnsafeBufferPointer { s in
            skelEnd.withUnsafeBufferPointer { ends in
                order.sort { a, b in
                    let c = WordIndex.compare(s, ends, Int(a), s, ends, Int(b))
                    return c != 0 ? c < 0 : a < b
                }
            }
        }
        bySkeleton = order
        buildLooseIndex()
    }

    /// Keys come from the words as Avro writes them (`looseLetters`), like the queries, not from the
    /// skeletons: they turn ড় ঢ় য় into ড ঢ য, which are other consonant classes. A word with ড় ঢ় or য়
    /// also keeps its skeleton's key, the one 0.1.0 indexed it by, so a query typed with d, dh or y for
    /// those letters (pahadi for পাহাড়ি) still reaches it (`LooseHit.compatible`). An index with more
    /// words than the id bits hold gets no loose matching.
    private func buildLooseIndex() {
        guard count < 1 << WordIndex.looseIDBits else { looseIndex = []; return }
        var packed: [UInt64] = []
        packed.reserveCapacity(count + count / 4)
        var letters: [UInt32] = []
        utf8.withUnsafeBufferPointer { bytes in
            wordEnd.withUnsafeBufferPointer { ends in
                for id in 0..<count {
                    let word = UnsafeBufferPointer(rebasing: bytes[WordIndex.range(ends, id)])
                    letters.removeAll(keepingCapacity: true)
                    _ = transcode(word.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: false) { letters.append($0) }
                    if WordIndex.needsLooseNormalization(letters) { letters = WordIndex.looseLetters(String(decoding: word, as: UTF8.self)) }
                    let key = WordIndex.looseKey(letters)
                    if let key { packed.append(key << WordIndex.looseIDBits | UInt64(id)) }
                    if letters.contains(where: WordIndex.isNuktaLetter), let old = skeletonLooseKey(id), old != key {
                        packed.append(old << WordIndex.looseIDBits | UInt64(id))
                    }
                }
            }
        }
        WordIndex.radixSort(&packed)
        looseIndex = packed
    }

    /// ড় ঢ় য়: the only letters whose consonant class the skeleton changes (to ড ঢ য).
    static func isNuktaLetter(_ u: UInt32) -> Bool { u == 0x09DC || u == 0x09DD || u == 0x09DF }

    /// The loose key of word `id`'s skeleton: the key 0.1.0's loose index used.
    private func skeletonLooseKey(_ id: Int) -> UInt64? {
        skel.withUnsafeBufferPointer { s in skelEnd.withUnsafeBufferPointer { ends in WordIndex.looseKey(s[WordIndex.range(ends, id)]) } }
    }

    /// Least-significant-digit radix sort, 16 bits per pass; passes where every key has the same
    /// digit are skipped. Several times faster than `sort()` for the 160 000 loose keys.
    static func radixSort(_ a: inout [UInt64]) {
        guard a.count > 1 else { return }
        var b = [UInt64](repeating: 0, count: a.count)
        for shift in stride(from: UInt64(0), to: 64, by: 16) {
            var counts = [Int](repeating: 0, count: 1 << 16)
            for v in a { counts[Int(v >> shift & 0xFFFF)] += 1 }
            if counts[Int(a[0] >> shift & 0xFFFF)] == a.count { continue }
            var total = 0
            for i in counts.indices { let c = counts[i]; counts[i] = total; total += c }
            for v in a { let d = Int(v >> shift & 0xFFFF); b[counts[d]] = v; counts[d] += 1 }
            swap(&a, &b)
        }
    }

    private static func compacted<T>(_ a: [T]) -> [T] {
        [T](unsafeUninitializedCapacity: a.count) { buffer, n in
            _ = buffer.initialize(from: a)
            n = a.count
        }
    }

    // MARK: Skeletons

    public static func skeleton(_ s: String) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(s.unicodeScalars.count)
        appendSkeleton(of: s, to: &out)
        return out
    }

    private static func appendSkeleton(of s: String, to out: inout [UInt16]) {
        for u in s.unicodeScalars {
            switch u.value {
            case 0x0988: out.append(0x0987)          // ঈ -> ই
            case 0x09C0: out.append(0x09BF)          // ী -> ি
            case 0x098A: out.append(0x0989)          // ঊ -> উ
            case 0x09C2: out.append(0x09C1)          // ূ -> ু
            case 0x09B6, 0x09B7: out.append(0x09B8)  // শ ষ -> স
            case 0x09A3: out.append(0x09A8)          // ণ -> ন
            case 0x09DF: out.append(0x09AF)          // য় -> য
            case 0x09DC: out.append(0x09A1)          // ড় -> ড
            case 0x09DD: out.append(0x09A2)          // ঢ় -> ঢ
            case 0x09CE: out.append(0x09A4)          // ৎ -> ত
            case 0x0999: out.append(0x0982)          // ঙ -> ং
            case 0x09BC, 0x0981, 0x0983, 0x09CB: continue // nukta, chandrabindu, visarga, ো
            default:
                if u.value < 0x10000 { out.append(UInt16(u.value)) }
            }
        }
    }

    private static func range(_ ends: UnsafeBufferPointer<UInt32>, _ i: Int) -> Range<Int> {
        (i == 0 ? 0 : Int(ends[i - 1]))..<Int(ends[i])
    }

    /// Lexicographic order of two stored skeletons.
    private static func compare(_ s1: UnsafeBufferPointer<UInt16>, _ e1: UnsafeBufferPointer<UInt32>, _ a: Int,
                                _ s2: UnsafeBufferPointer<UInt16>, _ e2: UnsafeBufferPointer<UInt32>, _ b: Int) -> Int {
        let ra = range(e1, a), rb = range(e2, b)
        let n = min(ra.count, rb.count)
        for k in 0..<n where s1[ra.lowerBound + k] != s2[rb.lowerBound + k] {
            return s1[ra.lowerBound + k] < s2[rb.lowerBound + k] ? -1 : 1
        }
        return ra.count == rb.count ? 0 : (ra.count < rb.count ? -1 : 1)
    }

    /// Compares stored skeleton `id` with `key`. With `prefixOnly`, only the first `key.count` units count.
    private func compare(_ id: Int, _ key: [UInt16], prefixOnly: Bool) -> Int {
        skel.withUnsafeBufferPointer { s in
            skelEnd.withUnsafeBufferPointer { ends in
                let r = WordIndex.range(ends, id)
                let n = min(r.count, key.count)
                for k in 0..<n where s[r.lowerBound + k] != key[k] { return s[r.lowerBound + k] < key[k] ? -1 : 1 }
                if r.count >= key.count && prefixOnly { return 0 }
                return r.count == key.count ? 0 : (r.count < key.count ? -1 : 1)
            }
        }
    }

    /// The first position in `bySkeleton` whose skeleton is not below `key` (`prefixOnly`: whose prefix).
    private func lowerBound(_ key: [UInt16], prefixOnly: Bool, after: Bool) -> Int {
        var lo = 0, hi = bySkeleton.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let c = compare(Int(bySkeleton[mid]), key, prefixOnly: prefixOnly)
            if c < 0 || (after && c == 0) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func skeletonLength(_ id: Int) -> Int {
        Int(skelEnd[id]) - (id == 0 ? 0 : Int(skelEnd[id - 1]))
    }

    // MARK: Words

    func word(_ id: Int) -> String {
        let start = id == 0 ? 0 : Int(wordEnd[id - 1])
        return utf8.withUnsafeBufferPointer { String(decoding: UnsafeBufferPointer(rebasing: $0[start..<Int(wordEnd[id])]), as: UTF8.self) }
    }

    /// Calls `body` with every word's id and UTF-8, in id (file) order, for indexes that share these words.
    func forEachWordUTF8(_ body: (Int, UnsafeBufferPointer<UInt8>) -> Void) {
        utf8.withUnsafeBufferPointer { bytes in
            wordEnd.withUnsafeBufferPointer { ends in
                for id in 0..<count { body(id, UnsafeBufferPointer(rebasing: bytes[WordIndex.range(ends, id)])) }
            }
        }
    }

    /// The UTF-8 of word `id`, without making a String.
    func withWordUTF8<R>(_ id: Int, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
        utf8.withUnsafeBufferPointer { bytes in
            wordEnd.withUnsafeBufferPointer { ends in body(UnsafeBufferPointer(rebasing: bytes[WordIndex.range(ends, id)])) }
        }
    }

    private func scalars(_ id: Int) -> [UInt32] {
        word(id).unicodeScalars.map { $0.value }
    }

    /// Dictionary words whose skeleton equals the skeleton of `phonetic`, best match first.
    /// `variants` are alternative spellings of the typed text (for example a final `o`
    /// typed as ো); a word is ranked by its closest variant, earlier variants win ties.
    public func matches(for phonetic: String, variants: [String] = [], preferVariants: Bool = false, limit: Int) -> [String] {
        let sk = WordIndex.skeleton(phonetic)
        guard !sk.isEmpty else { return [] }
        let lo = lowerBound(sk, prefixOnly: false, after: false)
        let hi = lowerBound(sk, prefixOnly: false, after: true)
        guard lo < hi else { return [] }
        let targets = (preferVariants ? variants + [phonetic] : [phonetic] + variants).map { $0.unicodeScalars.map { $0.value } }
        let ranked = bySkeleton[lo..<hi].map { id -> (Int, Int, Int, Int32) in
            let wv = scalars(Int(id))
            var best = Int.max, which = 0
            for (k, t) in targets.enumerated() {
                let d = WordIndex.distance(wv, t)
                if d < best { best = d; which = k }
            }
            return (best, which, wv.count, id)
        }.sorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
            return a.3 < b.3
        }
        return ranked.prefix(limit).map { word(Int($0.3)) }
    }

    /// Consonant class of a Bangla letter for loose matching, or nil for vowels, signs and the rest.
    /// Informal English spelling does not tell these apart: aspiration (ভ/ব), dental and retroflex
    /// (ত/ট, দ/ড), চ/ছ, শ/ষ/স, ন/ণ, জ/য/ঝ, র/ড়/ঢ়, ঙ/ং.
    static func looseClass(_ u: UInt32) -> UInt8? {
        guard u >= 0x0980, u < 0x0A00 else { return nil }
        let c = looseClasses[Int(u - 0x0980)]
        return c == 0 ? nil : c
    }

    /// `looseClass` for the Bengali block, as a table: the index is built from every dictionary word.
    private static let looseClasses: [UInt8] = (0x0980..<0x0A00).map { looseClassOf(UInt32($0)) ?? 0 }

    private static func looseClassOf(_ u: UInt32) -> UInt8? {
        switch u {
        case 0x0995, 0x0996: return 1                  // ক খ
        case 0x0997, 0x0998: return 2                  // গ ঘ
        case 0x0999, 0x0982: return 3                  // ঙ ং
        case 0x099A, 0x099B: return 4                  // চ ছ
        case 0x099C, 0x099D, 0x09AF: return 5          // জ ঝ য
        case 0x099E: return 6                          // ঞ
        case 0x099F, 0x09A0, 0x09A4, 0x09A5, 0x09CE: return 7   // ট ঠ ত থ ৎ
        case 0x09A1, 0x09A2, 0x09A6, 0x09A7: return 8  // ড ঢ দ ধ
        case 0x09A3, 0x09A8: return 9                  // ণ ন
        case 0x09AA, 0x09AB: return 10                 // প ফ
        case 0x09AC, 0x09AD: return 11                 // ব ভ
        case 0x09AE: return 12                         // ম
        case 0x09B0, 0x09DC, 0x09DD: return 13         // র ড় ঢ়
        case 0x09B2: return 14                         // ল
        case 0x09B6, 0x09B7, 0x09B8: return 15         // শ ষ স
        case 0x09B9: return 16                         // হ
        case 0x09DF: return 17                         // য়
        default: return nil
        }
    }

    /// The sequence of consonant classes (repeats collapsed) as one number, or nil when it has fewer
    /// than three classes: shorter keys match too many unrelated words.
    static func looseKey<S: Sequence>(_ scalars: S) -> UInt64? where S.Element: BinaryInteger {
        var key: UInt64 = 0, n = 0, last: UInt8 = 0   // 5 bits per class and 4 for the count: 44 bits
        for u in scalars {
            guard let c = looseClass(UInt32(truncatingIfNeeded: u)), c != last else { continue }
            last = c
            n += 1
            guard n <= 8 else { n = 8; break }   // longer words compare on their first 8
            key = key << 5 | UInt64(c)
        }
        return n >= 3 ? key | UInt64(n) << 40 : nil
    }

    /// The letters every loose comparison uses (index keys, query keys, loose and exact distances): the
    /// text as Avro writes it, with ো ৌ as one sign and ড় ঢ় য় as one code point. Dictionary words,
    /// curated spellings and queries can use other encodings of the same word.
    static func looseLetters(_ s: String) -> [UInt32] {
        Suggester.avroForm(Suggester.composeVowelSigns(s)).unicodeScalars.map(\.value)
    }

    /// Whether `looseLetters` would change these code points: a nukta, or ে followed by া or ৗ.
    static func needsLooseNormalization(_ u: [UInt32]) -> Bool {
        u.indices.contains { u[$0] == 0x09BC || (u[$0] == 0x09C7 && $0 + 1 < u.count && (u[$0 + 1] == 0x09BE || u[$0 + 1] == 0x09D7)) }
    }

    /// One word of a loose bucket, scored against the query by `looseHits`.
    struct LooseHit {
        let id: Int32
        /// The word as Avro writes it (`looseLetters`).
        let letters: [UInt32]
        /// Edit distance with same-class letters counted as equal (`looseDistance`), and plain edit distance.
        let loose: Int, exact: Int
        /// 0.1.0's index (skeleton keys) reached this word for the query too.
        let compatible: Bool
        /// The word's code points as stored and their two distances, when they are not `letters`.
        let stored: (letters: [UInt32], loose: Int, exact: Int)?
        /// What 0.1.0 compared: the code points as stored.
        var asStored: (letters: [UInt32], loose: Int, exact: Int) { stored ?? (letters, loose, exact) }
    }

    /// Up to `limit` words with the loose key of `phonetic`, closest first: loose distance, then edit
    /// distance, then dictionary order. A word stored twice (42 dictionary words in two encodings, mostly
    /// ো ৌ as one sign and as two, and one exact duplicate) comes once, unless `distinct` is false.
    func looseHits(for phonetic: String, limit: Int = .max, distinct: Bool = true) -> [LooseHit] {
        let typed = WordIndex.looseLetters(phonetic)
        guard limit > 0, let key = WordIndex.looseKey(typed) else { return [] }
        let first = key << WordIndex.looseIDBits, idMask: UInt64 = 1 << WordIndex.looseIDBits - 1
        var lo = 0, hi = looseIndex.count
        while lo < hi { let m = (lo + hi) / 2; if looseIndex[m] < first { lo = m + 1 } else { hi = m } }
        var hits: [LooseHit] = []
        for entry in looseIndex[lo...] {
            guard entry & ~idMask == first else { break }
            let id = Int32(entry & idMask)
            var word = scalars(Int(id))
            var stored: (letters: [UInt32], loose: Int, exact: Int)?
            if WordIndex.needsLooseNormalization(word) {   // compare as Avro writes it
                stored = (word, WordIndex.looseDistance(word, typed), WordIndex.distance(word, typed))
                word = WordIndex.looseLetters(self.word(Int(id)))
            }
            let compatible = !word.contains(where: WordIndex.isNuktaLetter) || skeletonLooseKey(Int(id)) == key
            hits.append(LooseHit(id: id, letters: word, loose: WordIndex.looseDistance(word, typed), exact: WordIndex.distance(word, typed),
                                 compatible: compatible, stored: stored))
        }
        hits.sort { a, b in (a.loose, a.exact, a.id) < (b.loose, b.exact, b.id) }
        var out: [LooseHit] = [], seen: Set<[UInt32]> = []
        for h in hits where out.count < limit {
            if !distinct || seen.insert(h.letters).inserted { out.append(h) }
        }
        return out
    }

    /// The dictionary word of a loose hit, as stored.
    func word(of hit: LooseHit) -> String { word(Int(hit.id)) }

    /// Words with the same consonant classes as `phonetic` (vowels ignored), closest first. For
    /// informal spellings the exact lookup misses (sarkar for সরকার, janota for জনতা).
    public func looseMatches(for phonetic: String, limit: Int) -> [String] {
        looseHits(for: phonetic, limit: limit).map { word(Int($0.id)) }
    }

    /// Words that start with the skeleton of `phonetic` but are longer than it, shortest first.
    public func completions(for phonetic: String, limit: Int) -> [String] {
        let sk = WordIndex.skeleton(phonetic)
        guard sk.count >= 2, limit > 0 else { return [] }
        let lo = lowerBound(sk, prefixOnly: true, after: false)
        let hi = lowerBound(sk, prefixOnly: true, after: true)
        var best: [(Int, Int32)] = []
        for id in bySkeleton[lo..<hi] {
            let n = skeletonLength(Int(id))
            guard n > sk.count else { continue }
            let item = (n, id)
            if best.count < limit {
                best.append(item)
                best.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            } else if let last = best.last, item.0 < last.0 || (item.0 == last.0 && item.1 < last.1) {
                best[best.count - 1] = item
                best.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            }
        }
        return best.map { word(Int($0.1)) }
    }

    /// Edit distance where letters of the same loose class (ত/ট, ন/ণ, শ/স, ...) count as equal: what
    /// is left are the vowel, conjunct and letter differences the loose key ignored.
    static func looseDistance(_ a: [UInt32], _ b: [UInt32]) -> Int {
        distance(a, b) { x, y in x == y || looseClass(x).map { $0 == looseClass(y) } == true }
    }

    static func distance(_ a: [UInt32], _ b: [UInt32], same: (UInt32, UInt32) -> Bool = { $0 == $1 }) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = same(a[i - 1], b[j - 1]) ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    // MARK: Reading the dictionary file

    /// Calls `body` for every word of `{"group": ["word", ...], ...}`, in file order, without
    /// building Foundation objects for the 160k strings. Throws if the file has another shape.
    static func forEachWord(in data: Data, _ body: (String) -> Void) throws {
        let bad = CocoaError(.fileReadCorruptFile)
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            var i = 0
            func skipSpace() { while i < n, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 } }
            func next() throws -> UInt8 {
                skipSpace()
                guard i < n else { throw bad }
                return b[i]
            }
            func string() throws -> String {
                guard try next() == 0x22 else { throw bad }
                i += 1
                let start = i
                var escaped = false
                while i < n, b[i] != 0x22 {
                    if b[i] == 0x5C { escaped = true; i += 1 }
                    i += 1
                }
                guard i < n else { throw bad }
                let bytes = UnsafeBufferPointer(rebasing: b[start..<i])
                i += 1
                guard escaped else { return String(decoding: bytes, as: UTF8.self) }
                // Escapes do not occur in the OpenBangla file; decode them properly if they ever do.
                let literal = Data([0x5B, 0x22]) + Data(bytes) + Data([0x22, 0x5D])
                guard let s = (try JSONSerialization.jsonObject(with: literal) as? [String])?.first else { throw bad }
                return s
            }
            guard try next() == 0x7B else { throw bad }
            i += 1
            if try next() == 0x7D { return }
            while true {
                _ = try string()
                guard try next() == 0x3A else { throw bad }
                i += 1
                guard try next() == 0x5B else { throw bad }
                i += 1
                if try next() == 0x5D {
                    i += 1
                } else {
                    while true {
                        body(try string())
                        let c = try next()
                        i += 1
                        if c == 0x2C { continue }
                        if c == 0x5D { break }
                        throw bad
                    }
                }
                let c = try next()
                i += 1
                if c == 0x2C { continue }
                if c == 0x7D { return }
                throw bad
            }
        }
    }
}
