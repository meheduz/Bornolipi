// Developer tool: measures suggestion quality on Tests/Evaluation/suggestions.tsv, and checks that
// the default commit (what Space inserts) is unchanged against a recorded baseline.
//   swift run -c release bangla-eval [--data Data] [--corpus Tests/Evaluation/suggestions.tsv]
//                                    [--record-defaults FILE | --compare-defaults FILE] [--verbose] [--loanwords]
// --loanwords turns on the experimental loanword retriever (EngineSettings.loanwordSuggestions).
import BanglaEngine
import Foundation

let args = CommandLine.arguments
func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
let data = URL(fileURLWithPath: value("--data") ?? "Data")
let corpus = value("--corpus") ?? "Tests/Evaluation/suggestions.tsv"
let verbose = args.contains("--verbose")
var settings = EngineSettings()
settings.loanwordSuggestions = args.contains("--loanwords")
let suggester = try Suggester(dataDirectory: data, settings: settings, selections: SelectionStore(), loadDictionaryInBackground: false)
if settings.loanwordSuggestions {
    guard let r = suggester.loanwordRetriever else { fatalError("loanword retriever not built: \(suggester.loanwordError.map { "\($0)" } ?? "unknown")") }
    print("Loanword retriever: on (\(r.count) words)")
}

struct Row { let input, expected, category, kind: String }
let rows: [Row] = try String(contentsOfFile: corpus, encoding: .utf8).split(separator: "\n").compactMap { line in
    guard !line.hasPrefix("#") else { return nil }
    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    return f.count >= 5 ? Row(input: f[0], expected: f[1], category: f[2], kind: f[4]) : nil
}

struct Tally { var n = 0, top1 = 0, top3 = 0, any = 0 }
var byCategory: [String: Tally] = [:]
var falsePositives = 0, probes = 0
var misses: [String] = []
for r in rows {
    let c = suggester.suggest(r.input).candidates
    if r.kind == "mustNot" {
        probes += 1
        if c.contains(r.expected) { falsePositives += 1; misses.append("FALSE POSITIVE \(r.input): \(c.joined(separator: " "))") }
        continue
    }
    var t = byCategory[r.category, default: Tally()]
    t.n += 1
    if c.first == r.expected { t.top1 += 1 }
    if c.prefix(3).contains(r.expected) { t.top3 += 1 }
    if c.contains(r.expected) { t.any += 1 } else { misses.append("miss \(r.category) \(r.input) -> want \(r.expected), got \(c.prefix(5).joined(separator: " "))") }
    byCategory[r.category] = t
}
func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.0f%%", 100 * Double(a) / Double(b)) }
print("| Category | Cases | Top-1 | Top-3 | Offered |")
print("| --- | ---: | ---: | ---: | ---: |")
var total = Tally()
for (k, t) in byCategory.sorted(by: { $0.key < $1.key }) {
    print("| \(k) | \(t.n) | \(pct(t.top1, t.n)) | \(pct(t.top3, t.n)) | \(pct(t.any, t.n)) |")
    total.n += t.n; total.top1 += t.top1; total.top3 += t.top3; total.any += t.any
}
print("| **all** | \(total.n) | \(pct(total.top1, total.n)) | \(pct(total.top3, total.n)) | \(pct(total.any, total.n)) |")
print("False positives: \(falsePositives) of \(probes) probes")
if verbose { misses.forEach { print("  " + $0) } }

// Default commits: what Space inserts for a fixed, reproducible set of inputs.
var g: UInt64 = 20261024
func next() -> UInt64 { g = g &* 6364136223846793005 &+ 1442695040888963407; return g >> 33 }
let alphabet = Array("abcdeghijklmnoprstuvyABDGHJKNORSTUZ`.,")
var inputs = rows.map(\.input)
for _ in 0..<20_000 { inputs.append(String((0..<Int(1 + next() % 9)).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] })) }
let defaults = inputs.map { "\($0)\t\(suggester.suggest($0).candidates.first ?? "")" }
let rawSame = inputs.filter { suggester.parser.convert($0) == suggester.suggest($0).candidates.first }.count
print("Space inserts the exact rule conversion for \(rawSame) of \(inputs.count) inputs (dictionary and autocorrect account for the rest)")
if let file = value("--record-defaults") {
    try defaults.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
    print("Recorded default commits to \(file)")
}
if let file = value("--compare-defaults") {
    // Matched by input, so cases added to the corpus since the recording do not shift the comparison.
    var before: [String: String] = [:]
    for line in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") {
        let f = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if f.count == 2 { before[f[0]] = before[f[0]] ?? f[1] }
    }
    let compared = defaults.filter { before[String($0.split(separator: "\t", omittingEmptySubsequences: false)[0])] != nil }
    let changed = compared.compactMap { line -> (String, String)? in
        let f = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let was = "\(f[0])\t\(before[f[0]]!)"
        return was == line ? nil : (was, line)
    }
    print("Default commit changed for \(changed.count) of \(compared.count) inputs")
    let current = Set(inputs)
    let missing = before.keys.filter { !current.contains($0) }.count
    if missing > 0 || compared.count < defaults.count {
        print("  not compared: \(missing) recorded inputs no longer present, \(defaults.count - compared.count) new inputs")
    }
    for (a, b) in changed.prefix(verbose ? 200 : 20) { print("  \(a.replacingOccurrences(of: "\t", with: ": "))  ->  \(b.split(separator: "\t").last ?? "")") }
}
