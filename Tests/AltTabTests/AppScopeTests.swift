import Foundation
import AltTabCore

let appScopeTests = TestSuite("SwitcherState.appScope") { suite in
    // Seed: two apps. pid 10 owns w1,w2,w3; pid 20 owns w4,w5.
    func makeState() -> SwitcherState {
        let state = SwitcherState(windows: [
            win(1, "w1-pid10", minimized: false),
            win(2, "w2-pid10", minimized: false),
            win(3, "w3-pid10", minimized: true),
            win(4, "w4-pid20", minimized: false),
            win(5, "w5-pid20", minimized: false),
        ])
        // re-seed with correct pids
        return SwitcherState(windows: [
            WindowModel(id: 1, ownerPID: 10, appName: "A", title: "w1", minimized: false, frame: .zero),
            WindowModel(id: 2, ownerPID: 10, appName: "A", title: "w2", minimized: false, frame: .zero),
            WindowModel(id: 3, ownerPID: 10, appName: "A", title: "w3", minimized: true, frame: .zero),
            WindowModel(id: 4, ownerPID: 20, appName: "B", title: "w4", minimized: false, frame: .zero),
            WindowModel(id: 5, ownerPID: 20, appName: "B", title: "w5", minimized: false, frame: .zero),
        ])
    }

    suite.test("app-windows hotkey shows only that app's windows") {
        let state = makeState()
        let effects = state.send(.appWindowsHotkeyTriggered(pid: 10))
        guard case let .show(windows, focusIndex)? = effects.first else {
            try expect(false, "expected .show effect, got \(effects)")
            return
        }
        try expectEqual(windows.map(\.id), [1, 2, 3]) // includes minimized
        try expectEqual(focusIndex, 1)
    }

    suite.test("app-windows hotkey with single window focuses it") {
        let state = makeState()
        let effects = state.send(.appWindowsHotkeyTriggered(pid: 20))
        guard case let .show(windows, focusIndex)? = effects.first else {
            try expect(false, "expected .show effect")
            return
        }
        try expectEqual(windows.map(\.id), [4, 5])
        try expectEqual(focusIndex, 1)
    }

    suite.test("tab cycles within the filtered list") {
        let state = makeState()
        _ = state.send(.appWindowsHotkeyTriggered(pid: 10))
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(2)])
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(0)])
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(1)])
    }

    suite.test("commit focuses a filtered window and resets scope") {
        let state = makeState()
        _ = state.send(.appWindowsHotkeyTriggered(pid: 10))
        _ = state.send(.tabPressed(shift: false)) // focus: w2 -> w3
        let effects = state.send(.enterPressed)
        guard case let .focusWindow(target)? = effects.first else {
            try expect(false, "expected .focusWindow")
            return
        }
        try expectEqual(target.id, 3)
        try expect(!state.isVisible)
        // after hide, the visible list is the full window set again
        try expectEqual(state.windows.count, 5)
    }

    suite.test("releasing shortcut commits from filtered list") {
        let state = makeState()
        _ = state.send(.appWindowsHotkeyTriggered(pid: 20))
        let effects = state.send(.shortcutReleased)
        guard case let .focusWindow(target)? = effects.first else {
            try expect(false, "expected .focusWindow")
            return
        }
        try expectEqual(target.id, 5)
    }

    suite.test("same-scope trigger again advances focus") {
        let state = makeState()
        _ = state.send(.appWindowsHotkeyTriggered(pid: 10)) // focus 1
        try expectEqual(state.send(.appWindowsHotkeyTriggered(pid: 10)), [.updateFocus(2)])
    }

    suite.test("switching scopes while shown reshow with the new scope") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered) // all windows, focus 1
        let effects = state.send(.appWindowsHotkeyTriggered(pid: 10))
        guard case let .show(windows, focusIndex)? = effects.first else {
            try expect(false, "expected .show")
            return
        }
        try expectEqual(windows.map(\.id), [1, 2, 3])
        try expectEqual(focusIndex, 1)
    }

    suite.test("all-windows hotkey after app scope restores full list") {
        let state = makeState()
        _ = state.send(.appWindowsHotkeyTriggered(pid: 10))
        let effects = state.send(.hotkeyTriggered)
        guard case let .show(windows, focusIndex)? = effects.first else {
            try expect(false, "expected .show")
            return
        }
        try expectEqual(windows.map(\.id), [1, 2, 3, 4, 5])
        try expectEqual(focusIndex, 1)
    }

    suite.test("windows changed keeps the app scope filter") {
        let state = makeState()
        _ = state.send(.appWindowsHotkeyTriggered(pid: 10))
        let effects = state.send(.windowsChanged(
            living: [
                WindowModel(id: 1, ownerPID: 10, appName: "A", title: "w1", minimized: false, frame: .zero),
                WindowModel(id: 2, ownerPID: 10, appName: "A", title: "w2", minimized: false, frame: .zero),
                WindowModel(id: 4, ownerPID: 20, appName: "B", title: "w4", minimized: false, frame: .zero),
            ],
            visibleFrontToBack: [
                WindowModel(id: 1, ownerPID: 10, appName: "A", title: "w1", minimized: false, frame: .zero),
                WindowModel(id: 4, ownerPID: 20, appName: "B", title: "w4", minimized: false, frame: .zero),
            ]
        ))
        guard case let .reload(windows, focusIndex)? = effects.first else {
            try expect(false, "expected .reload, got \(effects)")
            return
        }
        try expectEqual(windows.map(\.id), [1, 2])
        try expect(focusIndex < 2)
    }

    suite.test("app with no living windows shows nothing") {
        let state = makeState()
        try expect(state.send(.appWindowsHotkeyTriggered(pid: 99)).isEmpty)
        try expect(!state.isVisible)
    }
}
