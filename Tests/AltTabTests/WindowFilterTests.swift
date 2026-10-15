import Foundation
import AltTabCore

/// Helpers to build raw window descriptors concisely in tests.
func raw(
    id: UInt32,
    pid: Int32 = 100,
    owner: String = "Safari",
    title: String = "Page",
    layer: Int = 0,
    bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
    onscreen: Bool = true,
    minimized: Bool = false,
    policy: AppPolicy = .regular,
    isSelf: Bool = false
) -> RawWindowInfo {
    RawWindowInfo(
        windowID: id,
        ownerPID: pid,
        ownerName: owner,
        title: title,
        layer: layer,
        bounds: bounds,
        isOnscreen: onscreen,
        minimized: minimized,
        ownerPolicy: policy,
        isSelf: isSelf
    )
}

let windowFilterTests = TestSuite("WindowFilter") { suite in
    // MARK: - keeps

    suite.test("keeps normal windows") {
        let result = WindowFilter.windows(from: [
            raw(id: 1, pid: 50, owner: "Finder", title: "Downloads"),
            raw(id: 2, pid: 51, owner: "Safari", title: "Wikipedia"),
        ])
        try expectEqual(result.map(\.id), [1, 2])
        try expectEqual(result[0].appName, "Finder")
        try expectEqual(result[0].title, "Downloads")
        try expectEqual(result[0].ownerPID, 50)
        try expectEqual(result[0].frame, CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    suite.test("keeps minimized windows") {
        let result = WindowFilter.windows(from: [raw(id: 1, minimized: true)])
        try expectEqual(result.map(\.id), [1])
        try expect(result[0].minimized)
    }

    suite.test("keeps untitled windows when they have bounds") {
        let result = WindowFilter.windows(from: [raw(id: 1, title: "")])
        try expectEqual(result.map(\.id), [1])
    }

    // MARK: - drops

    suite.test("drops windows not on layer zero") {
        let result = WindowFilter.windows(from: [
            raw(id: 1, layer: 25), // Dock
            raw(id: 2, layer: 3),  // menu bar
            raw(id: 3, layer: -1),
            raw(id: 4),            // normal layer 0
        ])
        try expectEqual(result.map(\.id), [4])
    }

    suite.test("drops non-regular apps") {
        let result = WindowFilter.windows(from: [
            raw(id: 1, policy: .accessory),
            raw(id: 2, policy: .prohibited),
            raw(id: 3, policy: .regular),
        ])
        try expectEqual(result.map(\.id), [3])
    }

    suite.test("drops own windows") {
        let result = WindowFilter.windows(from: [
            raw(id: 1, isSelf: true),
            raw(id: 2),
        ])
        try expectEqual(result.map(\.id), [2])
    }

    suite.test("drops windows without title and without bounds") {
        let result = WindowFilter.windows(from: [
            raw(id: 1, title: "", bounds: .zero),
            raw(id: 2, title: "", bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            raw(id: 3, title: "t", bounds: .zero), // titled but no bounds: keep (e.g. minimized)
        ])
        try expectEqual(result.map(\.id), [2, 3])
    }

    // MARK: - dedup

    suite.test("deduplicates by window id") {
        let result = WindowFilter.windows(from: [
            raw(id: 7, title: "first"),
            raw(id: 8),
            raw(id: 7, title: "duplicate"),
        ])
        try expectEqual(result.map(\.id), [7, 8])
        try expectEqual(result[0].title, "first")
    }

    suite.test("empty input yields empty output") {
        try expectEqual(WindowFilter.windows(from: []), [])
    }
}
