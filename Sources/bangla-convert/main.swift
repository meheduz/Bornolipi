// Developer tool: reads roman text from stdin (one word per line) and prints the candidates.
//   echo ami | swift run bangla-convert
//   swift run bangla-convert --data ./Data < words.txt
//   swift run bangla-convert --raw < lines.txt     rule conversion only, one output line per input line
//   swift run bangla-convert --settings '{"autocorrect": false}' < words.txt
import Foundation
import BanglaEngine

var dataDir = URL(fileURLWithPath: "Data")
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--data"), i + 1 < args.count { dataDir = URL(fileURLWithPath: args[i + 1]) }
var settings = EngineSettings()
if let i = args.firstIndex(of: "--settings"), i + 1 < args.count {
    do { settings = try JSONDecoder().decode(EngineSettings.self, from: Data(args[i + 1].utf8)) } catch {
        FileHandle.standardError.write(Data("bad --settings JSON: \(error)\n".utf8))
        exit(2)
    }
}

do {
    if args.contains("--raw") {
        let parser = try AvroParser(grammarURL: dataDir.appendingPathComponent("AvroPhonetic.json"))
        while let line = readLine() { print(parser.convert(line)) }
        exit(0)
    }
    let start = Date()
    let s = try Suggester(dataDirectory: dataDir, settings: settings, loadDictionaryInBackground: false)
    FileHandle.standardError.write(Data("loaded \(s.index.count) words in \(Int(Date().timeIntervalSince(start) * 1000)) ms\n".utf8))
    while let line = readLine() {
        let t0 = Date()
        let r = s.suggest(line)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("\(line)\t\(r.candidates.joined(separator: " | "))\t[\(String(format: "%.2f", ms)) ms]")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
