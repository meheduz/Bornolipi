// swift-tools-version:5.9
import PackageDescription

// The input method, its installer and the app use AppKit, Carbon and InputMethodKit, so they are part of the
// package only on macOS. Elsewhere (the Linux CI job) the package is the engine, its tools and its tests.
#if os(macOS)
let appleProducts: [Product] = [
    .executable(name: "Bornolipi", targets: ["Bornolipi"]),
    .executable(name: "BornolipiKeyboard", targets: ["BornolipiKeyboard"]),
]
let appleTargets: [Target] = [
    // The macOS input method app (InputMethodKit, AppKit, SwiftUI).
    .executableTarget(name: "BornolipiKeyboard", dependencies: ["BanglaEngine", "InstallKit"]),
    // Installing, checking, repairing and removing the input method (macOS only).
    .target(name: "InstallKit"),
    // "Bornolipi.app", the app people open: setup assistant, status, repair, updates, uninstall.
    // It carries the input method inside and installs it; see scripts/build.sh.
    .executableTarget(name: "Bornolipi", dependencies: ["InstallKit"]),
    // Installer, update-feed and keyboard-restart tests.
    .testTarget(name: "InstallKitTests", dependencies: ["InstallKit"]),
]
#else
let appleProducts: [Product] = []
let appleTargets: [Target] = []
#endif

let package = Package(
    name: "Bornolipi",
    platforms: [.macOS(.v13)],
    products: appleProducts + [
        .library(name: "BanglaEngine", targets: ["BanglaEngine"]),
        .executable(name: "bangla-convert", targets: ["bangla-convert"]),
        .executable(name: "bangla-bench", targets: ["bangla-bench"]),
        .executable(name: "bangla-eval", targets: ["bangla-eval"]),
        .executable(name: "loanword-parity", targets: ["loanword-parity"]),
    ],
    targets: appleTargets + [
        // Pure Foundation engine: builds and tests on macOS and Linux.
        .target(name: "BanglaEngine"),
        // Developer tool: type roman text on stdin, see Bangla and suggestions.
        .executableTarget(name: "bangla-convert", dependencies: ["BanglaEngine"]),
        // Developer tool: latency, load time and memory benchmarks (run with -c release).
        .executableTarget(name: "bangla-bench", dependencies: ["BanglaEngine"]),
        // Developer tool: suggestion quality on Tests/Evaluation and default-commit stability.
        .executableTarget(name: "bangla-eval", dependencies: ["BanglaEngine"]),
        // Developer tool: parity of the experimental loanword retriever with its lab prototype, and its latency.
        .executableTarget(name: "loanword-parity", dependencies: ["BanglaEngine"]),
        // Engine tests, by responsibility: Transliteration, Suggestions, Input, Unicode, Data,
        // Properties (state-machine fuzzing); reference data in Fixtures.
        .testTarget(name: "BanglaEngineTests", dependencies: ["BanglaEngine"], exclude: ["Fixtures"]),
    ]
)
