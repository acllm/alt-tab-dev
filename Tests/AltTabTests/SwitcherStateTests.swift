import Foundation
import AltTabCore

let switcherStateTests = TestSuite("SwitcherState") { suite in
    // 4 windows: ids happen to be MRU order at seed time (1 = most recent)
    func makeState(seed: [UInt32] = [1, 2, 3, 4]) -> SwitcherState {
        SwitcherState(windows: seed.map { win($0, "w\($0)") })
    }

    // MARK: - showing

    suite.test("hotkey shows the switcher focused on the previously used window") {
        let state = makeState()
        let effects = state.send(.hotkeyTriggered)
        try expectEqual(effects, [.show(state.windows, focusIndex: 1)])
    }

    suite.test("hotkey with a single window focuses it") {
        let state = makeState(seed: [7])
        let effects = state.send(.hotkeyTriggered)
        try expectEqual(effects, [.show(state.windows, focusIndex: 0)])
    }

    suite.test("hotkey with no windows does nothing") {
        let state = makeState(seed: [])
        try expect(state.send(.hotkeyTriggered).isEmpty)
    }

    suite.test("hotkey while shown advances focus") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        let effects = state.send(.hotkeyTriggered)
        try expectEqual(effects, [.updateFocus(2)])
    }

    // MARK: - navigating

    suite.test("tab cycles focus forward") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(2)])
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(3)])
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(0)])
        try expectEqual(state.send(.tabPressed(shift: false)), [.updateFocus(1)])
    }

    suite.test("shift-tab cycles focus backward") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        try expectEqual(state.send(.tabPressed(shift: true)), [.updateFocus(0)])
        try expectEqual(state.send(.tabPressed(shift: true)), [.updateFocus(3)])
    }

    suite.test("arrow keys move focus") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        try expectEqual(state.send(.arrowPressed(.down)), [.updateFocus(3)])
        try expectEqual(state.send(.arrowPressed(.up)), [.updateFocus(1)])
    }

    // MARK: - committing

    suite.test("enter commits the focused window and hides") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        _ = state.send(.tabPressed(shift: false)) // focus -> 2
        let effects = state.send(.enterPressed)
        try expectEqual(effects, [.focusWindow(win(3, "w3")), .hide])
        try expect(!state.isVisible)
    }

    suite.test("releasing the shortcut commits like enter") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        let effects = state.send(.shortcutReleased)
        try expectEqual(effects, [.focusWindow(win(2, "w2")), .hide])
    }

    suite.test("commit moves the window to the front of MRU") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        _ = state.send(.tabPressed(shift: false)) // focus -> 2 (id 3)
        _ = state.send(.enterPressed)
        try expectEqual(state.windows.map(\.id), [3, 1, 2, 4])
    }

    suite.test("escape hides without focusing anything") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        try expectEqual(state.send(.escapePressed), [.hide])
        try expect(!state.isVisible)
    }

    suite.test("after hiding, hotkey shows again focused on the new MRU second") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        _ = state.send(.enterPressed) // focused id 2
        let effects = state.send(.hotkeyTriggered)
        try expectEqual(effects, [.show(state.windows, focusIndex: 1)])
        try expectEqual(state.windows.map(\.id), [2, 1, 3, 4])
    }

    // MARK: - live window set changes

    suite.test("windows changed while shown reloads and clamps focus") {
        let state = makeState() // [1,2,3,4]
        _ = state.send(.hotkeyTriggered)
        _ = state.send(.tabPressed(shift: false)) // focus -> 2
        // windows 3 and 4 close: focus index 2 no longer valid
        let effects = state.send(.windowsChanged(
            living: [win(1, "w1"), win(2, "w2")],
            visibleFrontToBack: [win(2, "w2"), win(1, "w1")]
        ))
        try expectEqual(effects, [.reload([win(2, "w2"), win(1, "w1")], focusIndex: 1)])
        try expect(state.isVisible)
    }

    suite.test("windows changed while shown inserts a new frontmost window") {
        let state = makeState()
        _ = state.send(.hotkeyTriggered)
        let effects = state.send(.windowsChanged(
            living: [win(1, "w1"), win(2, "w2"), win(3, "w3"), win(4, "w4"), win(9, "w9")],
            visibleFrontToBack: [win(9, "w9"), win(1, "w1"), win(2, "w2"), win(3, "w3"), win(4, "w4")]
        ))
        try expectEqual(effects, [.reload([9, 1, 2, 3, 4].map { win($0, "w\($0)") }, focusIndex: 2)])
    }

    suite.test("windows changed while hidden only updates the list") {
        let state = makeState()
        let effects = state.send(.windowsChanged(
            living: [win(1, "w1")],
            visibleFrontToBack: [win(1, "w1")]
        ))
        try expect(effects.isEmpty)
        try expectEqual(state.windows.map(\.id), [1])
    }

    suite.test("input while hidden produces no effects") {
        let state = makeState()
        try expect(state.send(.tabPressed(shift: false)).isEmpty)
        try expect(state.send(.arrowPressed(.left)).isEmpty)
        try expect(state.send(.enterPressed).isEmpty)
        try expect(state.send(.escapePressed).isEmpty)
    }
}
