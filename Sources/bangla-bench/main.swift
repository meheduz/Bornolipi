// Engine benchmarks on the machine they run on. Every word of the corpus is typed one key at a
// time, as a user would, and each step is timed. Build optimised:
//   swift run -c release bangla-bench [--data Data] [--words N] [--loanwords]
// --loanwords turns on the experimental loanword retriever (EngineSettings.loanwordSuggestions).
import Foundation
import BanglaEngine
#if canImport(Darwin)
import Darwin
#endif

/// Memory the process is charged for (what Activity Monitor shows), in MB.
func footprintMB() -> Double {
    #if canImport(Darwin)
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    #else
    return -1
    #endif
}

func nowNS() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

func ms(_ f: () throws -> Void) rethrows -> Double {
    let t = nowNS()
    try f()
    return Double(nowNS() - t) / 1e6
}

struct Percentiles {
    let p50, p95, p99, max: Double
    init(_ samples: [Double]) {
        let s = samples.sorted()
        func at(_ q: Double) -> Double { s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * q))] }
        p50 = at(0.50); p95 = at(0.95); p99 = at(0.99); max = s.last ?? 0
    }
}

func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

final class NullClient: TextClient {
    func insert(_ text: String) {}
    func setMarked(_ text: String) {}
}

var dataDir = URL(fileURLWithPath: "Data")
let args = CommandLine.arguments
func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
if let d = value("--data") { dataDir = URL(fileURLWithPath: d) }
var settings = EngineSettings()
settings.loanwordSuggestions = args.contains("--loanwords")

do {
    let base = footprintMB()
    let grammar = dataDir.appendingPathComponent("AvroPhonetic.json")
    let dict = dataDir.appendingPathComponent("dictionary.json")

    let grammarLoad = median(try (0..<10).map { _ in try ms { _ = try AvroParser(grammarURL: grammar) } })
    var index: WordIndex?
    let indexLoads = try (0..<3).map { _ in try ms { index = try WordIndex(dictionaryURL: dict) } }
    let afterIndex = footprintMB()
    index = nil
    _ = index
    var suggester: Suggester!
    let fullLoad = try ms { suggester = try Suggester(dataDirectory: dataDir, settings: settings, loadDictionaryInBackground: false) }
    let afterSuggester = footprintMB()

    // Corpus: real-world roman spellings and their corrections from autocorrect.json.
    let ac = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: dataDir.appendingPathComponent("autocorrect.json")))
    var words = Array(Set(ac.keys).union(ac.values)).filter { !$0.isEmpty && !$0.contains(" ") }.sorted()
    if let n = value("--words").flatMap(Int.init) { words = Array(words.prefix(n)) }

    var convert: [Double] = [], suggest: [Double] = [], keys: [Double] = []
    var slowest: [(Double, String)] = []
    let parser = suggester.parser
    for w in words {
        var prefix = ""
        for c in w {
            prefix.append(c)
            var t = nowNS()
            _ = parser.convert(prefix)
            convert.append(Double(nowNS() - t) / 1000)
            t = nowNS()
            _ = suggester.suggest(prefix)
            let us = Double(nowNS() - t) / 1000
            suggest.append(us)
            slowest.append((us, prefix))
        }
    }
    // The whole key path (session state, suggestions, marked text) through InputHandler.
    let handler = InputHandler(suggester: suggester)
    let client = NullClient()
    for w in words {
        for c in w + " " {
            let code: UInt16 = c == " " ? KeyCode.space : 0
            let key = KeyPress(keyCode: code, characters: String(c), modifiers: c.isUppercase ? Shortcut.shift : 0)
            let t = nowNS()
            _ = handler.handle(key, bangla: true, client: client)
            keys.append(Double(nowNS() - t) / 1000)
        }
    }
    slowest.sort { $0.0 > $1.0 }

    func row(_ name: String, _ p: Percentiles, _ n: Int) -> String {
        String(format: "| %@ | %d | %.1f | %.1f | %.1f | %.1f |", name, n, p.p50, p.p95, p.p99, p.max)
    }
    print("Corpus: \(words.count) words, \(convert.count) keystrokes. Times in microseconds.\n")
    print("| Step | Samples | p50 | p95 | p99 | max |")
    print("| --- | ---: | ---: | ---: | ---: | ---: |")
    print(row("Rule conversion (AvroParser.convert)", Percentiles(convert), convert.count))
    print(row("Candidates (Suggester.suggest)", Percentiles(suggest), suggest.count))
    print(row("Whole key press (InputHandler.handle)", Percentiles(keys), keys.count))
    print("")
    print(String(format: "Grammar load: %.1f ms (median of 10)", grammarLoad))
    print(String(format: "Dictionary load and index (%d words): %.0f ms (median of 3: %@)", suggester.index.count,
                 median(indexLoads), indexLoads.map { String(format: "%.0f", $0) }.joined(separator: ", ")))
    print(String(format: "Full engine load: %.0f ms", fullLoad))
    print(String(format: "Memory footprint: %.1f MB at start, %.1f MB after one index, %.1f MB with the engine loaded",
                 base, afterIndex, afterSuggester))
    print(String(format: "Memory footprint after the benchmark: %.1f MB", footprintMB()))
    if settings.loanwordSuggestions {
        if let r = suggester.loanwordRetriever {
            print(String(format: "Loanword retriever: on, %d words, built in %.0f ms (part of the full load), %.1f MB of arrays and memo tables",
                         r.count, r.loadMilliseconds, Double(r.footprintBytes) / 1_048_576))
        } else {
            print("Loanword retriever: on but not built: \(suggester.loanwordError.map { "\($0)" } ?? "unknown")")
        }
    } else {
        print("Loanword retriever: off")
    }
    print("\nSlowest candidate lookups:")
    for (us, p) in slowest.prefix(8) { print(String(format: "  %8.1f us  %@", us, p)) }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
