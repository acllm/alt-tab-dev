import Foundation
import AltTabCore

func win(_ id: UInt32, _ title: String = "t", minimized: Bool = false) -> WindowModel {
    WindowModel(
        id: id,
        ownerPID: 100,
        appName: "Safari",
        title: title,
        minimized: minimized,
        frame: CGRect(x: 0, y: 0, width: 100, height: 100)
    )
}

let mruWindowListTests = TestSuite("MruWindowList") { suite in
    suite.test("seed order is preserved, front = most recent") {
        let list = MruWindowList(seed: [win(1), win(2), win(3)])
        try expectEqual(list.windows.map(\.id), [1, 2, 3])
    }

    suite.test("focus moves a window to the front") {
        let list = MruWindowList(seed: [win(1), win(2), win(3), win(4)])
        list.focus(id: 3)
        try expectEqual(list.windows.map(\.id), [3, 1, 2, 4])
    }

    suite.test("focus on the front window keeps order") {
        let list = MruWindowList(seed: [win(1), win(2)])
        list.focus(id: 1)
        try expectEqual(list.windows.map(\.id), [1, 2])
    }

    suite.test("focus on unknown id is a no-op") {
        let list = MruWindowList(seed: [win(1), win(2)])
        list.focus(id: 99)
        try expectEqual(list.windows.map(\.id), [1, 2])
    }

    suite.test("focus twice in a row keeps single entry at front") {
        let list = MruWindowList(seed: [win(1), win(2), win(3)])
        list.focus(id: 2)
        list.focus(id: 2)
        try expectEqual(list.windows.map(\.id), [2, 1, 3])
    }

    suite.test("applySnapshot reorders visible windows by z-order") {
        let list = MruWindowList(seed: [win(1), win(2), win(3)])
        // window 3 now frontmost, then 1, then 2
        list.applySnapshot(frontToBack: [win(3), win(1), win(2)])
        try expectEqual(list.windows.map(\.id), [3, 1, 2])
    }

    suite.test("applySnapshot keeps non-visible windows at the end in previous order") {
        let list = MruWindowList(seed: [win(1), win(2), win(3, minimized: true), win(4, minimized: true)])
        list.applySnapshot(frontToBack: [win(2), win(1)]) // only 1 and 2 visible
        try expectEqual(list.windows.map(\.id), [2, 1, 3, 4])
    }

    suite.test("applySnapshot inserts newly visible windows at their z-position") {
        let list = MruWindowList(seed: [win(1), win(2)])
        // window 5 appeared on top, window 2 is now behind it
        list.applySnapshot(frontToBack: [win(5), win(2), win(1)])
        try expectEqual(list.windows.map(\.id), [5, 2, 1])
    }

    suite.test("applySnapshot with partial snapshot does not drop missing windows") {
        let list = MruWindowList(seed: [win(1), win(2), win(3)])
        list.applySnapshot(frontToBack: [win(2)])
        try expectEqual(list.windows.map(\.id), [2, 1, 3])
    }

    suite.test("reconcile drops closed windows and adds new ones at the back") {
        let list = MruWindowList(seed: [win(1), win(2), win(3)])
        // 3 closed, 4 opened (not yet visible in any snapshot)
        list.reconcile(living: [win(1), win(2), win(4)])
        try expectEqual(list.windows.map(\.id), [1, 2, 4])
    }

    suite.test("reconcile with empty living clears the list") {
        let list = MruWindowList(seed: [win(1), win(2)])
        list.reconcile(living: [])
        try expect(list.windows.isEmpty)
    }

    suite.test("window(at:) and indexOf(id:) accessors") {
        let list = MruWindowList(seed: [win(1, "a"), win(2, "b")])
        try expectEqual(list.window(at: 1)?.title, "b")
        try expect(list.window(at: 5) == nil)
        try expectEqual(list.indexOf(id: 2), 1)
        try expect(list.indexOf(id: 99) == nil)
    }
}
