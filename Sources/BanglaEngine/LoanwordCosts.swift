import Foundation

// Part of the experimental loanword retriever (LoanwordRetriever.swift).

/// A learned cost table with a memo: rows are roman contexts (a marked vowel segment, or the roman
/// letters and class behind a consonant), columns the lexicon's Bangla vowel material or consonant
/// spellings. Cells are computed on first use exactly as the prototype's segmodel.py does; at most
/// `maxRows` rows are kept, the least recently used giving way.
final class LoanwordCostMemo {
    enum Kind { case segments, consonants }
    let kind: Kind
    private let counts: [String: [String: Int]]
    private let totals: [String: Int]
    private let vocabulary: [String]
    private let vocabularyBytes: [[UInt8]]
    let width: Int
    private(set) var table: UnsafeMutablePointer<Double>
    private var capacity: Int
    private var rowKeys: [[UInt8]] = []
    private var rowHashes: [UInt64] = []
    private var rowUsed: [UInt32] = []
    private var rowByHash: [UInt64: Int32] = [:]
    private var query: UInt32 = 0
    // Segment rows: the first back-off row with enough data (or none) and the bare roman letters.
    private var segmentCounts: [[String: Int]?] = []
    private var segmentTotals: [Int] = []
    private var segmentLetters: [[UInt8]] = []
    // Consonant rows: the class distribution and the label's own counts, if any.
    private var consonantClass: [(counts: [String: Int], total: Int)] = []
    private var consonantLabel: [(counts: [String: Int], total: Int)?] = []
    private var prev: [Double] = [], cur: [Double] = []
    static let maxRows = 256
    static let alpha = 2.0, lambda = 1.2   // segments
    static let consonantAlpha = 1.0, floor = 1e-3   // consonants

    /// Vowel-segment counts: P(Bangla material | marked roman segment), smoothed towards a letter-similarity base.
    init(segments rows: [String: [String: Int]], vocabulary: [String]) {
        kind = .segments
        var c: [String: [String: Int]] = [:], t: [String: Int] = [:]
        for (v, row) in rows {
            t[v] = row["_tot"] ?? 0
            c[v] = row.filter { $0.key != "_tot" }
        }
        counts = c
        totals = t
        self.vocabulary = vocabulary
        vocabularyBytes = vocabulary.map { Array($0.utf8) }
        width = max(vocabulary.count, 1)
        capacity = 32
        table = .allocate(capacity: capacity * width)
    }

    /// Consonant-letter counts: P(Bangla letters | roman letters and class), backed off to the class.
    init(consonants rows: [String: [String: Int]], vocabulary: [String]) {
        kind = .consonants
        counts = rows
        totals = rows.mapValues { $0.values.reduce(0, +) }
        self.vocabulary = vocabulary
        vocabularyBytes = []
        width = max(vocabulary.count, 1)
        capacity = 32
        table = .allocate(capacity: capacity * width)
    }

    deinit { table.deallocate() }

    var bytes: Int { capacity * width * 8 }

    func beginQuery() { query &+= 1 }

    /// The row for a roman context (its UTF-8), made on first use.
    func row(_ key: [UInt8]) -> Int32 {
        let h = LoanwordRetriever.fnv1a(key)
        if let r = rowByHash[h], rowKeys[Int(r)] == key {
            rowUsed[Int(r)] = query
            return r
        }
        if rowByHash[h] != nil, let r = rowKeys.firstIndex(of: key) {   // a hash collision
            rowUsed[r] = query
            return Int32(r)
        }
        var r = rowKeys.count
        if r >= LoanwordCostMemo.maxRows,
           let old = rowUsed.indices.filter({ rowUsed[$0] != query }).min(by: { rowUsed[$0] < rowUsed[$1] }) {
            r = old
            if rowByHash[rowHashes[r]] == Int32(r) { rowByHash[rowHashes[r]] = nil }
        } else {
            if r == capacity {
                let bigger = UnsafeMutablePointer<Double>.allocate(capacity: capacity * 2 * width)
                bigger.initialize(from: table, count: capacity * width)
                table.deallocate()
                table = bigger
                capacity *= 2
            }
            rowKeys.append([]); rowHashes.append(0); rowUsed.append(0)
            switch kind {
            case .segments: segmentCounts.append(nil); segmentTotals.append(0); segmentLetters.append([])
            case .consonants: consonantClass.append(([:], 0)); consonantLabel.append(nil)
            }
        }
        (table + r * width).initialize(repeating: .nan, count: width)
        rowKeys[r] = key; rowHashes[r] = h; rowUsed[r] = query
        if rowByHash[h] == nil { rowByHash[h] = Int32(r) }
        let context = String(decoding: key, as: UTF8.self)
        switch kind {
        case .segments:
            // The first back-off with enough data: the segment, without ^ ~, with position marks only, bare.
            let bare = LoanwordCostMemo.stripMarks(context).replacingOccurrences(of: "E", with: "e")
            var found: (counts: [String: Int], total: Int)?
            for b in LoanwordCostMemo.backoffs(context) {
                guard let cnt = counts[b] else { continue }
                let tot = totals[b] ?? 0
                if tot < 5 { continue }
                found = (cnt, tot)
                break
            }
            segmentCounts[r] = found?.counts
            segmentTotals[r] = found?.total ?? 0
            segmentLetters[r] = Array(bare.utf8)
        case .consonants:
            let cls = "*|" + (context.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? context)
            consonantClass[r] = (counts[cls] ?? [:], totals[cls] ?? 0)
            if let lc = counts[context], !lc.isEmpty { consonantLabel[r] = (lc, totals[context] ?? 0) } else { consonantLabel[r] = nil }
        }
        return Int32(r)
    }

    /// Computes and stores cell (row, column).
    @inline(never)
    func fill(_ r: Int, _ w: Int) -> Double {
        let c: Double
        switch kind {
        case .segments:
            let base = exp(-LoanwordCostMemo.lambda * letterDistance(segmentLetters[r], vocabularyBytes[w])) * 0.05
            if let cnt = segmentCounts[r] {
                let p = (Double(cnt[vocabulary[w]] ?? 0) + LoanwordCostMemo.alpha * base) / (Double(segmentTotals[r]) + LoanwordCostMemo.alpha)
                c = -log(p)
            } else {
                c = -log(base)
            }
        case .consonants:
            let letters = vocabulary[w]
            let (cc, ct) = consonantClass[r]
            let f = LoanwordCostMemo.floor
            let pb = ct != 0 ? (Double(cc[letters] ?? 0) + f) / (Double(ct) + f * 50) : f
            let p: Double
            if let (lc, lt) = consonantLabel[r] {
                p = (Double(lc[letters] ?? 0) + LoanwordCostMemo.consonantAlpha * pb) / (Double(lt) + LoanwordCostMemo.consonantAlpha)
            } else {
                p = pb
            }
            c = -log(max(p, 1e-6))
        }
        table[r * width + w] = c
        return c
    }

    static func stripMarks(_ v: String) -> String { String(v.filter { $0 != "#" && $0 != "$" && $0 != "^" && $0 != "~" }) }

    static func backoffs(_ v: String) -> [String] {
        var out = [v]
        let a = String(v.filter { $0 != "^" && $0 != "~" })
        if a != v { out.append(a) }
        let bare = stripMarks(v).replacingOccurrences(of: "E", with: "e")
        let pos = (v.hasPrefix("#") ? "#" : "") + bare + (v.hasSuffix("$") ? "$" : "")
        if pos != a && pos != v { out.append(pos) }
        out.append(bare)
        return out
    }

    /// Edit distance between roman vowel letters and Bangla vowel material (segmodel.letter_dist).
    func letterDistance(_ r: [UInt8], _ w: [UInt8]) -> Double {
        let n = r.count, m = w.count
        prev.removeAll(keepingCapacity: true); prev.append(contentsOf: repeatElement(0, count: m + 1))
        cur.removeAll(keepingCapacity: true); cur.append(contentsOf: repeatElement(0, count: m + 1))
        if m > 0 { for j in 1...m { prev[j] = prev[j - 1] + LoanwordCostMemo.insertion(w[j - 1]) } }
        if n > 0 {
            for i in 1...n {
                cur[0] = prev[0] + LoanwordCostMemo.deletion(r[i - 1])
                if m > 0 {
                    for j in 1...m {
                        cur[j] = min(prev[j] + LoanwordCostMemo.deletion(r[i - 1]), cur[j - 1] + LoanwordCostMemo.insertion(w[j - 1]),
                                     prev[j - 1] + LoanwordCostMemo.substitution(r[i - 1], w[j - 1]))
                    }
                }
                swap(&prev, &cur)
            }
        }
        return prev[m]
    }

    private static func insertion(_ b: UInt8) -> Double { b == 0x30 ? 0.3 : (b == 0x79 || b == 0x77) ? 0.4 : 1.0 }   // 0; y w
    private static func deletion(_ x: UInt8) -> Double { (x == 0x79 || x == 0x68 || x == 0x77) ? 0.4 : x == 0x65 ? 0.7 : 1.0 }   // y h w; e

    private static let similar: [String: Double] = [
        "yi": 0.2, "ao": 0.6, "oa": 0.6, "ae": 0.6, "ea": 0.6, "ei": 0.5, "ie": 0.5, "ou": 0.5, "uo": 0.5, "ua": 0.6,
        "o0": 0.2, "a0": 0.4, "u0": 0.7, "e0": 0.7, "wu": 0.3, "wo": 0.4, "yy": 0.0, "ww": 0.0, "ye": 0.6, "iy": 0.4,
    ]
    private static let similarTable: [Double] = {
        var t = [Double](repeating: 1.0, count: 128 * 128)
        for (k, v) in similar { let b = Array(k.utf8); t[Int(b[0]) * 128 + Int(b[1])] = v }
        return t
    }()
    private static func substitution(_ x: UInt8, _ b: UInt8) -> Double { x == b ? 0.0 : similarTable[Int(x & 0x7F) * 128 + Int(b & 0x7F)] }
}
