import Foundation

public struct Suggestion: Equatable {
    public let preceding: String
    public let trailing: String
    /// Candidate words without the surrounding punctuation.
    public let words: [String]
    /// Index of the candidate that is selected by default.
    public let selected: Int
    /// The exact conversion of everything typed, and its position in `words`. Avro converts
    /// punctuation in context (".5" is .৫, ".`" is a plain full stop), so for the exact candidate
    /// the whole conversion is used instead of converting the punctuation on its own.
    public var exact: (index: Int, text: String)? = nil
    /// Index in `words` of the exact conversion of the word.
    public var exactIndex: Int? = nil
    /// Index in `words` of an automatic correction (autocorrect table), when it differs from the exact conversion.
    public var autocorrected: Int? = nil
    /// How many leading candidates are the engine's list as 0.1.0 showed it, when words were appended after it;
    /// nil when nothing was appended. ↑ on the first candidate wraps to the last of these.
    public var engineCount: Int? = nil

    public init(preceding: String, trailing: String, words: [String], selected: Int, exact: (index: Int, text: String)? = nil,
                exactIndex: Int? = nil, autocorrected: Int? = nil, engineCount: Int? = nil) {
        self.preceding = preceding
        self.trailing = trailing
        self.words = words
        self.selected = selected
        self.exact = exact
        self.exactIndex = exactIndex
        self.autocorrected = autocorrected
        self.engineCount = engineCount
    }

    public var candidates: [String] {
        words.enumerated().map { i, w in i == exact?.index ? exact!.text : preceding + w + trailing }
    }

    public static func == (a: Suggestion, b: Suggestion) -> Bool {
        a.preceding == b.preceding && a.trailing == b.trailing && a.words == b.words && a.selected == b.selected
            && a.exact?.index == b.exact?.index && a.exact?.text == b.exact?.text
            && a.exactIndex == b.exactIndex && a.autocorrected == b.autocorrected && a.engineCount == b.engineCount
    }
}

/// Remembers which candidate the user picked for a typed word.
public final class SelectionStore {
    private var map: [String: String] = [:]
    /// Where the choices are saved; nil keeps them in memory only.
    public let file: UserDataFile<[String: String]>?

    public init(url: URL? = nil) {
        file = url.map { UserDataFile(url: $0, format: "bornolipi.selections") }
        map = file?.load() ?? [:]
    }

    public subscript(key: String) -> String? { map[key] }

    /// Every remembered choice: typed roman word -> chosen Bangla word.
    public var all: [String: String] { map }

    public func record(_ key: String, _ value: String) {
        map[key] = value
        save()
    }

    public func remove(_ key: String) {
        guard map.removeValue(forKey: key) != nil else { return }
        save()
    }

    /// Replaces everything, e.g. when importing a backup.
    public func replaceAll(_ entries: [String: String]) {
        map = entries
        save()
    }

    public func removeAll() {
        map = [:]
        file?.remove()
    }

    private func save() { file?.save(map) }
}

public final class Suggester {
    public let parser: AvroParser
    public let index = WordIndex()
    public let selections: SelectionStore
    public var settings: EngineSettings {
        didSet {
            if settings.loanwordSuggestions && !oldValue.loanwordSuggestions { requestLoanwords() }
            if !settings.loanwordSuggestions && oldValue.loanwordSuggestions { releaseLoanwords() }
        }
    }
    /// The user's own words (personal dictionary), searched before the main dictionary.
    public private(set) var userWords: [String] = []
    private var userIndex = WordIndex()

    private var autocorrect: [String: String] = [:]
    private var suffixes: [String: String] = [:]
    /// Longest roman suffix; only that many final letters can start a suffix (keeps long words linear).
    private var longestSuffix = 0
    /// Conventional spellings (Data/conventional.json), keyed by the lowercased roman word.
    private var conventional: [String: [(bangla: String, upperOnly: Bool)]] = [:]
    /// Conventional and proper-noun spellings by loose key (consonant classes), for informal input.
    private var conventionalByLooseKey: [UInt64: [String]] = [:]
    private let lock = NSLock()
    private var ready = false
    private let dataDirectory: URL
    private let loading: DictionaryLoading
    /// The experimental loanword retriever (`EngineSettings.loanwordSuggestions`), built once the
    /// dictionary it shares has loaded and the setting is on. Guarded by `lock`, like the next two.
    private var loanwords: LoanwordRetriever?
    private var loanwordsWanted = false, loanwordsStarted = false
    private var loanwordFailure: Error?
    /// Counts the times the setting was turned off, so a build that started before is discarded.
    private var loanwordGeneration = 0
    /// Words never appended after the engine's list (Data/suggestion-blocklist.txt).
    private let blocklist: SuggestionBlocklist

    enum DictionaryLoading { case background, immediate, manual }
    /// Called on the main queue once the dictionary is searchable, so a word typed while it was
    /// loading can get its dictionary candidates. Set it right after `init`, on the main queue.
    public var onDictionaryReady: (() -> Void)?
    /// For tests (`.manual`): loads the dictionary when called.
    private(set) var loadDictionary: (() -> Void)?

    /// - Parameter dataDirectory: folder holding AvroPhonetic, dictionary, autocorrect and suffix JSON.
    /// - Parameter loadDictionaryInBackground: when false the dictionary loads before `init` returns.
    public convenience init(dataDirectory: URL, settings: EngineSettings = EngineSettings(),
                            selections: SelectionStore = SelectionStore(), loadDictionaryInBackground: Bool = true) throws {
        try self.init(dataDirectory: dataDirectory, settings: settings, selections: selections,
                      loading: loadDictionaryInBackground ? .background : .immediate)
    }

    init(dataDirectory: URL, settings: EngineSettings, selections: SelectionStore, loading: DictionaryLoading) throws {
        parser = try AvroParser(grammarURL: dataDirectory.appendingPathComponent("AvroPhonetic.json"))
        self.settings = settings
        self.selections = selections
        self.dataDirectory = dataDirectory
        self.loading = loading
        loanwordsWanted = settings.loanwordSuggestions
        autocorrect = Suggester.readMap(dataDirectory.appendingPathComponent("autocorrect.json"))
        suffixes = Suggester.readMap(dataDirectory.appendingPathComponent("suffix.json"))
        longestSuffix = suffixes.keys.map(\.count).max() ?? 0
        blocklist = SuggestionBlocklist(url: dataDirectory.appendingPathComponent("suggestion-blocklist.txt"))
        conventional = Suggester.readConventional(dataDirectory.appendingPathComponent("conventional.json"))
        // Proper nouns (places, institutions, names) share the format; curated entries come first.
        for (key, values) in Suggester.readConventional(dataDirectory.appendingPathComponent("propernouns.json"), format: "bornolipi.propernouns") {
            conventional[key, default: []].append(contentsOf: values)
        }
        for value in Set(conventional.values.flatMap { $0.filter { !$0.upperOnly }.map(\.bangla) }).sorted() {
            if let k = WordIndex.looseKey(WordIndex.looseLetters(value)) { conventionalByLooseKey[k, default: []].append(value) }
        }
        let dict = dataDirectory.appendingPathComponent("dictionary.json")
        let work = { [weak self] in
            guard let self else { return }
            try? self.index.load(dict)
            self.lock.lock()
            self.ready = true
            let loanwords = self.loanwordsWanted && !self.loanwordsStarted
            if loanwords { self.loanwordsStarted = true }
            let generation = self.loanwordGeneration
            self.lock.unlock()
            if loanwords { self.buildLoanwords(generation: generation) }
        }
        switch loading {
        case .background:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                work()
                DispatchQueue.main.async { self?.onDictionaryReady?() }
            }
        case .immediate: work()
        case .manual: loadDictionary = { [weak self] in work(); self?.onDictionaryReady?() }
        }
    }

    /// Sets the personal dictionary. Words are stored as typed (Bangla script).
    public func setUserWords(_ words: [String]) {
        var seen = Set<String>()
        userWords = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        let index = WordIndex()
        index.build(userWords)
        userIndex = index
    }

    public var isDictionaryReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready
    }

    /// The loanword retriever once it is built (only with `loanwordSuggestions` on).
    public var loanwordRetriever: LoanwordRetriever? {
        lock.lock(); defer { lock.unlock() }
        return loanwords
    }

    /// Why the loanword retriever could not be built, if it could not (its data is missing or stale).
    public var loanwordError: Error? {
        lock.lock(); defer { lock.unlock() }
        return loanwordFailure
    }

    /// The setting was turned on: build the retriever now if the dictionary is loaded (otherwise the
    /// dictionary loader builds it when it finishes).
    private func requestLoanwords() {
        lock.lock()
        loanwordsWanted = true
        let start = ready && !loanwordsStarted
        if start { loanwordsStarted = true }
        let generation = loanwordGeneration
        lock.unlock()
        if start { buildLoanwords(generation: generation) }
    }

    /// The setting was turned off: free the retriever's memory and let turning it on again rebuild it.
    /// A build still running is discarded when it finishes (its generation is out of date).
    private func releaseLoanwords() {
        lock.lock()
        loanwordsWanted = false
        loanwordsStarted = false
        loanwords = nil
        loanwordFailure = nil
        loanwordGeneration += 1
        lock.unlock()
    }

    /// Taken when a build starts and given back to `finishLoanwords` (internal for tests).
    var currentLoanwordGeneration: Int {
        lock.lock(); defer { lock.unlock() }
        return loanwordGeneration
    }

    /// Keeps a finished build, unless the setting was turned off after it started. Returns whether it was kept.
    @discardableResult
    func finishLoanwords(_ retriever: LoanwordRetriever?, failure: Error?, generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard loanwordsWanted, generation == loanwordGeneration else { return false }
        loanwords = retriever
        loanwordFailure = failure
        return true
    }

    /// Builds the retriever (about a tenth of a second): in the background for the keyboard, then
    /// `onDictionaryReady` again so a word being typed gets its candidates; at once for tools and tests.
    /// `generation` is taken under the lock that marked the build as started.
    private func buildLoanwords(generation: Int) {
        let build = { [weak self] () -> Bool in
            guard let self else { return false }
            var retriever: LoanwordRetriever?
            var failure: Error?
            do { retriever = try LoanwordRetriever(dataDirectory: self.dataDirectory, dictionary: self.index) } catch { failure = error }
            return self.finishLoanwords(retriever, failure: failure, generation: generation)
        }
        switch loading {
        case .background:
            DispatchQueue.global(qos: .utility).async { [weak self] in
                // A discarded build (the setting went off meanwhile) has nothing new to show.
                if build() { DispatchQueue.main.async { self?.onDictionaryReady?() } }
            }
        case .immediate, .manual: _ = build()
        }
    }

    private struct ConventionalFile: Decodable {
        struct Entry: Decodable { let roman: [String]; let bangla: [String]; let `case`: String? }
        let format: String
        let entries: [Entry]
    }

    static func readConventional(_ url: URL, format: String = "bornolipi.conventional") -> [String: [(bangla: String, upperOnly: Bool)]] {
        guard let d = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(ConventionalFile.self, from: d),
              file.format == format else { return [:] }
        var out: [String: [(bangla: String, upperOnly: Bool)]] = [:]
        for e in file.entries {
            for r in e.roman { for b in e.bangla { out[r.lowercased(), default: []].append((b, e.case == "upper")) } }
        }
        return out
    }

    static func readMap(_ url: URL) -> [String: String] {
        guard let d = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }

    // MARK: Suggestions

    public func suggest(_ buffer: String) -> Suggestion {
        let sp = SplitWord(buffer)
        let pre = parser.convert(sp.preceding)
        // Without surrounding punctuation the whole input is just the word, converted below.
        let hasPunctuation = !sp.preceding.isEmpty || !sp.trailing.isEmpty
        let whole = hasPunctuation ? normalize(fixDigits(parser.convert(buffer))) : ""
        guard !sp.word.isEmpty else {
            let joined = fixDigits(pre)
            return Suggestion(preceding: joined, trailing: "", words: [""], selected: 0, exact: joined == whole ? nil : (0, whole))
        }
        let post = parser.convert(sp.trailing)
        let word = sp.word
        let phonetic = parser.convert(word)
        let limit = settings.maxCandidates

        var list: [String] = []
        func add(_ s: String) {
            let t = normalize(fixDigits(s))
            if !t.isEmpty && !list.contains(t) { list.append(t) }
        }

        if let learned = selections[word] { add(learned) }
        let fix = settings.autocorrect ? settings.userAutocorrect[word] ?? autocorrect[word] : nil
        var correction: String?
        if let fix {
            let converted = normalize(fixDigits(parser.convert(fix)))
            if !list.contains(converted) { correction = converted }
            add(converted)
        }
        let alternatives = variants(of: word, phonetic)
        if settings.suggestions {
            for m in userIndex.matches(for: phonetic, variants: alternatives, preferVariants: true, limit: max(limit - 1, 1)) { add(m) }
        }
        let useDict = settings.suggestions && isDictionaryReady
        if useDict {
            for m in index.matches(for: phonetic, variants: alternatives, preferVariants: true, limit: max(limit - 1, 1)) { add(m) }
            for m in suffixed(word) { add(m) }
        }
        // Suggestions offered right after the exact conversion: they never change what Space inserts,
        // so a few slots are kept for them instead of letting dictionary matches crowd them out.
        // A word nothing above recognised may be an informal spelling of a known one (sarkar for সরকার):
        // offer the words with the same consonants 0.1.0 offered (up to two) after the exact conversion
        // and after the dictionary word for a broken conjunct (nojr: নজ্র, then নজর), which is the closer
        // guess; words it could not reach go after every other candidate (`looseCandidates`).
        // Only when nothing else recognised the word, and only for informal lowercase typing (capitals
        // are Avro's deliberate precision: T for ট, S for ষ).
        let curated = settings.suggestions ? conventionalSpellings(word) + (fix == nil ? autocorrectedSuffixes(word) : []) : []
        let informal = word.count >= 4 && word.allSatisfy { $0.isASCII && $0.isLowercase }
        let unrecognised = list.isEmpty && curated.isEmpty && informal
        // Words the list shows anyway (informal rewrites, conjunct-free spellings) do not take a free loose slot.
        var informalWords: [String]?
        var shown: [String] = []
        if settings.suggestions && unrecognised && useDict {
            informalWords = informalSpellings(word)
            shown = informalWords! + Suggester.withoutConjuncts(phonetic).flatMap { index.matches(for: $0, limit: 2) }
        }
        let loose = settings.suggestions && unrecognised ? looseCandidates(phonetic, dictionary: useDict, shown: shown) : (kept: [], added: [])
        let extras = curated
        let reserved = min((extras + loose.kept).filter { e in !list.contains(normalize(fixDigits(e))) }.count, 3)
        if list.count >= limit - reserved { list = Array(list.prefix(max(limit - 1 - reserved, list.isEmpty ? 0 : 1))) }
        add(phonetic)
        for e in extras where list.count < limit { add(e) }
        // After the exact conversion, so Space still commits what Avro would type; ↓ reaches the word.
        if useDict {
            for v in Suggester.withoutConjuncts(phonetic) where list.count < limit {
                for m in index.matches(for: v, limit: 2) { add(m) }
            }
        }
        for e in loose.kept where list.count < limit { add(e) }
        if settings.suggestions && settings.completions {
            for m in userIndex.completions(for: phonetic, limit: 2) { add(m) }
            if useDict { for m in index.completions(for: phonetic, limit: 3) { add(m) } }
        }
        // Informal habits Avro reads differently (bari: বারি, but বাড়ি is meant) go right after the
        // exact conversion, ahead of other dictionary matches, which mostly differ only in vowels.
        if useDict && informal, let at = list.firstIndex(of: normalize(fixDigits(phonetic))) {
            let spellings = (informalWords ?? informalSpellings(word)).map { normalize(fixDigits($0)) }.filter { !list.contains($0) }
            list.insert(contentsOf: spellings.prefix(2), at: at + 1)
        }
        if settings.includeEnglish {
            add(word)
            // The informal insert above may have filled the list; keep the typed word visible. A word
            // already first (a learned choice) stays first: that is what Space inserts.
            if list.count > limit, let i = list.lastIndex(of: word), i >= limit { list.remove(at: i); list.insert(word, at: limit - 1) }
        }
        // A web address or e-mail address is offered as typed. Avro converts it like any other text,
        // and Space still does; this only adds the original after the Bangla candidates.
        if Suggester.looksLikeAddress(buffer), !list.contains(buffer) {
            // Make room without dropping the first candidate (what Space inserts) or the exact conversion.
            let exactWord = normalize(fixDigits(phonetic))
            if list.count >= limit, let i = list.indices.last(where: { $0 > 0 && list[$0] != exactWord }) { list.remove(at: i) }
            if list.count < limit { list.append(buffer) }
        }
        // Loose words 0.1.0 did not offer go after every other candidate, the typed English word
        // included: nothing it offered moves. The candidates before them are the engine's list as 0.1.0
        // showed it; ↑ on the first candidate wraps to the last of those (`Suggestion.engineCount`).
        let engineCount = min(list.count, limit)
        // Appended words skip the blocklist's obscenities; the engine's own candidates are never filtered.
        for e in loose.added where list.count < limit && !blocklist.blocks(e) { add(e) }
        if list.count > limit { list = Array(list.prefix(limit)) }
        // The exact candidate must read as Avro writes the whole input, punctuation included.
        let exactWord = normalize(fixDigits(phonetic))
        // An empty conversion (a lone `) only takes a place when there is nothing else to show.
        if list.isEmpty { list.append(exactWord) }
        // Experimental, off by default: up to three known words the loanword retriever finds for lowercase
        // input of 2-40 letters (term: টার্ম). They only take free places after the engine's last candidate,
        // so every candidate the engine offers keeps its place, and Space is unchanged.
        if useDict, settings.loanwordSuggestions, list.count < limit, (2...Suggester.loanwordMaxLetters).contains(word.utf8.count),
           word.utf8.allSatisfy({ $0 >= 0x61 && $0 <= 0x7A }), let retriever = loanwordRetriever {
            let room = min(limit, list.count + 3)
            for c in retriever.generate(word) where list.count < room {
                let t = normalize(fixDigits(c.word))
                // A word the engine's own truncation cut (its autocorrection or the exact conversion) is not
                // brought back here, where it would be marked as the correction or the exact word.
                if t == exactWord || t == correction { continue }
                if SuggestionBlocklist.isJunk(t, inDictionary: c.inDictionary) || blocklist.blocks(t) { continue }
                if !list.contains(t) { list.append(t) }
            }
        }
        let wrapped = fixDigits(pre) + exactWord + fixDigits(post)
        let exact = hasPunctuation ? list.firstIndex(of: exactWord).flatMap { wrapped == whole ? nil : (index: $0, text: whole) } : nil
        let exactIndex = list.firstIndex(of: exactWord)
        let correctionIndex = correction.flatMap { c in c == exactWord ? nil : list.firstIndex(of: c) }
        let appendedFrom = list.count > engineCount && engineCount > 0 ? engineCount : nil
        return Suggestion(preceding: fixDigits(pre), trailing: fixDigits(post), words: list, selected: 0, exact: exact,
                          exactIndex: exactIndex, autocorrected: correctionIndex, engineCount: appendedFrom)
    }

    /// Longer words are not given to the loanword retriever: its reading costs more than linear time in
    /// the length (735 µs at 1,000 letters), and no lexicon word needs half as many letters.
    static let loanwordMaxLetters = 40

    /// Conventional spellings for what was typed: curated entries (acronyms, places, informal
    /// spellings), then, for a word typed in capitals, the acronym spelled with Bangla letter names.
    func conventionalSpellings(_ word: String) -> [String] {
        let upper = word.count >= 2 && word.allSatisfy { $0.isASCII && $0.isUppercase }
        var out: [String] = []
        for e in conventional[word.lowercased()] ?? [] where (!e.upperOnly || upper) && !out.contains(e.bangla) { out.append(e.bangla) }
        if upper, word.count <= 6 { out.append(word.compactMap { Suggester.letterNames[$0] }.joined()) }
        return out
    }

    /// www.example.com, http://..., a@b.co: text that is almost never meant as Bangla.
    static func looksLikeAddress(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.hasPrefix("www.") || lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.contains("://") { return s.count > 4 }
        if let at = s.firstIndex(of: "@"), at != s.startIndex, let dot = s[at...].lastIndex(of: "."), s.index(after: dot) < s.endIndex,
           s.index(after: at) < dot, !s.contains(" ") { return true }
        return false
    }

    /// Informal romanisation that Avro reads differently, with what Avro expects instead: r for ড়
    /// after a vowel (bari: বাড়ি), t and d for ট and ড (taka: টাকা), chh and ch for ছ and চ, j for
    /// য, gy for জ্ঞ, kkh for ক্ষ, st for ষ্ট, and ri for ৃ after a consonant (bristi: বৃষ্টি).
    static let informalRewrites: [(from: [Character], to: String)] = [
        ("chh", "ch"), ("ch", "c"), ("gy", "gg"), ("kkh", "kSh"), ("st", "ShT"), ("ri", "rri"),
        ("r", "R"), ("t", "T"), ("d", "D"), ("j", "z"),
    ].map { (Array($0.0), $0.1) }

    /// Dictionary words for the input with one or two `informalRewrites` applied, fewest rewrites
    /// first, at most two. Only exact (skeleton) dictionary matches count, so a rewrite that makes
    /// no known word adds nothing.
    func informalSpellings(_ word: String) -> [String] {
        let w = Array(word)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        var sites: [(at: Int, length: Int, to: String)] = []
        for i in w.indices {
            for r in Suggester.informalRewrites where i + r.from.count <= w.count && Array(w[i..<i + r.from.count]) == r.from {
                if r.from == ["r"] && (i == 0 || !vowels.contains(w[i - 1])) { continue }    // ড় follows a vowel
                if r.from == ["r", "i"] && (i == 0 || vowels.contains(w[i - 1])) { continue } // ৃ follows a consonant
                sites.append((i, r.from.count, r.to))
            }
        }
        guard !sites.isEmpty, sites.count <= 8 else { return [] }   // bounds the work on long words
        var choices = sites.indices.map { [$0] }
        for a in sites.indices {
            for b in sites.indices where sites[a].at + sites[a].length <= sites[b].at { choices.append([a, b]) }
        }
        var out: [String] = []
        for chosen in choices {
            var v = w
            for k in chosen.reversed() { v.replaceSubrange(sites[k].at..<sites[k].at + sites[k].length, with: Array(sites[k].to)) }
            for m in index.matches(for: parser.convert(String(v)), limit: 1) where !out.contains(m) { out.append(m) }
            if out.count >= 2 { break }
        }
        return out
    }

    /// Known words with the same consonant classes as the conversion, for words the exact lookup did
    /// not recognise: the ones 0.1.0 offered, then the others (`looseCandidates`).
    func looseSpellings(_ phonetic: String, dictionary: Bool) -> [String] {
        let loose = looseCandidates(phonetic, dictionary: dictionary, shown: [])
        return loose.kept + loose.added
    }

    /// `kept`: the loose words 0.1.0 offered, chosen exactly as it chose them (`looseWords010`), so
    /// nothing it offered moves. `added`: the other words `looseWords` chooses, for the slots left free
    /// after every other candidate.
    func looseCandidates(_ phonetic: String, dictionary: Bool, shown: [String]) -> (kept: [String], added: [String]) {
        let typed = WordIndex.looseLetters(phonetic)
        guard let key = WordIndex.looseKey(typed) else { return ([], []) }
        let names = conventionalByLooseKey[key] ?? []
        let hits = dictionary && names.count < 2 ? index.looseHits(for: phonetic, distinct: false) : []
        let kept = looseWords010(typed, names: names, hits: hits)
        let added = looseWords(typed, names: names, hits: hits, shown: shown).filter { w in !kept.contains { $0.letters == w.letters } }
        return (kept.map(\.word), added.map(\.word))
    }

    /// The loose words 0.1.0 offered: the two proper nouns closest by edit distance; then, while fewer
    /// than two, the first of the two dictionary words its index reached closest (`LooseHit.compatible`)
    /// that passes `looseWords`' closeness limit, and the second if as close. It compared code points as
    /// stored (`LooseHit.asStored`): every curated spelling with ড় ঢ় য় (187) and 84 dictionary words write
    /// them as letter + nukta, and 54 dictionary words write ো ৌ as two signs, which made those words look
    /// further away than they are.
    func looseWords010(_ typed: [UInt32], names: [String], hits: [WordIndex.LooseHit]) -> [(word: String, letters: [UInt32])] {
        let named = names.map { (word: $0, distance: WordIndex.distance($0.unicodeScalars.map(\.value), typed)) }
        var out = named.sorted { $0.distance < $1.distance }.prefix(2).map { (word: $0.word, letters: WordIndex.looseLetters($0.word)) }
        // Its two closest of the words its index reached. `hits` is in Avro-form order, which is 0.1.0's
        // unless a word is stored otherwise.
        var window: [WordIndex.LooseHit] = []
        if hits.contains(where: { $0.compatible && $0.stored != nil }) {
            func order(_ h: WordIndex.LooseHit) -> (Int, Int, Int32) { (h.stored?.loose ?? h.loose, h.stored?.exact ?? h.exact, h.id) }
            for h in hits where h.compatible {
                if window.count < 2 { window.append(h) } else if order(h) < order(window[1]) { window[1] = h } else { continue }
                if window.count == 2 && order(window[1]) < order(window[0]) { window.swapAt(0, 1) }
            }
        } else {
            for h in hits where h.compatible { window.append(h); if window.count == 2 { break } }
        }
        var first: Int?
        for h in window where out.count < 2 {
            let word = index.word(of: h), s = h.asStored
            guard !out.contains(where: { $0.word == word }), !s.letters.starts(with: typed), s.loose * 5 <= max(s.letters.count, typed.count),
                  s.loose <= first ?? s.loose else { continue }
            first = first ?? s.loose
            out.append((word, h.letters))
        }
        return out
    }

    /// The loose words for `typed`, each compared as Avro writes it (`WordIndex.looseLetters`): proper
    /// nouns, then the two closest dictionary words among those 0.1.0's index reached
    /// (`LooseHit.compatible`), then, for the slots that leaves free, the closest of the next four words
    /// (mostly ড় ঢ় য় words 0.1.0 could not reach), skipping words in `shown` (offered by another step).
    /// Dictionary words are a weaker signal than names (about a quarter of them were what the typist
    /// meant in the development set, against nearly all names), so every one must also be close: apart
    /// from same-class letters, at most one edit in five letters; any after the first only as close as
    /// the first; and never a longer form of the conversion itself (খারাপ → খারাপি is a completion).
    func looseWords(_ typed: [UInt32], names: [String], hits: [WordIndex.LooseHit], shown: [String]) -> [(word: String, letters: [UInt32])] {
        let named = names.map { name -> (word: String, letters: [UInt32], distance: Int) in
            let letters = WordIndex.looseLetters(name)
            return (name, letters, WordIndex.distance(letters, typed))
        }
        let closest = named.sorted { $0.distance < $1.distance }.prefix(2)
        var words = closest.map(\.word)
        var chosen = closest.map(\.letters)
        guard words.count < 2 else { return zip(words, chosen).map { (word: $0, letters: $1) } }
        var first: Int?
        func admits(_ h: WordIndex.LooseHit) -> Bool {
            !chosen.contains(h.letters) && !h.letters.starts(with: typed) && h.loose * 5 <= max(h.letters.count, typed.count)
                && h.loose <= first ?? h.loose
        }
        var seen = Set<[UInt32]>()
        var window = 0
        var rest: [WordIndex.LooseHit] = []
        for h in hits where seen.insert(h.letters).inserted {   // a word stored in two encodings comes once
            guard h.compatible && window < 2 else { rest.append(h); continue }
            window += 1
            if words.count < 2 && admits(h) {
                first = first ?? h.loose
                words.append(index.word(of: h))
                chosen.append(h.letters)
            }
        }
        let shownLetters = Set(shown.map(WordIndex.looseLetters))
        for h in rest.prefix(4) where words.count < 2 {
            guard !shownLetters.contains(h.letters), admits(h) else { continue }
            first = first ?? h.loose
            words.append(index.word(of: h))
            chosen.append(h.letters)
        }
        return zip(words, chosen).map { (word: $0, letters: $1) }
    }

    /// How English letter names are written in Bangla, as in বিএনপি or আইসিটি.
    static let letterNames: [Character: String] = [
        "A": "এ", "B": "বি", "C": "সি", "D": "ডি", "E": "ই", "F": "এফ", "G": "জি", "H": "এইচ", "I": "আই",
        "J": "জে", "K": "কে", "L": "এল", "M": "এম", "N": "এন", "O": "ও", "P": "পি", "Q": "কিউ", "R": "আর",
        "S": "এস", "T": "টি", "U": "ইউ", "V": "ভি", "W": "ডব্লিউ", "X": "এক্স", "Y": "ওয়াই", "Z": "জেড",
    ]

    /// Suffixed forms of an autocorrected English stem: computerer -> কম্পিউটার + ের.
    private func autocorrectedSuffixes(_ word: String) -> [String] {
        let chars = Array(word)
        guard chars.count > 3 else { return [] }
        var out: [String] = []
        for i in max(3, chars.count - longestSuffix)..<chars.count {
            let stem = String(chars[..<i])
            guard let suffix = suffixes[String(chars[i...])],
                  let fix = settings.userAutocorrect[stem] ?? autocorrect[stem] else { continue }
            out.append(Suggester.join(parser.convert(fix), suffix))
        }
        return out
    }

    /// Joins a Bangla stem and suffix the way the rule table does (য় after a vowel, ৎ and ং reshaped).
    static func join(_ base: String, _ suffix: String) -> String {
        guard let last = base.unicodeScalars.last, let first = suffix.unicodeScalars.first else { return base + suffix }
        var joined = base
        if isVowelSign(last) && isKar(first) {
            joined += "\u{09DF}"   // য়, one code point as in the rule table
        } else if last == "ৎ" {
            joined.unicodeScalars.removeLast(); joined += "ত"
        } else if last == "ং" {
            joined.unicodeScalars.removeLast(); joined += "ঙ"
        }
        return joined + suffix
    }

    /// A trailing `o` is usually meant as ো (bhalo = ভালো), so also rank against that spelling.
    /// When the word ends in `o` that spelling is preferred over the bare consonant.
    private func variants(of word: String, _ phonetic: String) -> [String] {
        guard word.hasSuffix("o") else { return [] }
        let alt = parser.convert(String(word.dropLast()) + "O")
        return [alt]
    }

    /// The spelling with one conjunct (or all of them) broken up: "abdar" converts to আব্দার, but
    /// আবদার is usually meant (Avro users type ab`dar for it). Avro's own dictionary search treats a
    /// hasanta between consonants as optional too. Only dictionary words are looked up this way.
    static func withoutConjuncts(_ phonetic: String) -> [String] {
        let u = Array(phonetic.unicodeScalars)
        func consonant(_ i: Int) -> Bool {
            (0x0995...0x09B9).contains(u[i].value) || [0x09DC, 0x09DD, 0x09DF].contains(u[i].value)
        }
        let hasantas = u.indices.filter { $0 > 0 && $0 + 1 < u.count && u[$0].value == 0x09CD && consonant($0 - 1) && consonant($0 + 1) }
        guard !hasantas.isEmpty, hasantas.count <= 4 else { return [] }
        func without(_ drop: [Int]) -> String {
            var v = String.UnicodeScalarView()
            for (i, x) in u.enumerated() where !drop.contains(i) { v.append(x) }
            return String(v)
        }
        var out = hasantas.map { without([$0]) }
        if hasantas.count > 1 { out.append(without(hasantas)) }
        return out
    }

    /// Dictionary stem + suffix, e.g. "bondhuder" -> বন্ধুদের.
    private func suffixed(_ word: String) -> [String] {
        let chars = Array(word)
        guard chars.count > 2 else { return [] }
        var out: [String] = []
        for i in max(1, chars.count - longestSuffix)..<chars.count {
            let key = String(chars[i...])
            guard let suffix = suffixes[key] else { continue }
            let stem = String(chars[..<i])
            // A run of one repeated letter (a held or doubled key, as in rrri) is not a word stem.
            if stem.count > 1, Set(stem.lowercased()).count == 1 { continue }
            let basePhonetic = parser.convert(stem)
            for base in index.matches(for: basePhonetic, variants: variants(of: stem, basePhonetic), preferVariants: true, limit: 2) {
                out.append(Suggester.join(base, suffix))
            }
        }
        return out
    }

    static func isKar(_ u: Unicode.Scalar) -> Bool { (0x09BE...0x09CC).contains(u.value) || u.value == 0x09D7 }
    static func isVowelSign(_ u: Unicode.Scalar) -> Bool { (0x0985...0x0994).contains(u.value) || isKar(u) }

    private func normalize(_ s: String) -> String {
        switch settings.normalization {
        // Compose first (some dictionary words spell ো ৌ as two code points), then use Avro's
        // single code points for ড় ঢ় য়, which NFC splits.
        case .avro: return Suggester.avroForm(Suggester.composeVowelSigns(s))
        case .nfc: return s.precomposedStringWithCanonicalMapping
        }
    }

    /// ে + া and ে + ৗ as the single signs ো and ৌ: the only compositions NFC makes in Bangla
    /// besides the nukta letters, without NFC's cost on every candidate.
    static func composeVowelSigns(_ s: String) -> String {
        let u = Array(s.unicodeScalars)
        guard u.indices.dropLast().contains(where: { u[$0].value == 0x09C7 && (u[$0 + 1].value == 0x09BE || u[$0 + 1].value == 0x09D7) }) else { return s }
        var out = String.UnicodeScalarView()
        var i = 0
        while i < u.count {
            if i + 1 < u.count, u[i].value == 0x09C7, u[i + 1].value == 0x09BE { out.append("\u{09CB}"); i += 2 }
            else if i + 1 < u.count, u[i].value == 0x09C7, u[i + 1].value == 0x09D7 { out.append("\u{09CC}"); i += 2 }
            else { out.append(u[i]); i += 1 }
        }
        return String(out)
    }

    private static let precomposedNukta: [UInt32: Unicode.Scalar] = [0x09A1: "\u{09DC}", 0x09A2: "\u{09DD}", 0x09AF: "\u{09DF}"]

    /// Avro writes ড় ঢ় য় as single code points; a few dictionary words spell them as letter + nukta.
    static func avroForm(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0.value == 0x09BC }) else { return s }
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if i + 1 < scalars.count, scalars[i + 1].value == 0x09BC, let p = precomposedNukta[scalars[i].value] {
                out.append(p)
                i += 2
            } else {
                out.append(scalars[i])
                i += 1
            }
        }
        return String(out)
    }

    private func fixDigits(_ s: String) -> String {
        guard !settings.banglaDigits else { return s }
        let map: [Character: Character] = ["০": "0", "১": "1", "২": "2", "৩": "3", "৪": "4",
                                           "৫": "5", "৬": "6", "৭": "7", "৮": "8", "৯": "9"]
        return String(s.map { map[$0] ?? $0 })
    }

    /// Remember that the user chose `word` for the typed `buffer`.
    public func learn(buffer: String, chosenWord: String) {
        let w = SplitWord(buffer).word
        guard !w.isEmpty, !chosenWord.isEmpty else { return }
        selections.record(w, chosenWord)
    }
}
