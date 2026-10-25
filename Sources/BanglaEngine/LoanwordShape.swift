import Foundation

// Part of the experimental loanword retriever (LoanwordRetriever.swift).

/// A Bangla word as consonant classes with the vowel material between them (the prototype's
/// bnshape.py). Classes are `WordIndex.looseClass` numbers, except that য় and the glides ্য and ্ব
/// are vowel material ('y', 'w'), ঋ and ৃ count as র followed by 'i', and য after a reph is a
/// consonant (সূর্য). Vowel material is written in a roman-like alphabet: 0 for the inherent vowel,
/// a i u e o, oi and ou for ৈ ৌ, y and w for glides.
enum BanglaShape {
    struct Builder {
        var classes: [UInt8] = []
        /// Vowel segments (one more than classes), each as 4-bit symbols (see `symbols`).
        var segments: [UInt64] = [0]
        /// Consonant letters at each class position, 8 bits per letter (code point - 0x0980 + 1).
        var letters: [UInt64] = []
        mutating func reset() {
            classes.removeAll(keepingCapacity: true)
            segments.removeAll(keepingCapacity: true)
            segments.append(0)
            letters.removeAll(keepingCapacity: true)
        }
        mutating func vowel(_ s: StaticString) {
            for k in 0..<s.utf8CodeUnitCount {
                segments[segments.count - 1] = segments[segments.count - 1] << 4 | UInt64(BanglaShape.symbol(s.utf8Start[k]))
            }
        }
        /// A cluster or doubled letter of one class (ট্ট, ক্খ) is one consonant.
        mutating func consonant(_ c: UInt8, _ u: UInt32) {
            let code = UInt64(u - 0x0980 + 1)
            if let l = classes.last, l == c, segments[segments.count - 1] == 0 {
                letters[letters.count - 1] = letters[letters.count - 1] << 8 | code
                return
            }
            classes.append(c)
            segments.append(0)
            letters.append(code)
        }
    }

    static let symbols: [UInt8] = Array("0aiueoywl".utf8)
    static func symbol(_ c: UInt8) -> UInt8 { UInt8(symbols.firstIndex(of: c)! + 1) }

    static func segmentString(_ code: UInt64) -> String {
        var out: [UInt8] = []
        var c = code
        while c != 0 { out.append(symbols[Int(c & 0xF) - 1]); c >>= 4 }
        return String(decoding: out.reversed(), as: UTF8.self)
    }

    static func letterString(_ code: UInt64) -> String {
        var parts: [UInt32] = []
        var c = code
        while c != 0 { parts.append(UInt32(c & 0xFF) - 1 + 0x0980); c >>= 8 }
        var out = String.UnicodeScalarView()
        for u in parts.reversed() { out.append(Unicode.Scalar(u)!) }
        return String(out)
    }

    /// The class of a consonant spelling (its first letter; ঋ and ৃ are র's class).
    static func spellingClass(_ code: UInt64) -> UInt8 {
        var c = code
        while c > 0xFF { c >>= 8 }
        let u = UInt32(c) - 1 + 0x0980
        return u == 0x09C3 || u == 0x098B ? 13 : consonantClass(u)
    }

    /// The prototype's class table (bnshape._CLASS): no class for য়, which is a glide.
    private static let classTable: [UInt8] = (0x0980..<0x0A00).map { u -> UInt8 in
        switch u {
        case 0x0995, 0x0996: return 1
        case 0x0997, 0x0998: return 2
        case 0x0999, 0x0982: return 3
        case 0x099A, 0x099B: return 4
        case 0x099C, 0x099D, 0x09AF: return 5
        case 0x099E: return 6
        case 0x099F, 0x09A0, 0x09A4, 0x09A5, 0x09CE: return 7
        case 0x09A1, 0x09A2, 0x09A6, 0x09A7: return 8
        case 0x09A3, 0x09A8: return 9
        case 0x09AA, 0x09AB: return 10
        case 0x09AC, 0x09AD: return 11
        case 0x09AE: return 12
        case 0x09B0, 0x09DC, 0x09DD: return 13
        case 0x09B2: return 14
        case 0x09B6, 0x09B7, 0x09B8: return 15
        case 0x09B9: return 16
        default: return 0
        }
    }

    static func consonantClass(_ u: UInt32) -> UInt8 { u >= 0x0980 && u < 0x0A00 ? classTable[Int(u - 0x0980)] : 0 }

    static func vowelSign(_ u: UInt32) -> StaticString? {
        switch u {
        case 0x09BE: return "a"
        case 0x09BF, 0x09C0, 0x09C4: return "i"
        case 0x09C1, 0x09C2, 0x09D7: return "u"
        case 0x09C7: return "e"
        case 0x09C8: return "oi"
        case 0x09CB: return "o"
        case 0x09CC: return "ou"
        default: return nil
        }
    }

    static func independentVowel(_ u: UInt32) -> StaticString? {
        switch u {
        case 0x0985: return "o"
        case 0x0986: return "a"
        case 0x0987, 0x0988: return "i"
        case 0x0989, 0x098A: return "u"
        case 0x098F: return "e"
        case 0x0990: return "oi"
        case 0x0993: return "o"
        case 0x0994: return "ou"
        case 0x098C: return "li"
        default: return nil
        }
    }

    /// The prototype keeps a word only when it starts with a consonant or an independent vowel.
    static func startsWord(_ u: UInt32) -> Bool { consonantClass(u) != 0 || independentVowel(u) != nil }

    private static func ignored(_ u: UInt32) -> Bool { u == 0x0981 || u == 0x0983 || u == 0x09BC || u == 0x200C || u == 0x200D }

    /// The prototype's normalisation: ড় ঢ় য় ো ৌ as single code points, then no ZWNJ or ZWJ.
    static func normalize(_ s: [UInt32], into out: inout [UInt32]) {
        out.removeAll(keepingCapacity: true)
        var i = 0
        while i < s.count {
            let u = s[i], v: UInt32 = i + 1 < s.count ? s[i + 1] : 0
            if v == 0x09BC, u == 0x09AF { out.append(0x09DF); i += 2; continue }
            if v == 0x09BC, u == 0x09A1 { out.append(0x09DC); i += 2; continue }
            if v == 0x09BC, u == 0x09A2 { out.append(0x09DD); i += 2; continue }
            if u == 0x09C7, v == 0x09BE { out.append(0x09CB); i += 2; continue }
            if u == 0x09C7, v == 0x09D7 { out.append(0x09CC); i += 2; continue }
            out.append(u)
            i += 1
        }
        out.removeAll { $0 == 0x200C || $0 == 0x200D }
    }

    static func normalized(_ s: String) -> String {
        var out: [UInt32] = []
        normalize(s.unicodeScalars.map(\.value), into: &out)
        var v = String.UnicodeScalarView()
        for u in out { v.append(Unicode.Scalar(u)!) }
        return String(v)
    }

    /// The shape of a normalised word; false when it has no Bangla letter.
    static func shape(_ w: [UInt32], into b: inout Builder) -> Bool {
        let n = w.count
        var i = 0, any = false
        let has: UInt32 = 0x09CD, ya: UInt32 = 0x09AF, ba: UInt32 = 0x09AC, yya: UInt32 = 0x09DF, ra: UInt32 = 0x09B0
        while i < n {
            let ch = w[i]
            if ignored(ch) { i += 1; continue }
            if ch == has {
                // Hasanta: a phala (glide) or a cluster; no inherent vowel either way.
                let nxt: UInt32 = i + 1 < n ? w[i + 1] : 0
                if nxt == ya {
                    // র + ্ + য is reph over য (সূর্য: a real /dʒ/) after a vowel or a consonant's inherent
                    // vowel; after a র-phala, a word-initial র or ZWJ it is ya-phala, a glide.
                    if i > 1, w[i - 1] == ra, w[i - 2] != has, w[i - 2] != 0x200D,
                       consonantClass(w[i - 2]) != 0 || vowelSign(w[i - 2]) != nil || independentVowel(w[i - 2]) != nil {
                        b.consonant(5, ya)
                        if !(i + 2 < n && (vowelSign(w[i + 2]) != nil || w[i + 2] == has)) { b.vowel("0") }
                        i += 2
                        continue
                    }
                    b.vowel("y")
                    i += 2
                    continue
                }
                // ব-phala is silent or a glide (বিশ্ব, স্বাধীন) except after ম, ল and reph (কম্বল, সর্বদা).
                if nxt == ba, !b.classes.isEmpty, i > 0, w[i - 1] != 0x09AE, w[i - 1] != 0x09B2, w[i - 1] != ra {
                    b.vowel("w")
                    i += 2
                    continue
                }
                i += 1
                continue
            }
            if ch == yya { b.vowel("y"); i += 1; any = true; continue }
            if ch == 0x09C3 || ch == 0x098B {   // ৃ ঋ
                b.consonant(13, ch)
                b.vowel("i")
                i += 1
                any = true
                continue
            }
            let c = consonantClass(ch)
            if c != 0 {
                any = true
                b.consonant(c, ch)
                if ch != 0x0982 && ch != 0x09CE {
                    // Inherent vowel unless a sign, hasanta or the end follows.
                    var j = i + 1
                    while j < n, ignored(w[j]) { j += 1 }
                    let nxt: UInt32 = j < n ? w[j] : 0
                    if vowelSign(nxt) == nil && nxt != has && nxt != 0x09C3 { b.vowel("0") }
                }
                i += 1
                continue
            }
            if let v = vowelSign(ch) ?? independentVowel(ch) { any = true; b.vowel(v) }
            i += 1
        }
        return any
    }

    /// The retrieval key: classes with consecutive repeats collapsed, at most 8, packed as the engine's
    /// loose key (5 bits per class, the count above bit 40); 0 for no class.
    static func packedKey<C: Collection>(_ cs: C) -> UInt64 where C.Element == UInt8 {
        var key: UInt64 = 0, n: UInt64 = 0, last: UInt8 = 0
        for c in cs where c != last {
            last = c
            key = key << 5 | UInt64(c)
            n += 1
            if n == 8 { break }
        }
        return n == 0 ? 0 : key | n << 40
    }
}
