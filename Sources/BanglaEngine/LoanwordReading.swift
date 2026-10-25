import Foundation

// Part of the experimental loanword retriever (LoanwordRetriever.swift).

/// The typed word read by context rules into a beam of templates (the prototype's rkeys.py): every
/// letter has one or more options (consonant classes, vowel or glide letters, or nothing), each with a
/// cost from the model; the beam keeps the cheapest readings.
enum RomanReading {
    /// One option: `length` letters read as up to two items, each a class 1...16 or an ASCII vowel or
    /// glide letter; `tag` indexes `tags` (-1: an option without a cost).
    struct Option {
        var length: Int
        var count: Int
        var a: UInt8
        var b: UInt8
        var tag: Int
    }

    /// Hand priors of the rule options (rkeys.PRIOR); the learned tables override every one of them.
    static let priorCosts: [String: Double] = [
        "ch:4": 0.1, "ch:1": 2.0, "ch:15": 2.5, "c+f:15": 0.1, "c+f:4": 2.0, "c+f:1": 3.0, "c:1": 0.1, "c:4": 2.0, "c:15": 3.0,
        "cc+f:1,15": 0.3, "cc+f:1": 1.0, "dg:5": 0.1, "dg:8,2": 2.5, "gh#:2": 0.0, "gh:0": 0.5, "gh:10": 1.5, "gh:2": 1.0,
        "gn$:9": 0.3, "gn$:2,9": 1.0, "gn:2,9": 0.2, "gn:9": 1.5, "gg+f:2": 0.5, "gg+f:2,5": 1.0, "gg+f:5": 1.5, "gg+f:5,6": 2.0,
        "gg:2": 0.1, "gg:5,6": 2.5, "gy:2": 0.3, "gy:5,6": 1.5, "g+f:5": 0.5, "g+f:2": 0.7, "h#:16": 0.05, "h#:0": 3.0,
        "h_v:0": 0.7, "h_v:16": 0.7, "h_c:0": 0.3, "h_c:16": 1.5, "kn#:9": 0.3, "kn#:1,9": 1.5, "kkh:1,15": 0.3, "kkh:1": 1.5,
        "kh:1": 0.3, "kh:1,15": 1.5, "l_sil:0": 0.7, "l_sil:14": 0.7, "mb$:12": 0.5, "mb$:12,11": 1.0, "mn$:12": 0.5, "mn$:12,9": 1.0,
        "ng$:3": 0.1, "ng$:3,2": 1.5, "ng$:9,2": 3.0, "ng+f:9,5": 1.0, "ng+f:6,5": 1.0, "ng+f:3,2": 1.0, "ng+f:3": 2.0,
        "ng+v:3,2": 0.5, "ng+v:3": 1.0, "ng+v:9,2": 1.5, "n+vel:3": 0.5, "n+vel:9": 0.9, "n+vel:0": 3.0, "n+pal:6": 1.0, "n+pal:9": 0.4,
        "ps#:15": 0.5, "ps#:10,15": 1.0, "que$:1": 0.2, "que$:1,v": 1.5, "sch:15,1": 0.5, "sch:15": 1.0, "sch:15,4": 1.5,
        "s_vv:15": 0.4, "s_vv:5": 1.0, "s+ion:15": 0.4, "s+ion:5": 1.0, "s$v:15": 0.3, "s$v:5": 1.2, "s_m$:5": 0.5, "s_m$:15": 0.9,
        "tion:15": 0.1, "tion:4": 2.0, "tion:7": 2.5, "ti+v:15": 0.7, "ti+v:7": 0.7, "tu:4": 0.7, "tu:7": 0.7, "t_sil:0": 0.7, "t_sil:7": 0.7,
        "th:7": 0.4, "th:8": 1.0, "w:w": 0.1, "w:11": 2.5, "wh:16": 0.1, "wh:w": 2.0, "x#:5": 0.7, "x#:1,15": 0.7, "x:1,15": 0.2, "x:2,5": 1.5,
        "y#:y": 0.3, "y#:5": 1.2, "z:5": 0.1, "z:15": 2.0, "cch:4": 0.1, "n+sh:9": 0.3, "n+sh:3": 1.5, "n+sh:0": 2.5, "n+c:9": 0.1, "n+c:0": 3.0,
        "y_vv:y": 0.3, "y_vv:5": 1.5, "rh:13": 0.3, "rh:13,16": 1.5, "s$v:0": 2.0, "s$u:15": 0.2, "s$u:0": 2.0,
    ]
    /// Every rule option with a cost; costs are kept per model in this order.
    static let tags: [String] = priorCosts.keys.sorted()
    private static let tagIndex: [String: Int] = Dictionary(uniqueKeysWithValues: tags.enumerated().map { ($1, $0) })

    private static func isVowel(_ c: UInt8) -> Bool { c == 0x61 || c == 0x65 || c == 0x69 || c == 0x6F || c == 0x75 }
    private static func isFront(_ c: UInt8) -> Bool { c == 0x65 || c == 0x69 || c == 0x79 }
    private static func isVoicedEnd(_ c: UInt8) -> Bool {
        isVowel(c) || c == 0x62 || c == 0x64 || c == 0x67 || c == 0x6C || c == 0x6D || c == 0x6E || c == 0x72 || c == 0x76 || c == 0x77 || c == 0x79
    }

    /// The options at every position of `s` (rkeys.Rules.options), into the workspace.
    // swiftlint:disable cyclomatic_complexity function_body_length
    static func options(_ s: [UInt8], into w: inout Workspace) {
        w.options.removeAll(keepingCapacity: true)
        w.optionStart.removeAll(keepingCapacity: true)
        let n = s.count
        for i in 0..<n {
            w.optionStart.append(w.options.count)
            let ch = s[i]
            let nx: UInt8 = i + 1 < n ? s[i + 1] : 0
            let nx2: UInt8 = i + 2 < n ? s[i + 2] : 0
            let pv: UInt8 = i > 0 ? s[i - 1] : 0
            // Items are never 0 (classes are 1...16, letters ASCII), so 0 means "no item".
            func o(_ l: Int, _ a: UInt8 = 0, _ b: UInt8 = 0, tag: String? = nil) {
                w.options.append(Option(length: l, count: a == 0 ? 0 : b == 0 ? 1 : 2, a: a, b: b, tag: tag.map { tagIndex[$0] ?? -1 } ?? -1))
            }
            func c(_ x: Unicode.Scalar) -> UInt8 { UInt8(x.value) }
            /// s[from..<to] (clipped to the word) equals `lit`.
            func slice(_ from: Int, _ to: Int, _ lit: StaticString) -> Bool {
                let end = min(to, n)
                guard from <= end else { return lit.utf8CodeUnitCount == 0 }
                guard end - from == lit.utf8CodeUnitCount else { return false }
                for k in 0..<(end - from) where s[from + k] != lit.utf8Start[k] { return false }
                return true
            }
            func rest(_ p: StaticString) -> Bool { i + p.utf8CodeUnitCount <= n && slice(i, i + p.utf8CodeUnitCount, p) }
            func tail(_ from: Int, _ lit: StaticString) -> Bool { slice(from, n, lit) }
            let w8 = c("w"), y = c("y")
            if isVowel(ch) {
                o(1, ch)
                continue
            }
            switch ch {
            case c("b"):
                if nx == c("b") || nx == c("h") { o(2, 11) } else { o(1, 11) }
            case c("c"):
                if rest("chh") {
                    o(3, 4)
                } else if nx == c("h") {
                    o(2, 4, tag: "ch:4"); o(2, 1, tag: "ch:1"); o(2, 15, tag: "ch:15")
                } else if nx == c("k") || nx == c("q") {
                    o(2, 1)
                } else if nx == c("c") && nx2 == c("h") {
                    o(slice(i + 3, i + 4, "h") ? 4 : 3, 4, tag: "cch:4")
                } else if nx == c("c") {
                    if isFront(nx2) { o(2, 1, 15, tag: "cc+f:1,15"); o(2, 1, tag: "cc+f:1") } else { o(2, 1) }
                } else if isFront(nx) {
                    o(1, 15, tag: "c+f:15"); o(1, 4, tag: "c+f:4"); o(1, 1, tag: "c+f:1")
                } else {
                    o(1, 1, tag: "c:1"); o(1, 4, tag: "c:4"); o(1, 15, tag: "c:15")
                }
            case c("d"):
                if nx == c("g") && isFront(nx2) {
                    o(2, 5, tag: "dg:5"); o(2, 8, 2, tag: "dg:8,2")
                } else if nx == c("d") || nx == c("h") {
                    o(2, 8)
                } else {
                    o(1, 8)
                }
            case c("f"):
                o(nx == c("f") ? 2 : 1, 10)
            case c("g"):
                if nx == c("h") {
                    if i == 0 { o(2, 2, tag: "gh#:2") } else { o(2, tag: "gh:0"); o(2, 10, tag: "gh:10"); o(2, 2, tag: "gh:2") }
                } else if nx == c("n") && (i + 2 >= n || !isVowel(s[i + 2])) {
                    o(2, 9, tag: "gn$:9"); o(2, 2, 9, tag: "gn$:2,9")
                } else if nx == c("n") {
                    o(2, 2, 9, tag: "gn:2,9"); o(2, 9, tag: "gn:9")
                } else if nx == c("g") {
                    if isFront(nx2) {
                        o(2, 2, tag: "gg+f:2"); o(2, 2, 5, tag: "gg+f:2,5"); o(2, 5, tag: "gg+f:5"); o(2, 5, 6, tag: "gg+f:5,6")
                    } else {
                        o(2, 2, tag: "gg:2"); o(2, 5, 6, tag: "gg:5,6")
                    }
                } else if nx == y && isVowel(nx2) {
                    o(1, 2, tag: "gy:2"); o(2, 5, 6, tag: "gy:5,6")
                } else if isFront(nx) {
                    o(1, 5, tag: "g+f:5"); o(1, 2, tag: "g+f:2")
                } else {
                    o(1, 2)
                }
            case c("h"):
                if i == 0 {
                    o(1, 16, tag: "h#:16"); o(1, tag: "h#:0")
                } else if isVowel(pv) && isVowel(nx) {
                    o(1, 16)
                } else if isVowel(pv) || pv == y || pv == w8 {
                    o(1, tag: "h_v:0"); o(1, 16, tag: "h_v:16")
                } else {
                    o(1, tag: "h_c:0"); o(1, 16, tag: "h_c:16")
                }
            case c("j"):
                o(nx == c("j") || nx == c("h") ? 2 : 1, 5)
            case c("k"):
                if i == 0 && nx == c("n") {
                    o(2, 9, tag: "kn#:9"); o(2, 1, 9, tag: "kn#:1,9")
                } else if rest("kkh") {
                    o(3, 1, 15, tag: "kkh:1,15"); o(3, 1, tag: "kkh:1")
                } else if rest("ksh") {
                    o(3, 1, 15)
                } else if nx == c("h") {
                    o(2, 1, tag: "kh:1"); o(2, 1, 15, tag: "kh:1,15")
                } else if nx == c("k") {
                    o(2, 1)
                } else {
                    o(1, 1)
                }
            case c("l"):
                if nx == c("l") {
                    o(2, 14)
                } else if ((pv == c("a") || pv == c("o")) && (nx == c("k") || nx == c("m"))) || (slice(max(0, i - 2), i, "ou") && nx == c("d")) {
                    o(1, tag: "l_sil:0"); o(1, 14, tag: "l_sil:14")
                } else {
                    o(1, 14)
                }
            case c("m"):
                if nx == c("m") {
                    o(2, 12)
                } else if nx == c("b") && (i + 2 == n || tail(i + 2, "e") || tail(i + 2, "s")) {
                    o(2, 12, tag: "mb$:12"); o(2, 12, 11, tag: "mb$:12,11")
                } else if nx == c("n") && i + 2 == n {
                    o(2, 12, tag: "mn$:12"); o(2, 12, 9, tag: "mn$:12,9")
                } else {
                    o(1, 12)
                }
            case c("n"):
                if nx == c("n") {
                    o(2, 9)
                } else if nx == c("g") && nx2 != c("h") {
                    let after: UInt8 = i + 2 < n ? s[i + 2] : 0
                    if after == 0 || (!isVowel(after) && after != c("l") && after != c("r") && after != y) {
                        o(2, 3, tag: "ng$:3"); o(2, 3, 2, tag: "ng$:3,2"); o(2, 9, 2, tag: "ng$:9,2")
                    } else if isFront(after) {
                        o(2, 9, 5, tag: "ng+f:9,5"); o(2, 6, 5, tag: "ng+f:6,5"); o(2, 3, 2, tag: "ng+f:3,2"); o(2, 3, tag: "ng+f:3")
                    } else {
                        o(2, 3, 2, tag: "ng+v:3,2"); o(2, 3, tag: "ng+v:3"); o(2, 9, 2, tag: "ng+v:9,2")
                    }
                } else if nx == c("k") || nx == c("q") || nx == c("x") || (nx == c("c") && !isFront(nx2) && nx2 != c("h")) {
                    o(1, 3, tag: "n+vel:3"); o(1, 9, tag: "n+vel:9"); o(1, tag: "n+vel:0")
                } else if nx == c("j") || nx == c("z") || (nx == c("c") && nx2 == c("h")) {
                    o(1, 6, tag: "n+pal:6"); o(1, 9, tag: "n+pal:9")
                } else if i > 0 && isVowel(pv) && (nx == c("s") || nx == c("h")) {
                    o(1, 9, tag: "n+sh:9"); o(1, 3, tag: "n+sh:3"); o(1, tag: "n+sh:0")
                } else if i > 0 && isVowel(pv) && nx != 0 && !isVowel(nx) && nx != y {
                    o(1, 9, tag: "n+c:9"); o(1, tag: "n+c:0")
                } else {
                    o(1, 9)
                }
            case c("p"):
                if nx == c("h") || nx == c("p") {
                    o(2, 10)
                } else if i == 0 && nx == c("s") {
                    o(2, 15, tag: "ps#:15"); o(2, 10, 15, tag: "ps#:10,15")
                } else if i == 0 && nx == c("n") {
                    o(2, 9)
                } else {
                    o(1, 10)
                }
            case c("q"):
                if tail(i, "que") {
                    o(3, 1, tag: "que$:1"); o(2, 1, w8, tag: "que$:1,v")
                } else if nx == c("u") {
                    o(2, 1, w8)
                } else {
                    o(1, 1)
                }
            case c("r"):
                if nx == c("h") && i > 0 {
                    o(2, 13, tag: "rh:13"); o(2, 13, 16, tag: "rh:13,16")
                } else {
                    o(nx == c("r") || nx == c("h") ? 2 : 1, 13)
                }
            case c("s"):
                if nx == c("h") {
                    o(2, 15)
                } else if nx == c("c") && nx2 == c("h") {
                    o(3, 15, 1, tag: "sch:15,1"); o(3, 15, tag: "sch:15"); o(3, 15, 4, tag: "sch:15,4")
                } else if nx == c("c") && isFront(nx2) {
                    o(2, 15)
                } else if nx == c("s") {
                    o(2, 15)
                } else if isVowel(pv) && (slice(i + 1, i + 4, "ion") || slice(i + 1, i + 4, "ure") || slice(i + 1, i + 4, "ual")) {
                    o(1, 15, tag: "s+ion:15"); o(1, 5, tag: "s+ion:5")
                } else if isVowel(pv) && (isVowel(nx) || nx == y) {
                    o(1, 15, tag: "s_vv:15"); o(1, 5, tag: "s_vv:5")
                } else if i == n - 1 && isVoicedEnd(pv) && i > 1 {
                    o(1, 15, tag: "s$v:15"); o(1, 5, tag: "s$v:5"); o(1, tag: "s$v:0")
                } else if i == n - 1 && i > 2 && pv != c("s") {
                    o(1, 15, tag: "s$u:15"); o(1, tag: "s$u:0")
                } else if nx == c("m") && i + 2 == n && isVowel(pv) {
                    o(1, 5, tag: "s_m$:5"); o(1, 15, tag: "s_m$:15")
                } else {
                    o(1, 15)
                }
            case c("t"):
                if rest("tion") || rest("tian") {
                    o(1, 15, tag: "tion:15"); o(1, 4, tag: "tion:4"); o(1, 7, tag: "tion:7")
                } else if rest("tch") {
                    o(3, 4)
                } else if nx == c("h") {
                    o(2, 7, tag: "th:7"); o(2, 8, tag: "th:8")
                } else if nx == c("t") {
                    o(2, 7)
                } else if nx == c("i") && isVowel(nx2) && i > 0 && i + 3 < n {
                    o(1, 15, tag: "ti+v:15"); o(1, 7, tag: "ti+v:7")
                } else if nx == c("u") && (nx2 == c("r") || isVowel(nx2)) && i > 0 {
                    o(1, 4, tag: "tu:4"); o(1, 7, tag: "tu:7")
                } else if pv == c("s") && (tail(i + 1, "en") || tail(i + 1, "le") || tail(i + 1, "ens") || tail(i + 1, "les") || tail(i + 1, "ener")) {
                    o(1, tag: "t_sil:0"); o(1, 7, tag: "t_sil:7")
                } else {
                    o(1, 7)
                }
            case c("v"):
                o(nx == c("v") ? 2 : 1, 11)
            case c("w"):
                if nx == c("h") {
                    o(2, 16, w8, tag: "wh:16"); o(2, w8, tag: "wh:w")
                } else if i == 0 && nx == c("r") {
                    o(2, 13)
                } else {
                    o(1, w8, tag: "w:w"); o(1, 11, tag: "w:11")
                }
            case c("x"):
                if i == 0 { o(1, 5, tag: "x#:5"); o(1, 1, 15, tag: "x#:1,15") } else { o(1, 1, 15, tag: "x:1,15"); o(1, 2, 5, tag: "x:2,5") }
            case c("y"):
                if isVowel(nx) && i == 0 {
                    o(1, y, tag: "y#:y"); o(1, 5, tag: "y#:5")
                } else if isVowel(nx) && isVowel(pv) {
                    o(1, y, tag: "y_vv:y"); o(1, 5, tag: "y_vv:5")
                } else {
                    o(1, y)
                }
            case c("z"):
                if nx == c("z") { o(2, 5) } else { o(1, 5, tag: "z:5"); o(1, 15, tag: "z:15") }
            default:
                o(1)   // anything else is ignored
            }
        }
        w.optionStart.append(w.options.count)
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// The cheapest readings of `s` under `ruleCost` (rkeys.Rules.beam): leaves in `w.order` the final
    /// states within `margin` of the best, cheapest first. States are token sequences: a vowel or glide
    /// letter, or a class with the roman letters it was read from. Equal sequences reached on different
    /// paths keep the cheaper cost in their first place, as the prototype's dictionaries do; ties keep
    /// that order.
    static func beam(_ s: [UInt8], ruleCost: [Double], width: Int, margin: Double, in w: inout Workspace) {
        let n = s.count
        w.arena.removeAll(keepingCapacity: true)
        w.stStart.removeAll(keepingCapacity: true); w.stCount.removeAll(keepingCapacity: true)
        w.stCost.removeAll(keepingCapacity: true); w.stHash.removeAll(keepingCapacity: true); w.stNext.removeAll(keepingCapacity: true)
        w.posHead.removeAll(keepingCapacity: true); w.posHead.append(contentsOf: repeatElement(-1, count: n + 1))
        w.posTail.removeAll(keepingCapacity: true); w.posTail.append(contentsOf: repeatElement(-1, count: n + 1))
        w.posSize.removeAll(keepingCapacity: true); w.posSize.append(contentsOf: repeatElement(0, count: n + 1))
        if w.slotKey.isEmpty { w.growTable(to: 256) }
        w.stamp &+= 1
        if w.stamp == 0 {
            for k in w.slotStamp.indices { w.slotStamp[k] = 0 }
            w.stamp = 1
        }
        w.slots = 0
        // The start state.
        w.stStart.append(0); w.stCount.append(0); w.stCost.append(0.0); w.stHash.append(0xCBF2_9CE4_8422_2325); w.stNext.append(-1)
        w.posHead[0] = 0; w.posTail[0] = 0; w.posSize[0] = 1
        for i in 0..<n {
            guard w.posSize[i] > 0 else { continue }
            w.order.removeAll(keepingCapacity: true)
            var st = w.posHead[i]
            while st >= 0 { w.order.append(st); st = w.stNext[Int(st)] }
            if w.order.count > width {
                // State ids grow in insertion order, so this is a stable sort by cost.
                let cost = w.stCost
                w.order.sort { cost[Int($0)] != cost[Int($1)] ? cost[Int($0)] < cost[Int($1)] : $0 < $1 }
                w.order.removeLast(w.order.count - width)
            }
            for k in 0..<w.order.count {
                let parent = Int(w.order[k])
                for oi in w.optionStart[i]..<w.optionStart[i + 1] {
                    let opt = w.options[oi]
                    let oc = opt.tag >= 0 ? ruleCost[opt.tag] : 0.0
                    let l = opt.length
                    // Tokens: a letter (0x8000_0000 | ASCII) or a class with its label: class (5 bits), index in
                    // a two-class option + 1 (2 bits), letters read (3 bits), those letters (5 bits each).
                    var letterBits: UInt32 = 0
                    for q in 0..<l { letterBits |= UInt32(s[i + q] &- 0x60) << (5 * UInt32(q)) }
                    let twoClasses = opt.count == 2 && opt.a <= 16 && opt.b <= 16
                    var conv0: UInt32 = 0, conv1: UInt32 = 0
                    if opt.count > 0 {
                        conv0 = opt.a <= 16 ? UInt32(opt.a) | (twoClasses ? 1 : 0) << 5 | UInt32(l) << 7 | letterBits << 10 : 0x8000_0000 | UInt32(opt.a)
                    }
                    if opt.count > 1 {
                        conv1 = opt.b <= 16 ? UInt32(opt.b) | (twoClasses ? 2 : 0) << 5 | UInt32(l) << 7 | letterBits << 10 : 0x8000_0000 | UInt32(opt.b)
                    }
                    let convCount = opt.count
                    var h = w.stHash[parent]
                    if convCount > 0 { h = (h ^ UInt64(conv0)) &* 0x0000_0100_0000_01B3; h ^= h >> 29 }
                    if convCount > 1 { h = (h ^ UInt64(conv1)) &* 0x0000_0100_0000_01B3; h ^= h >> 29 }
                    let j = i + l
                    let total = w.stCost[parent] + oc
                    let key = h &+ UInt64(j) &* 0x9E37_79B9_7F4A_7C15
                    let mask = w.slotKey.count - 1
                    var slot = Int(truncatingIfNeeded: key >> 7) & mask
                    var found = -1
                    let pc = Int(w.stCount[parent]), ps = Int(w.stStart[parent])
                    while w.slotStamp[slot] == w.stamp {
                        if w.slotKey[slot] == key {
                            // Same tokens: the parent's followed by conv.
                            let e = Int(w.slotState[slot])
                            var same = Int(w.stCount[e]) == pc + convCount
                            if same {
                                let a = Int(w.stStart[e])
                                for z in 0..<pc where w.arena[a + z] != w.arena[ps + z] { same = false; break }
                                if same, convCount > 0, w.arena[a + pc] != conv0 { same = false }
                                if same, convCount > 1, w.arena[a + pc + 1] != conv1 { same = false }
                            }
                            if same { found = e; break }
                        }
                        slot = (slot + 1) & mask
                    }
                    if found >= 0 {
                        if w.stCost[found] > total { w.stCost[found] = total }
                        continue
                    }
                    // The new state's tokens: the parent's, then conv (copied one by one: appending a slice
                    // of the arena to itself would copy the whole arena).
                    let start = w.arena.count
                    w.arena.reserveCapacity(start + pc + convCount)
                    for z in 0..<pc { w.arena.append(w.arena[ps + z]) }
                    if convCount > 0 { w.arena.append(conv0) }
                    if convCount > 1 { w.arena.append(conv1) }
                    let id = Int32(w.stCost.count)
                    w.stStart.append(Int32(start)); w.stCount.append(Int32(pc + convCount)); w.stCost.append(total)
                    w.stHash.append(h); w.stNext.append(-1)
                    if w.posTail[j] >= 0 { w.stNext[Int(w.posTail[j])] = id } else { w.posHead[j] = id }
                    w.posTail[j] = id
                    w.posSize[j] += 1
                    w.slotKey[slot] = key; w.slotState[slot] = id; w.slotStamp[slot] = w.stamp
                    w.slots += 1
                    if w.slots * 2 > w.slotKey.count { w.growTable(to: w.slotKey.count * 2) }
                }
            }
        }
        // The final states within the margin, cheapest first (ties in insertion order).
        w.order.removeAll(keepingCapacity: true)
        var st = w.posHead[n]
        while st >= 0 { w.order.append(st); st = w.stNext[Int(st)] }
        let cost = w.stCost
        w.order.sort { cost[Int($0)] != cost[Int($1)] ? cost[Int($0)] < cost[Int($1)] : $0 < $1 }
        if let first = w.order.first {
            let limit = cost[Int(first)] + margin
            while let last = w.order.last, cost[Int(last)] > limit { w.order.removeLast() }
        }
    }

    /// Builds the template of beam state `state` in the workspace's tmp* buffers (rkeys.template):
    /// classes (a cluster of one class merged), raw vowel segments, labels ("th|7", clusters joined with
    /// "+") and context marks.
    static func template(of state: Int, _ s: [UInt8], in w: inout Workspace) {
        w.tmpClasses.removeAll(keepingCapacity: true)
        w.tmpSegStart.removeAll(keepingCapacity: true); w.tmpSegStart.append(0)
        w.tmpSegLetters.removeAll(keepingCapacity: true)
        w.tmpLabelStart.removeAll(keepingCapacity: true)
        w.tmpLabelBytes.removeAll(keepingCapacity: true)
        let a = Int(w.stStart[state]), count = Int(w.stCount[state])
        for p in a..<a + count {
            let t = w.arena[p]
            if t & 0x8000_0000 != 0 {
                w.tmpSegLetters.append(UInt8(t & 0x7F))
                continue
            }
            let c = UInt8(t & 0x1F)
            if let last = w.tmpClasses.last, last == c, w.tmpSegLetters.count == w.tmpSegStart[w.tmpSegStart.count - 1] {
                w.tmpLabelBytes.append(0x2B)   // + : a cluster of one class
                appendLabelBase(t, to: &w.tmpLabelBytes)
                continue
            }
            if let last = w.tmpClasses.last { closeLabel(last, &w.tmpLabelBytes) }
            w.tmpClasses.append(c)
            w.tmpSegStart.append(w.tmpSegLetters.count)
            w.tmpLabelStart.append(w.tmpLabelBytes.count)
            appendLabelBase(t, to: &w.tmpLabelBytes)
        }
        if let last = w.tmpClasses.last { closeLabel(last, &w.tmpLabelBytes) }
        w.tmpSegStart.append(w.tmpSegLetters.count)
        markSegments(s, in: &w)
    }

    /// The roman letters of a class token, and its index in a two-class option.
    private static func appendLabelBase(_ t: UInt32, to bytes: inout [UInt8]) {
        let k = (t >> 5) & 0x3, l = Int((t >> 7) & 0x7)
        for q in 0..<l { bytes.append(UInt8((t >> (10 + 5 * UInt32(q))) & 0x1F) + 0x60) }
        if k > 0 { bytes.append(0x30 + UInt8(k - 1)) }
    }

    private static func closeLabel(_ c: UInt8, _ bytes: inout [UInt8]) {
        bytes.append(0x7C)   // |
        if c >= 10 { bytes.append(0x30 + c / 10) }
        bytes.append(0x30 + c % 10)
    }

    /// rkeys.mark: E for a final e after a consonant, ^ for the vowel before it (magic e), ~ for a vowel
    /// before an r with no vowel after it.
    private static func markSegments(_ s: [UInt8], in w: inout Workspace) {
        let m = w.tmpClasses.count, n = s.count
        func length(_ k: Int) -> Int { w.tmpSegStart[k + 1] - w.tmpSegStart[k] }
        func last(_ k: Int) -> UInt8 { w.tmpSegLetters[w.tmpSegStart[k + 1] - 1] }
        func vowelOrY(_ c: UInt8) -> Bool { isVowel(c) || c == 0x79 }
        var eFinal = false, caretAt = -1
        if m >= 1, length(m) == 1, last(m) == 0x65, n >= 2, s[n - 1] == 0x65, !isVowel(s[n - 2]) {
            eFinal = true
            if n >= 3, isVowel(s[n - 3]) || s[n - 3] == 0x79, length(m - 1) > 0, vowelOrY(last(m - 1)) { caretAt = m - 1 }
        }
        w.tildes.removeAll(keepingCapacity: true)
        w.tildes.append(contentsOf: repeatElement(false, count: m + 1))
        for k in 0..<m where w.tmpClasses[k] == 13 && k >= 1 && length(k) > 0 && caretAt != k && vowelOrY(last(k)) {
            // The next segment is empty or the final E.
            if (k + 1 == m && eFinal) || length(k + 1) == 0 { w.tildes[k] = true }
        }
        w.eFinal = eFinal
        w.caretAt = caretAt
    }

    /// Segment k of the template being built, with its marks, into `w.keyBytes`.
    static func markedSegment(_ k: Int, in w: inout Workspace) {
        let m = w.tmpClasses.count
        w.keyBytes.removeAll(keepingCapacity: true)
        if k == 0 { w.keyBytes.append(0x23) }   // #
        if k == m && w.eFinal {
            w.keyBytes.append(0x45)   // E
        } else {
            w.keyBytes.append(contentsOf: w.tmpSegLetters[w.tmpSegStart[k]..<w.tmpSegStart[k + 1]])
        }
        if w.caretAt == k { w.keyBytes.append(0x5E) }   // ^
        if w.tildes[k] { w.keyBytes.append(0x7E) }   // ~
        if k == m { w.keyBytes.append(0x24) }   // $
    }
}

// MARK: - Scratch space

/// Buffers for one query, kept from query to query so that a query allocates little (the
/// retriever's lock serialises queries).
struct Workspace {
    // The options at each position of the typed word.
    var options: [RomanReading.Option] = []
    var optionStart: [Int] = []
    // Beam states: their tokens (in `arena`), cost and hash, and the states of each position in order.
    var arena: [UInt32] = []
    var stStart: [Int32] = [], stCount: [Int32] = [], stCost: [Double] = [], stHash: [UInt64] = [], stNext: [Int32] = []
    var posHead: [Int32] = [], posTail: [Int32] = [], posSize: [Int32] = []
    // Open addressing: (position, token hash) -> state.
    var slotKey: [UInt64] = [], slotState: [Int32] = [], slotStamp: [UInt32] = []
    var stamp: UInt32 = 0, slots = 0
    /// Beam states being expanded; after the beam, the final states within the margin, cheapest first.
    var order: [Int32] = []
    // The template being built.
    var tmpClasses: [UInt8] = [], tmpSegStart: [Int] = [], tmpSegLetters: [UInt8] = [], tmpLabelStart: [Int] = [], tmpLabelBytes: [UInt8] = []
    var keyBytes: [UInt8] = []
    // Its context marks (rkeys.mark) as flags; `RomanReading.markedSegment` writes them out.
    var eFinal = false, caretAt = -1
    var tildes: [Bool] = []
    // Templates of both models: classes at tStart..<tStart + tLength, label rows likewise, segment rows
    // at tStart + t (one more); collapsed classes at tCollapsedStart, their rows at tCollapsedStart + t.
    var tModel: [Int] = [], tCost: [Double] = [], tBias: [Double] = [], tKey: [UInt64] = []
    var tStart: [Int] = [], tLength: [Int] = [], tClasses: [UInt8] = [], tSegRows: [Int32] = [], tLabelRows: [Int32] = []
    var tCollapsedStart: [Int] = [], tCollapsedLength: [Int] = [], tCollapsed: [UInt8] = [], tCollapsedRows: [Int32] = []

    mutating func resetTemplates() {
        tModel.removeAll(keepingCapacity: true); tCost.removeAll(keepingCapacity: true); tBias.removeAll(keepingCapacity: true)
        tKey.removeAll(keepingCapacity: true); tStart.removeAll(keepingCapacity: true); tLength.removeAll(keepingCapacity: true)
        tClasses.removeAll(keepingCapacity: true); tSegRows.removeAll(keepingCapacity: true); tLabelRows.removeAll(keepingCapacity: true)
        tCollapsedStart.removeAll(keepingCapacity: true); tCollapsedLength.removeAll(keepingCapacity: true)
        tCollapsed.removeAll(keepingCapacity: true); tCollapsedRows.removeAll(keepingCapacity: true)
    }

    /// Whether no template since `first` has the classes of the template being built.
    func isNewClassSequence(since first: Int) -> Bool {
        for t in first..<tCost.count where tLength[t] == tmpClasses.count && tClasses[tStart[t]..<tStart[t] + tLength[t]].elementsEqual(tmpClasses) {
            return false
        }
        return true
    }

    /// Adds the template being built, with the memo rows of its marked segments and labels.
    mutating func addTemplate(model: Int, bias: Double, cost: Double, memo: LoanwordRetriever.Model) {
        let n = tmpClasses.count
        tModel.append(model); tCost.append(cost); tBias.append(bias)
        tKey.append(BanglaShape.packedKey(tmpClasses))
        tStart.append(tClasses.count); tLength.append(n)
        tClasses.append(contentsOf: tmpClasses)
        let segRowsAt = tSegRows.count
        for k in 0...n {
            RomanReading.markedSegment(k, in: &self)
            tSegRows.append(memo.segments.row(keyBytes))
        }
        for k in 0..<n {
            let end = k + 1 < tmpLabelStart.count ? tmpLabelStart[k + 1] : tmpLabelBytes.count
            keyBytes.removeAll(keepingCapacity: true)
            keyBytes.append(contentsOf: tmpLabelBytes[tmpLabelStart[k]..<end])
            tLabelRows.append(memo.consonants.row(keyBytes))
        }
        // Collapsed: segment 0, then per kept class the segment after its run.
        tCollapsedStart.append(tCollapsed.count)
        tCollapsedRows.append(tSegRows[segRowsAt])
        var length = 0
        for k in 0..<n {
            if length > 0, tCollapsed[tCollapsed.count - 1] == tmpClasses[k] {
                tCollapsedRows[tCollapsedRows.count - 1] = tSegRows[segRowsAt + k + 1]
                continue
            }
            tCollapsed.append(tmpClasses[k]); tCollapsedRows.append(tSegRows[segRowsAt + k + 1]); length += 1
        }
        tCollapsedLength.append(length)
    }

    mutating func growTable(to size: Int) {
        var old: [(UInt64, Int32)] = []
        for k in slotKey.indices where slotStamp[k] == stamp { old.append((slotKey[k], slotState[k])) }
        slotKey = [UInt64](repeating: 0, count: size)
        slotState = [Int32](repeating: 0, count: size)
        slotStamp = [UInt32](repeating: 0, count: size)
        for (key, state) in old {
            var slot = Int(truncatingIfNeeded: key >> 7) & (size - 1)
            while slotStamp[slot] == stamp { slot = (slot + 1) & (size - 1) }
            slotKey[slot] = key; slotState[slot] = state; slotStamp[slot] = stamp
        }
    }
}
