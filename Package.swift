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
        .testTarget(
            name: "AltTabCoreTests",
            dependencies: ["AltTabCore"],
            path: "Tests/AltTabCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
