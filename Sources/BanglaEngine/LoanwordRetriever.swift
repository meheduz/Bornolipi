import Foundation

/// Experimental, off by default (`EngineSettings.loanwordSuggestions`): known words that a typed roman
/// word may stand for when Avro's letter-by-letter reading misses them, above all English loanwords
/// (term: টার্ম, bank: ব্যাংক) and informal romanisations. It never invents a spelling: every result
/// is a word of its lexicon (the dictionary plus attested OpenSubtitles words).
///
/// A port of the lab prototype "retrieval" (lexicon retrieval with English-aware consonant keys); it
/// returns exactly the prototype's `generate()` results (`loanword-parity` checks this).
/// 1. `RomanReading` reads the typed word into a small beam of templates: consonant classes, the roman
///    vowel letters around them (with context marks) and the roman letters behind each class. Its rules
///    know English spelling (c before e/i, silent letters, -tion, magic e) and informal romanisation
///    (h for aspiration, kh for ক্ষ). Two learned cost tables (English loanword pairs, native
///    romanisations) price every rule option, which makes the beam a weighted transducer.
/// 2. Every lexicon word is filed under its collapsed consonant-class key (`BanglaShape`: ্য য় ্ব are
///    vowel material there, not consonants). The words sharing a template's key are scored: template
///    cost + learned costs of the vowel material and of the consonant letters + a frequency prior.
/// 3. The best words within 4 nats of the best one are returned, best first.
/// Data: Data/loanword-*. The lexicon is written by scripts/build-loanword-data.py; the cost tables and the
/// English words are the prototype's.
public final class LoanwordRetriever {
    public struct Candidate: Equatable {
        public let word: String
        /// Lower is better (a negative log score).
        public let cost: Double
        /// A Data/dictionary.json word, not one the lexicon added from subtitles.
        public var inDictionary = true
    }

    public enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case badFormat(String)
        public var description: String {
            switch self {
            case .unreadable(let s): return "unreadable: \(s)"
            case .badFormat(let s): return "bad format: \(s)"
            }
        }
    }

    // The prototype's configuration (its config.json).
    static let outMargin = 4.0, classMismatch = 2.0, englishBias = 1.0, beamKeep = 12, beamWidth = 24, beamMargin = 6.0
    static let priorWeight = 0.25, priorDelta = 1.0

    // Lexicon ids: the dictionary words first (WordIndex order, without the words the prototype leaves
    // out), then the added words, whose UTF-8 is kept here.
    private let dictionary: WordIndex
    private let dictionaryCount: Int
    /// For every WordIndex id that is not a lexicon word, ascending: how many lexicon words precede it.
    private let skippedAfter: [Int32]
    /// Lexicon ids of dictionary words the prototype writes differently from the file (nukta, ZWNJ).
    private let renormalized: Set<Int32>
    private let addedUTF8: [UInt8]
    private let addedEnd: [UInt32]

    // Entries: the lexicon words with at least one consonant class, in (key, id) order, so the words of
    // one key are contiguous. Entry e has entryLength[e] classes, whose consonant spellings are in
    // `letters`, and one vowel segment more, in `segments` at its letters offset + e. The scoring loop
    // reads these fixed arrays through unchecked buffers, allocated once and freed in deinit.
    private let bucketKey: UnsafeMutableBufferPointer<UInt64>
    private let bucketStart: UnsafeMutableBufferPointer<Int32>
    private let bucketLetters: UnsafeMutableBufferPointer<Int32>
    private let entryID: UnsafeMutableBufferPointer<Int32>
    private let entryPrior: UnsafeMutableBufferPointer<UInt16>
    private let entryLength: UnsafeMutableBufferPointer<UInt8>
    private let letters: UnsafeMutableBufferPointer<UInt8>
    /// Vowel material ids, most frequent first; 255 means "see rareSegments".
    private let segments: UnsafeMutableBufferPointer<UInt8>
    private let rareSegments: [Int32: UInt16]
    /// The consonant class of each consonant spelling id.
    private let letterClass: UnsafeMutableBufferPointer<UInt8>
    private let priors: UnsafeMutableBufferPointer<Double>

    private let models: [Model]
    private let english: Set<String>
    private var work = Workspace()
    /// Per-word scratch of the scoring loop: classes, collapsed classes and segments, segment costs.
    private let scratchClasses: UnsafeMutablePointer<UInt8>
    private let scratchSegments: UnsafeMutablePointer<Int>
    private let scratchCosts: UnsafeMutablePointer<Double>
    private let lock = NSLock()

    /// Words in the lexicon.
    public let count: Int
    /// Words of the lexicon file's `=` lines that are not in the dictionary it was given (left out, for
    /// diagnostics: the file was built for an older dictionary).
    public let staleCounts: Int
    /// How long building the retriever took.
    public let loadMilliseconds: Double
    /// Bytes held by the lexicon, the entries and the cost memos (not counting the dictionary it shares).
    public var footprintBytes: Int {
        lock.lock(); defer { lock.unlock() }
        var bytes: Int = skippedAfter.count * 4 + renormalized.count * 8
        bytes += addedUTF8.count + addedEnd.count * 4
        bytes += bucketKey.count * 8 + bucketStart.count * 4 + bucketLetters.count * 4
        bytes += entryID.count * 4 + entryPrior.count * 2 + entryLength.count
        bytes += letters.count + segments.count + rareSegments.count * 16 + priors.count * 8
        for m in models { bytes += m.segments.bytes + m.consonants.bytes }
        return bytes
    }

    struct Model {
        /// Cost of every rule option, by `RomanReading.tags` index.
        let ruleCost: [Double]
        let segments: LoanwordCostMemo
        let consonants: LoanwordCostMemo
    }

    /// Builds the retriever from `Data/loanword-*` and the loaded dictionary, which it shares. Takes about
    /// a tenth of a second. Temporary memory is kept low (the allocator keeps what a load used at its
    /// peak): the shapes are computed twice rather than stored in id order and then reordered.
    public init(dataDirectory: URL, dictionary: WordIndex) throws {
        let start = DispatchTime.now().uptimeNanoseconds
        self.dictionary = dictionary
        var lexicon = try LexiconFile(dataDirectory.appendingPathComponent("loanword-lexicon.tsv"))

        // The dictionary part, derived as the prototype does: normalised words of Data/dictionary.json
        // in file order whose first letter is a consonant or an independent vowel and whose letters are
        // all Bangla, the first of equal words only. The counts of the dictionary words (`=` lines) are
        // in the same order, so they are matched by walking both lists, as long as every word is found.
        // When one is not (the dictionary was edited), they are matched by sorting: the words of the lexicon
        // file are sorted with the dictionary words by (hash, position), so one pass finds the equal
        // dictionary words, the counts and the added words that are dictionary words now.
        var candidates: [Int32] = [], order: [UInt64] = [], changed: [Bool] = []
        // Counts are at least 1, so 0 means "no count".
        var countOf: [UInt32] = [], walked = 0
        candidates.reserveCapacity(dictionary.count); changed.reserveCapacity(dictionary.count); countOf.reserveCapacity(dictionary.count)
        order.reserveCapacity(dictionary.count + lexicon.added.count)
        var scalars: [UInt32] = [], normal: [UInt32] = [], bytes: [UInt8] = []
        dictionary.forEachWordUTF8 { id, utf8 in
            LoanwordRetriever.decode(utf8, into: &scalars)
            BanglaShape.normalize(scalars, into: &normal)
            guard let first = normal.first, BanglaShape.startsWord(first), normal.allSatisfy({ $0 >= 0x0980 && $0 <= 0x09FF }) else { return }
            LoanwordRetriever.encode(normal, into: &bytes)
            order.append((LoanwordRetriever.fnv1a(bytes) >> 20) << 20 | UInt64(candidates.count))
            candidates.append(Int32(id))
            changed.append(normal != scalars)
            if walked < lexicon.counted.count, lexicon.counted.word(walked, equals: bytes) {
                countOf.append(lexicon.counted.counts[walked]); walked += 1
            } else {
                countOf.append(0)
            }
        }
        // Positions: the dictionary candidates, then the `=` words (only when the walk did not find them
        // all), then the `+` words.
        let countedAt = candidates.count, addedAt = countedAt + lexicon.counted.count
        guard addedAt + lexicon.added.count < 1 << 20 else { throw LoadError.badFormat("too many words") }
        var matched = walked
        if walked < lexicon.counted.count {
            matched = 0
            for k in countOf.indices { countOf[k] = 0 }
            for k in 0..<lexicon.counted.count { order.append((lexicon.counted.hash(k) >> 20) << 20 | UInt64(countedAt + k)) }
        }
        for k in 0..<lexicon.added.count { order.append((lexicon.added.hash(k) >> 20) << 20 | UInt64(addedAt + k)) }
        var duplicate = [Bool](repeating: false, count: candidates.count)
        var addedInDictionary = Set<Int>()
        WordIndex.radixSort(&order)
        // The normalised UTF-8 of position `p`, into `out`.
        func fill(_ p: Int, _ out: inout [UInt8]) {
            out.removeAll(keepingCapacity: true)
            if p >= addedAt { out.append(contentsOf: lexicon.added.slice(p - addedAt)); return }
            if p >= countedAt { out.append(contentsOf: lexicon.counted.slice(p - countedAt)); return }
            dictionary.withWordUTF8(Int(candidates[p])) { utf8 in
                if !changed[p] { out.append(contentsOf: utf8); return }
                LoanwordRetriever.decode(utf8, into: &scalars)
                BanglaShape.normalize(scalars, into: &normal)
                LoanwordRetriever.encode(normal, into: &out)
            }
        }
        // Position q holds the same word as the earlier position p.
        func same(_ p: Int, _ q: Int, _ word: [UInt8]) throws {
            let twice = { LoadError.badFormat("word listed twice: \(String(decoding: word, as: UTF8.self))") }
            guard p < countedAt else { throw twice() }
            if q < countedAt {
                duplicate[q] = true
                // The walk gives a count to the copy it meets in order, which is the later one when an edit
                // added the word again earlier: the copy that is kept takes it.
                if countOf[p] == 0 { countOf[p] = countOf[q] }
            } else if q < addedAt {
                guard countOf[p] == 0 else { throw twice() }
                countOf[p] = lexicon.counted.counts[q - countedAt]; matched += 1
            } else {
                // An added word that is in the dictionary now: kept once, as the dictionary word.
                addedInDictionary.insert(q - addedAt)
                if countOf[p] == 0 { countOf[p] = lexicon.added.counts[q - addedAt] }
            }
        }
        var x: [UInt8] = [], y: [UInt8] = [], members: [Int] = [], settled: [Bool] = []
        var g = 0
        while g < order.count {
            var e = g + 1
            while e < order.count, order[e] >> 20 == order[g] >> 20 { e += 1 }
            if e - g == 2 {
                let p = Int(order[g] & (1 << 20 - 1)), q = Int(order[g + 1] & (1 << 20 - 1))
                fill(min(p, q), &x); fill(max(p, q), &y)
                if x == y { try same(min(p, q), max(p, q), y) }
            } else if e - g > 2 {
                // Positions ascending: the first of equal words is a dictionary word whenever there is one.
                members.removeAll(keepingCapacity: true)
                for k in g..<e { members.append(Int(order[k] & (1 << 20 - 1))) }
                members.sort()
                settled.removeAll(keepingCapacity: true)
                settled.append(contentsOf: repeatElement(false, count: members.count))
                for a in members.indices where !settled[a] {
                    fill(members[a], &x)
                    for b in members.indices where b > a && !settled[b] {
                        fill(members[b], &y)
                        guard x == y else { continue }
                        settled[b] = true
                        try same(members[a], members[b], y)
                    }
                }
            }
            g = e
        }
        order = []
        staleCounts = lexicon.counted.count - matched
        var kept: [Int32] = [], keptCount: [UInt32] = []
        kept.reserveCapacity(candidates.count); keptCount.reserveCapacity(candidates.count)
        var renormalized = Set<Int32>()
        for (k, id) in candidates.enumerated() where !duplicate[k] {
            if changed[k] { renormalized.insert(Int32(kept.count)) }
            kept.append(id)
            keptCount.append(countOf[k])
        }
        candidates = []; changed = []; duplicate = []; countOf = []
        var skippedAfter: [Int32] = []
        var next = 0
        for (k, id) in kept.enumerated() {
            while next < Int(id) { skippedAfter.append(Int32(k)); next += 1 }
            next = Int(id) + 1
        }
        while next < dictionary.count { skippedAfter.append(Int32(kept.count)); next += 1 }
        self.skippedAfter = skippedAfter
        self.renormalized = renormalized
        dictionaryCount = kept.count
        var added = lexicon.added
        lexicon = LexiconFile()
        if !addedInDictionary.isEmpty { added = added.removing(addedInDictionary) }
        let addedEnds = added.end
        addedUTF8 = added.utf8
        addedEnd = addedEnds
        let total = kept.count + addedEnds.count
        count = total

        // Counts and priors.
        var priorOf = [UInt16](repeating: 0, count: total)
        var priorIndex: [UInt32: UInt16] = [:], priors: [Double] = []
        func setPrior(_ id: Int, _ c: UInt32) throws {
            if let k = priorIndex[c] { priorOf[id] = k; return }
            guard priors.count < Int(UInt16.max) else { throw LoadError.badFormat("too many distinct counts") }
            priorIndex[c] = UInt16(priors.count)
            priorOf[id] = UInt16(priors.count)
            // As the prototype: beta * -ln(count + delta), + 0 for words outside the dictionary.
            priors.append(LoanwordRetriever.priorWeight * -log(Double(c) + LoanwordRetriever.priorDelta) + 0.0)
        }
        for (id, c) in keptCount.enumerated() { try setPrior(id, c) }
        keptCount = []
        for (k, c) in added.counts.enumerated() { try setPrior(kept.count + k, c) }
        let addedBytes = addedUTF8

        // The scalars of lexicon word `id`, normalised.
        func load(_ id: Int) {
            if id < kept.count {
                dictionary.withWordUTF8(Int(kept[id])) { LoanwordRetriever.decode($0, into: &scalars) }
                BanglaShape.normalize(scalars, into: &normal)
            } else {
                let k = id - kept.count
                let r = (k == 0 ? 0 : Int(addedEnds[k - 1]))..<Int(addedEnds[k])
                addedBytes.withUnsafeBufferPointer { LoanwordRetriever.decode(UnsafeBufferPointer(rebasing: $0[r]), into: &normal) }
            }
        }

        // Shapes, first pass: keys, sizes, consonant spellings, and how often each vowel material occurs.
        var keys: [UInt64] = []
        keys.reserveCapacity(total)
        var letterTotal = 0, segmentTotal = 0
        var segmentUses: [UInt64: Int] = [:], letterID: [UInt64: UInt8] = [:]
        var letterCodes: [UInt64] = [], letterClass: [UInt8] = []
        var shape = BanglaShape.Builder()
        for id in 0..<total {
            load(id)
            shape.reset()
            // A word without a consonant class has no key; the prototype never retrieves it.
            guard BanglaShape.shape(normal, into: &shape), !shape.classes.isEmpty else { continue }
            guard shape.classes.count <= Int(UInt8.max) else { throw LoadError.badFormat("word too long") }
            for c in shape.segments { segmentUses[c, default: 0] += 1 }
            for (k, c) in shape.letters.enumerated() {
                let l: UInt8
                if let x = letterID[c] {
                    l = x
                } else {
                    guard letterCodes.count < Int(UInt8.max) else { throw LoadError.badFormat("too many consonant spellings") }
                    l = UInt8(letterCodes.count)
                    letterID[c] = l; letterCodes.append(c); letterClass.append(BanglaShape.spellingClass(c))
                }
                // The scoring loop reads a word's classes from its spellings, so they must agree.
                guard letterClass[Int(l)] == shape.classes[k] else { throw LoadError.badFormat("class of \(BanglaShape.letterString(c))") }
            }
            letterTotal += shape.classes.count
            segmentTotal += shape.classes.count + 1
            keys.append(BanglaShape.packedKey(shape.classes) << 20 | UInt64(id))
        }
        // Vowel material ids by frequency, so that all but the rarest fit in a byte.
        let byUse = segmentUses.keys.sorted { segmentUses[$0]! != segmentUses[$1]! ? segmentUses[$0]! > segmentUses[$1]! : $0 < $1 }
        var segmentRank: [UInt64: UInt16] = [:]
        for (r, code) in byUse.enumerated() { segmentRank[code] = UInt16(r) }
        guard byUse.count < Int(UInt16.max) else { throw LoadError.badFormat("too many vowel segments") }
        WordIndex.radixSort(&keys)
        var buckets = 0
        for (e, packed) in keys.enumerated() where e == 0 || packed >> 20 != keys[e - 1] >> 20 { buckets += 1 }

        // Cost models and the English words.
        let segmentVocabulary = byUse.map(BanglaShape.segmentString)
        let letterVocabulary = letterCodes.map(BanglaShape.letterString)
        var models: [Model] = []
        for name in ["en", "native"] {
            let url = dataDirectory.appendingPathComponent("loanword-costs-\(name).json")
            guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(url.lastPathComponent) }
            let file = try JSONDecoder().decode(CostFile.self, from: data)
            var rules = RomanReading.priorCosts
            for (tag, cost) in file.rules { rules[tag] = cost }
            models.append(Model(ruleCost: RomanReading.tags.map { rules[$0] ?? 0.0 },
                                segments: LoanwordCostMemo(segments: file.segments, vocabulary: segmentVocabulary),
                                consonants: LoanwordCostMemo(consonants: file.consonants, vocabulary: letterVocabulary)))
        }
        self.models = models
        let englishURL = dataDirectory.appendingPathComponent("loanword-english.txt")
        guard let englishText = try? String(contentsOf: englishURL, encoding: .utf8) else { throw LoadError.unreadable(englishURL.lastPathComponent) }
        english = Set(englishText.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init))

        // Nothing throws after this point, so these allocations are always freed by deinit.
        func buffer<T>(_ n: Int, _ zero: T) -> UnsafeMutableBufferPointer<T> {
            let p = UnsafeMutableBufferPointer<T>.allocate(capacity: n)
            p.initialize(repeating: zero)
            return p
        }
        let bucketKey = buffer(buckets, UInt64(0)), bucketStart = buffer(buckets + 1, Int32(0)), bucketLetters = buffer(buckets, Int32(0))
        let entryID = buffer(keys.count, Int32(0)), entryPrior = buffer(keys.count, UInt16(0)), entryLength = buffer(keys.count, UInt8(0))
        let letters = buffer(letterTotal, UInt8(0)), segments = buffer(segmentTotal, UInt8(0))
        var rare: [Int32: UInt16] = [:]
        // Shapes, second pass: the entries in key order.
        var b = -1, letterAt = 0, segmentAt = 0
        for (e, packed) in keys.enumerated() {
            let key = packed >> 20, id = Int(packed & (1 << 20 - 1))
            if b < 0 || bucketKey[b] != key {
                b += 1
                bucketKey[b] = key; bucketStart[b] = Int32(e); bucketLetters[b] = Int32(letterAt)
            }
            load(id)
            shape.reset()
            _ = BanglaShape.shape(normal, into: &shape)
            entryID[e] = Int32(id); entryPrior[e] = priorOf[id]; entryLength[e] = UInt8(shape.classes.count)
            for c in shape.letters { letters[letterAt] = letterID[c]!; letterAt += 1 }
            for c in shape.segments {
                let r = segmentRank[c]!
                if r < 255 { segments[segmentAt] = UInt8(r) } else { rare[Int32(segmentAt)] = r; segments[segmentAt] = 255 }
                segmentAt += 1
            }
        }
        bucketStart[buckets] = Int32(keys.count)
        self.bucketKey = bucketKey
        self.bucketStart = bucketStart
        self.bucketLetters = bucketLetters
        self.entryID = entryID
        self.entryPrior = entryPrior
        self.entryLength = entryLength
        self.letters = letters
        self.segments = segments
        rareSegments = rare
        self.letterClass = LoanwordRetriever.fixed(letterClass)
        self.priors = LoanwordRetriever.fixed(priors)
        scratchClasses = .allocate(capacity: 512)
        scratchSegments = .allocate(capacity: 257)
        scratchCosts = .allocate(capacity: 257)
        loadMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    deinit {
        scratchClasses.deallocate(); scratchSegments.deallocate(); scratchCosts.deallocate()
        bucketKey.deallocate(); bucketStart.deallocate(); bucketLetters.deallocate(); entryID.deallocate(); entryPrior.deallocate()
        entryLength.deallocate(); letters.deallocate(); segments.deallocate(); letterClass.deallocate(); priors.deallocate()
    }

    /// A fixed copy of `a` in its own allocation.
    private static func fixed<T>(_ a: [T]) -> UnsafeMutableBufferPointer<T> {
        let p = UnsafeMutableBufferPointer<T>.allocate(capacity: a.count)
        _ = p.initialize(from: a)
        return p
    }

    private struct CostFile: Decodable {
        let rules: [String: Double]
        let segments: [String: [String: Int]]
        let consonants: [String: [String: Int]]
    }

    /// Data/loanword-lexicon.tsv (the format is in its header).
    struct LexiconFile {
        /// Words with their counts, in file order.
        struct Words {
            var utf8: [UInt8] = []
            var end: [UInt32] = []
            var counts: [UInt32] = []
            var count: Int { end.count }

            func range(_ k: Int) -> Range<Int> { (k == 0 ? 0 : Int(end[k - 1]))..<Int(end[k]) }
            func slice(_ k: Int) -> ArraySlice<UInt8> { utf8[range(k)] }
            func word(_ k: Int, equals bytes: [UInt8]) -> Bool {
                let r = range(k)
                guard r.count == bytes.count else { return false }
                return utf8.withUnsafeBufferPointer { u in bytes.withUnsafeBufferPointer { memcmp(u.baseAddress! + r.lowerBound, $0.baseAddress!, r.count) == 0 } }
            }
            func hash(_ k: Int) -> UInt64 { utf8.withUnsafeBufferPointer { LoanwordRetriever.fnv1a(UnsafeBufferPointer(rebasing: $0[range(k)])) } }
            /// These words without the ones at `positions`.
            func removing(_ positions: Set<Int>) -> Words {
                var w = Words()
                for k in 0..<count where !positions.contains(k) {
                    w.utf8.append(contentsOf: utf8[range(k)]); w.end.append(UInt32(w.utf8.count)); w.counts.append(counts[k])
                }
                return w
            }
            mutating func append(_ bytes: UnsafeBufferPointer<UInt8>, _ c: UInt32) {
                utf8.append(contentsOf: bytes); end.append(UInt32(utf8.count)); counts.append(c)
            }
        }

        static let header = "# bornolipi.loanword-lexicon\t2\n"
        /// The dictionary words that have a count (`=` lines).
        var counted = Words()
        /// The added words (`+` lines).
        var added = Words()

        init() {}

        init(_ url: URL) throws {
            guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(url.lastPathComponent) }
            guard data.starts(with: Data(LexiconFile.header.utf8)) else {
                throw LoadError.badFormat("the first line must be \"\(LexiconFile.header.dropLast())\" (rebuild it with scripts/build-loanword-data.py)")
            }
            var counted = Words(), added = Words()
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let b = raw.bindMemory(to: UInt8.self)
                var i = 0, lineNumber = 0
                func field() -> Range<Int> {
                    let s = i
                    while i < b.count, b[i] != 0x09, b[i] != 0x0A { i += 1 }
                    return s..<i
                }
                func number(_ r: Range<Int>) -> UInt32? {
                    guard !r.isEmpty, r.count < 11 else { return nil }
                    var v: UInt64 = 0
                    for k in r {
                        guard b[k] >= 0x30, b[k] <= 0x39 else { return nil }
                        v = v * 10 + UInt64(b[k] - 0x30)
                    }
                    return v <= UInt32.max ? UInt32(v) : nil
                }
                while i < b.count {
                    lineNumber += 1
                    if b[i] == 0x23 || b[i] == 0x0A {   // a comment or an empty line
                        while i < b.count, b[i] != 0x0A { i += 1 }
                        i += 1
                        continue
                    }
                    var bad: LoadError { .badFormat("line \(lineNumber): expected \"=\" or \"+\", a word and a count of at least 1, tab-separated") }
                    let kind = field()
                    guard kind.count == 1, i < b.count, b[i] == 0x09 else { throw bad }
                    i += 1
                    let a = field()
                    guard i < b.count, b[i] == 0x09 else { throw bad }
                    i += 1
                    let c = field()
                    guard i == b.count || b[i] == 0x0A else { throw bad }
                    i += 1
                    // A word is Bangla letters only, U+0980-U+09FF, which is E0 A6 80 to E0 A7 BF in UTF-8 (so a
                    // count where the word belongs, as in a file of the first format, is refused).
                    guard !a.isEmpty, a.count % 3 == 0, let n = number(c), n > 0 else { throw bad }
                    for k in stride(from: a.lowerBound, to: a.upperBound, by: 3) {
                        guard b[k] == 0xE0, b[k + 1] & 0xFE == 0xA6, b[k + 2] & 0xC0 == 0x80 else { throw bad }
                    }
                    let word = UnsafeBufferPointer(rebasing: b[a])
                    switch b[kind.lowerBound] {
                    case 0x3D: counted.append(word, n)   // =
                    case 0x2B: added.append(word, n)     // +
                    default: throw bad
                    }
                }
            }
            self.counted = counted
            self.added = added
        }
    }

    // MARK: Generation

    /// Lexicon words for the typed roman word, best first: at most `limit`, all within 4 nats of the
    /// best. Only the letters a-z of `roman` are read (lowercased), as in the prototype.
    public func generate(_ roman: String, limit: Int = 10) -> [Candidate] {
        var s: [UInt8] = []
        s.reserveCapacity(roman.utf8.count)
        for u in roman.unicodeScalars {
            if u.value >= 0x61 && u.value <= 0x7A {
                s.append(UInt8(u.value))
            } else if u.value >= 0x41 && u.value <= 0x5A {
                s.append(UInt8(u.value + 0x20))
            }
        }
        guard !s.isEmpty, limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return rank(s, limit: limit).map { Candidate(word: word(Int($0.id)), cost: $0.cost, inDictionary: Int($0.id) < dictionaryCount) }
    }

    /// The lexicon word with id `id`, normalised as the prototype writes it.
    func word(_ id: Int) -> String {
        if id < dictionaryCount {
            // WordIndex id: the lexicon id plus the words left out before it.
            var lo = 0, hi = skippedAfter.count
            while lo < hi { let mid = (lo + hi) >> 1; if skippedAfter[mid] <= Int32(id) { lo = mid + 1 } else { hi = mid } }
            let raw = dictionary.word(id + lo)
            return renormalized.contains(Int32(id)) ? BanglaShape.normalized(raw) : raw
        }
        let k = id - dictionaryCount
        let r = (k == 0 ? 0 : Int(addedEnd[k - 1]))..<Int(addedEnd[k])
        return addedUTF8.withUnsafeBufferPointer { String(decoding: UnsafeBufferPointer(rebasing: $0[r]), as: UTF8.self) }
    }

    private func rank(_ s: [UInt8], limit: Int) -> [(cost: Double, id: Int32)] {
        // The workspace's buffers, borrowed for this query.
        var w = Workspace()
        swap(&w, &work)
        defer { swap(&w, &work) }
        let isEnglish = english.contains(String(decoding: s, as: UTF8.self))
        RomanReading.options(s, into: &w)
        w.resetTemplates()
        for (mi, m) in models.enumerated() {
            m.segments.beginQuery(); m.consonants.beginQuery()
            let bias = isEnglish && mi != 0 ? LoanwordRetriever.englishBias : 0.0
            let first = w.tCost.count
            RomanReading.beam(s, ruleCost: m.ruleCost, width: LoanwordRetriever.beamWidth, margin: LoanwordRetriever.beamMargin, in: &w)
            // w.order: the final states within the margin, cheapest first; one template per class sequence.
            for k in 0..<w.order.count {
                let state = Int(w.order[k])
                RomanReading.template(of: state, s, in: &w)
                guard w.isNewClassSequence(since: first) else { continue }
                w.addTemplate(model: mi, bias: bias, cost: w.stCost[state], memo: m)
                if w.tCost.count - first >= LoanwordRetriever.beamKeep { break }
            }
        }
        // Templates grouped by key (templates without a consonant class are never looked up).
        var groups: [Int] = []
        groups.reserveCapacity(w.tCost.count)
        for t in w.tCost.indices where w.tKey[t] != 0 { groups.append(t) }
        let tKey = w.tKey, tModel = w.tModel, tCost = w.tCost, tBias = w.tBias, tStart = w.tStart, tLength = w.tLength
        let tClasses = w.tClasses, tSegRows = w.tSegRows, tLabelRows = w.tLabelRows
        let tColStart = w.tCollapsedStart, tColLength = w.tCollapsedLength, tCollapsed = w.tCollapsed, tColRows = w.tCollapsedRows
        groups.sort { tKey[$0] != tKey[$1] ? tKey[$0] < tKey[$1] : $0 < $1 }
        var ranges: [(start: Int, end: Int)] = []
        var gs = 0
        while gs < groups.count {
            var ge = gs + 1
            while ge < groups.count, tKey[groups[ge]] == tKey[groups[gs]] { ge += 1 }
            ranges.append((gs, ge))
            gs = ge
        }
        var top: [(cost: Double, id: Int32)] = []
        top.reserveCapacity(limit + 1)
        let wordClasses = scratchClasses, wc2 = scratchClasses + 256, ws2 = scratchSegments, costs = scratchCosts
        let entryLength = self.entryLength, letters = self.letters, letterClass = self.letterClass
        let entryPrior = self.entryPrior, entryID = self.entryID, priors = self.priors
        let segMemo0 = models[0].segments, segMemo1 = models[1].segments
        let consMemo0 = models[0].consonants, consMemo1 = models[1].consonants
        let segTable0 = segMemo0.table, segTable1 = segMemo1.table, consTable0 = consMemo0.table, consTable1 = consMemo1.table
        let segWidth = segMemo0.width, consWidth = consMemo0.width
        let cm = LoanwordRetriever.classMismatch
        for (g, gEnd) in ranges {
            let key = tKey[groups[g]]
            var lo = 0, hi = bucketKey.count
            while lo < hi { let mid = (lo + hi) >> 1; if bucketKey[mid] < key { lo = mid + 1 } else { hi = mid } }
            guard lo < bucketKey.count, bucketKey[lo] == key else { continue }
            var letterAt = Int(bucketLetters[lo])
            for e in Int(bucketStart[lo])..<Int(bucketStart[lo + 1]) {
                let wn = Int(entryLength[e])
                let segAt = letterAt + e
                defer { letterAt += wn }
                for k in 0..<wn { wordClasses[k] = letterClass[Int(letters[letterAt + k])] }
                var best = Double.infinity
                for gi in g..<gEnd {
                    let t = groups[gi]
                    let n = tLength[t], ts = tStart[t], mi = tModel[t]
                    var same = wn == n
                    if same { for k in 0..<n where wordClasses[k] != tClasses[ts + k] { same = false; break } }
                    var sc: Double
                    if same {
                        sc = 0.0
                        let table = mi == 0 ? segTable0 : segTable1, rows = ts + t
                        for k in 0...n {
                            let r = Int(tSegRows[rows + k]), v = segment(segAt + k)
                            var c = table[r * segWidth + v]
                            if c.isNaN { c = (mi == 0 ? segMemo0 : segMemo1).fill(r, v) }
                            sc += c
                        }
                        let ctable = mi == 0 ? consTable0 : consTable1
                        for k in 0..<n {
                            let r = Int(tLabelRows[ts + k]), v = Int(letters[letterAt + k])
                            var c = ctable[r * consWidth + v]
                            if c.isNaN { c = (mi == 0 ? consMemo0 : consMemo1).fill(r, v) }
                            sc += c
                        }
                    } else {
                        sc = cm
                        if wn > 8 || n > 8 {
                            var eq = min(wn, 8) == min(n, 8)
                            if eq { for k in 0..<min(n, 8) where wordClasses[k] != tClasses[ts + k] { eq = false; break } }
                            if !eq { sc = cm * 2 }
                        }
                        // Compare the collapsed sequences (runs of one class merged).
                        var wc2n = 0
                        ws2[0] = segment(segAt)
                        for k in 0..<wn {
                            let c = wordClasses[k]
                            if wc2n > 0, wc2[wc2n - 1] == c { ws2[wc2n] = segment(segAt + k + 1); continue }
                            wc2[wc2n] = c; wc2n += 1; ws2[wc2n] = segment(segAt + k + 1)
                        }
                        let cs = tColStart[t], cn = tColLength[t]
                        var equal = cn == wc2n
                        if equal { for k in 0..<cn where tCollapsed[cs + k] != wc2[k] { equal = false; break } }
                        if equal {
                            let table = mi == 0 ? segTable0 : segTable1
                            for k in 0...cn {
                                let r = Int(tColRows[cs + t + k]), v = ws2[k]
                                var c = table[r * segWidth + v]
                                if c.isNaN { c = (mi == 0 ? segMemo0 : segMemo1).fill(r, v) }
                                costs[k] = c
                            }
                            sc += LoanwordRetriever.pythonSum(UnsafeBufferPointer(start: costs, count: cn + 1))
                        } else {
                            sc += 3.0 * Double(abs(cn - wc2n)) + 3.0
                        }
                    }
                    let tot = tCost[t] + sc + tBias[t]
                    if tot < best { best = tot }
                }
                // Keep the `limit` best (cost, id), ties by id.
                let item = (cost: best + priors[Int(entryPrior[e])], id: entryID[e])
                if top.count == limit {
                    let worst = top[limit - 1]
                    guard item.cost < worst.cost || (item.cost == worst.cost && item.id < worst.id) else { continue }
                    top[limit - 1] = item
                } else {
                    top.append(item)
                }
                var k = top.count - 1
                while k > 0, top[k].cost < top[k - 1].cost || (top[k].cost == top[k - 1].cost && top[k].id < top[k - 1].id) {
                    top.swapAt(k, k - 1)
                    k -= 1
                }
            }
        }
        guard let bestCost = top.first?.cost else { return [] }
        let cut = bestCost + LoanwordRetriever.outMargin
        return top.filter { $0.cost <= cut }
    }

    @inline(__always) private func segment(_ at: Int) -> Int {
        let v = segments[at]
        return v != 255 ? Int(v) : Int(rareSegments[Int32(at)]!)
    }

    /// Python's `sum()` of floats (3.12 and later): Neumaier's compensated summation, so totals match
    /// the prototype to the last bit.
    static func pythonSum<C: Collection>(_ xs: C) -> Double where C.Element == Double {
        guard var f = xs.first else { return 0 }
        f = 0 + f
        var c = 0.0
        for x in xs.dropFirst() {
            let t = f + x
            if abs(f) >= abs(x) { c += (f - t) + x } else { c += (x - t) + f }
            f = t
        }
        if c != 0 && c.isFinite { f += c }
        return f
    }

    // MARK: Helpers

    static func decode(_ utf8: UnsafeBufferPointer<UInt8>, into out: inout [UInt32]) {
        out.removeAll(keepingCapacity: true)
        _ = transcode(utf8.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: false) { out.append($0) }
    }

    static func encode(_ scalars: [UInt32], into out: inout [UInt8]) {
        out.removeAll(keepingCapacity: true)
        for u in scalars { if let s = Unicode.Scalar(u) { out.append(contentsOf: UTF8.encode(s)!) } }
    }

    static func fnv1a<C: Collection>(_ bytes: C, _ seed: UInt64 = 0xCBF2_9CE4_8422_2325) -> UInt64 where C.Element == UInt8 {
        var h = seed
        for b in bytes { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
        return h
    }
}
