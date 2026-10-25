// Developer tool for the experimental loanword retriever: checks that the Swift port gives the lab
// prototype's results (its generate() output, stored as JSONL) and times the generator on its own.
//   swift run -c release loanword-parity --inputs DIR --expected DIR [--data Data] [--sets silver,typed,native]
//                                        [--show N] [--dump FILE]
// --inputs holds <set>.tsv files of id<TAB>input lines; --expected holds the prototype's <set>.jsonl
// ({"id", "input", "gen": [[bangla, score, confident], ...]}, best first). Both come from the lab, not
// from this repository. Every input runs twice: the first pass fills the cost memo, the second is warm.
import BanglaEngine
import Foundation

let args = CommandLine.arguments
func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
guard let inputsDir = value("--inputs"), let expectedDir = value("--expected") else {
    FileHandle.standardError.write(Data("usage: loanword-parity --inputs DIR --expected DIR [--data Data] [--sets a,b] [--show N] [--dump FILE]\n".utf8))
    exit(2)
}
let data = URL(fileURLWithPath: value("--data") ?? "Data")
let sets = (value("--sets") ?? "silver,typed,native").split(separator: ",").map(String.init)
let show = Int(value("--show") ?? "10") ?? 10

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
let t0 = now()
let index = try WordIndex(dictionaryURL: data.appendingPathComponent("dictionary.json"))
let t1 = now()
let retriever = try LoanwordRetriever(dataDirectory: data, dictionary: index)
let t2 = now()
print(String(format: "Dictionary: %d words, %.0f ms. Retriever: %d words, built in %.0f ms (measured inside: %.0f ms).",
             index.count, Double(t1 - t0) / 1e6, retriever.count, Double(t2 - t1) / 1e6, retriever.loadMilliseconds))

struct Expected { let words: [String]; let scores: [Double] }
struct Case { let set, id, input: String; let expected: Expected }
var cases: [Case] = []
for set in sets {
    var expected: [String: Expected] = [:]
    for line in try String(contentsOfFile: "\(expectedDir)/\(set).jsonl", encoding: .utf8).split(separator: "\n") {
        guard let o = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = o["id"] as? String,
              let gen = o["gen"] as? [[Any]] else { fatalError("bad line in \(set).jsonl") }
        expected[id] = Expected(words: gen.map { $0[0] as! String }, scores: gen.map { ($0[1] as! NSNumber).doubleValue })
    }
    for line in try String(contentsOfFile: "\(inputsDir)/\(set).tsv", encoding: .utf8).split(separator: "\n") {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 2, let e = expected[f[0]] else { fatalError("no expected output for \(line)") }
        cases.append(Case(set: set, id: f[0], input: f[1], expected: e))
    }
}

// Pass 1 (memo cold) and pass 2 (warm), timed per call.
var results: [[LoanwordRetriever.Candidate]] = []
results.reserveCapacity(cases.count)
var cold: [Double] = [], warm: [Double] = []
for c in cases {
    let t = now()
    let g = retriever.generate(c.input)
    cold.append(Double(now() - t) / 1000)
    results.append(g)
}
for (k, c) in cases.enumerated() {
    let t = now()
    let g = retriever.generate(c.input)
    warm.append(Double(now() - t) / 1000)
    if g != results[k] { print("NOT DETERMINISTIC: \(c.input)") }
}

struct Tally { var n = 0, top1 = 0, top3 = 0, full = 0, scores = 0, emptyBoth = 0 }
var tallies: [String: Tally] = [:]
var mismatches: [String] = []
var dump: [String] = []
for (k, c) in cases.enumerated() {
    let got = results[k].map(\.word), want = c.expected.words
    var t = tallies[c.set, default: Tally()]
    t.n += 1
    if got.first == want.first { t.top1 += 1 }
    if Array(got.prefix(3)) == Array(want.prefix(3)) { t.top3 += 1 }
    if got == want {
        t.full += 1
        if got.isEmpty { t.emptyBoth += 1 }
        // The prototype writes round(-cost, 4).
        if zip(results[k], c.expected.scores).allSatisfy({ abs(-$0.cost - $1) <= 0.5e-4 + 1e-9 }) { t.scores += 1 }
    } else {
        mismatches.append("\(c.set) \(c.id) \(c.input)\n    swift:  \(zip(got, results[k]).map { "\($0.0) \(String(format: "%.4f", -$0.1.cost))" }.joined(separator: ", "))\n    python: \(zip(want, c.expected.scores).map { "\($0.0) \($0.1)" }.joined(separator: ", "))")
    }
    tallies[c.set] = t
    dump.append("\(c.set)\t\(c.id)\t\(c.input)\t\(got.joined(separator: "|"))")
}
print("\n| Set | Inputs | Top-1 equal | Top-3 equal (ordered) | Whole list equal | Scores equal (4 dp) |")
print("| --- | ---: | ---: | ---: | ---: | ---: |")
var all = Tally()
for set in sets {
    let t = tallies[set] ?? Tally()
    print("| \(set) | \(t.n) | \(t.top1) | \(t.top3) | \(t.full) | \(t.scores) |")
    all.n += t.n; all.top1 += t.top1; all.top3 += t.top3; all.full += t.full; all.scores += t.scores; all.emptyBoth += t.emptyBoth
}
print("| all | \(all.n) | \(all.top1) | \(all.top3) | \(all.full) | \(all.scores) |")
print("Inputs with no candidates on both sides: \(all.emptyBoth)")

func percentiles(_ xs: [Double]) -> String {
    let s = xs.sorted()
    func at(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count) * q))] }
    return String(format: "p50 %.1f  p90 %.1f  p99 %.1f  max %.1f  mean %.1f", at(0.5), at(0.9), at(0.99), s.last ?? 0, s.reduce(0, +) / Double(max(s.count, 1)))
}
print("\nGenerator alone, per word (microseconds), \(cases.count) inputs:")
print("  pass 1 (memo filling): " + percentiles(cold))
print("  pass 2 (warm):         " + percentiles(warm))
print("Retriever arrays and memo tables after the run: \(String(format: "%.2f", Double(retriever.footprintBytes) / 1_048_576)) MB")
if !mismatches.isEmpty {
    print("\nMismatches (\(mismatches.count)), first \(show):")
    for m in mismatches.prefix(show) { print(m) }
}
if let file = value("--dump") {
    try (dump.joined(separator: "\n") + "\n").write(toFile: file, atomically: true, encoding: .utf8)
    print("\nWrote \(file)")
}
