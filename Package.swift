// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltTab",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure-logic library: window filtering, MRU ordering, grid navigation,
        // switcher state machine. No AppKit — fully unit-testable.
        .target(
            name: "AltTabCore",
            path: "Sources/AltTabCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // GUI executable: global hotkey, window enumeration (CG + AX),
        // thumbnail capture, overlay panel UI.
        .executableTarget(
            name: "AltTab",
            dependencies: ["AltTabCore"],
            path: "Sources/AltTab",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Test runner executable. This CLT-only machine ships neither a
        // usable XCTest nor a runnable swift-testing integration, so TDD runs
        // on a small in-repo harness driven by `swift run alttab-tests`.
        .executableTarget(
            name: "AltTabTests",
            dependencies: ["AltTabCore"],
            path: "Tests/AltTabTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
