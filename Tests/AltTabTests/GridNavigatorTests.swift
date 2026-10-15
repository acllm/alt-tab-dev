import Foundation
import AltTabCore

let gridNavigatorTests = TestSuite("GridNavigator") { suite in
    // MARK: - columns computation (AltTab-style adaptive grid)

    suite.test("columns: perfect squares use sqrt") {
        try expectEqual(GridLayout.columns(for: 1), 1)
        try expectEqual(GridLayout.columns(for: 4), 2)
        try expectEqual(GridLayout.columns(for: 9), 3)
        try expectEqual(GridLayout.columns(for: 16), 4)
    }

    suite.test("columns: non-perfect squares round up") {
        try expectEqual(GridLayout.columns(for: 2), 2)
        try expectEqual(GridLayout.columns(for: 5), 3)
        try expectEqual(GridLayout.columns(for: 10), 4)
    }

    suite.test("columns: capped at max") {
        try expectEqual(GridLayout.columns(for: 50), 7)
        try expectEqual(GridLayout.columns(for: 100), 7)
    }

    suite.test("columns: at least one for empty grid") {
        try expectEqual(GridLayout.columns(for: 0), 1)
    }

    // MARK: - row/column math

    suite.test("row and column of an index") {
        let columns = 3
        try expectEqual(GridLayout.row(of: 0, columns: columns), 0)
        try expectEqual(GridLayout.row(of: 2, columns: columns), 0)
        try expectEqual(GridLayout.row(of: 3, columns: columns), 1)
        try expectEqual(GridLayout.column(of: 0, columns: columns), 0)
        try expectEqual(GridLayout.column(of: 4, columns: columns), 1)
        try expectEqual(GridLayout.column(of: 8, columns: columns), 2)
    }

    // MARK: - horizontal moves

    suite.test("right moves within a row") {
        var nav = GridNavigator(count: 9, columns: 3, startIndex: 0)
        nav.move(.right)
        try expectEqual(nav.index, 1)
        nav.move(.right)
        try expectEqual(nav.index, 2)
    }

    suite.test("right wraps from the last cell to the first") {
        var nav = GridNavigator(count: 6, columns: 3, startIndex: 5)
        nav.move(.right)
        try expectEqual(nav.index, 0)
    }

    suite.test("right from row end lands on next row head") {
        var nav = GridNavigator(count: 6, columns: 3, startIndex: 2)
        nav.move(.right)
        try expectEqual(nav.index, 3)
    }

    suite.test("left moves within a row") {
        var nav = GridNavigator(count: 9, columns: 3, startIndex: 4)
        nav.move(.left)
        try expectEqual(nav.index, 3)
    }

    suite.test("left wraps from the first cell to the last") {
        var nav = GridNavigator(count: 6, columns: 3, startIndex: 0)
        nav.move(.left)
        try expectEqual(nav.index, 5)
    }

    suite.test("left from row head lands on previous row end") {
        var nav = GridNavigator(count: 6, columns: 3, startIndex: 3)
        nav.move(.left)
        try expectEqual(nav.index, 2)
    }

    // MARK: - vertical moves

    suite.test("down moves one row down, same column") {
        var nav = GridNavigator(count: 9, columns: 3, startIndex: 1)
        nav.move(.down)
        try expectEqual(nav.index, 4)
        nav.move(.down)
        try expectEqual(nav.index, 7)
    }

    suite.test("down on the last row is a no-op") {
        var nav = GridNavigator(count: 9, columns: 3, startIndex: 8)
        nav.move(.down)
        try expectEqual(nav.index, 8)
    }

    suite.test("down onto a shorter partial row clamps to the last cell") {
        // 5 windows in 3 columns: last row holds cells 3 and 4 only
        var nav = GridNavigator(count: 5, columns: 3, startIndex: 4)
        nav.move(.down) // already last valid
        try expectEqual(nav.index, 4)
        nav = GridNavigator(count: 5, columns: 3, startIndex: 3)
        nav.move(.down)
        try expectEqual(nav.index, 4)
    }

    suite.test("up moves one row up, same column") {
        var nav = GridNavigator(count: 9, columns: 3, startIndex: 7)
        nav.move(.up)
        try expectEqual(nav.index, 4)
    }

    suite.test("up on the first row is a no-op") {
        var nav = GridNavigator(count: 9, columns: 3, startIndex: 2)
        nav.move(.up)
        try expectEqual(nav.index, 2)
    }

    // MARK: - tab / shift-tab

    suite.test("next advances with wrap-around") {
        var nav = GridNavigator(count: 3, columns: 3, startIndex: 0)
        nav.next()
        try expectEqual(nav.index, 1)
        nav.next()
        try expectEqual(nav.index, 2)
        nav.next()
        try expectEqual(nav.index, 0)
    }

    suite.test("previous retreats with wrap-around") {
        var nav = GridNavigator(count: 3, columns: 3, startIndex: 0)
        nav.previous()
        try expectEqual(nav.index, 2)
        nav.previous()
        try expectEqual(nav.index, 1)
    }

    // MARK: - degenerate cases

    suite.test("single window grid is stable under any move") {
        var nav = GridNavigator(count: 1, columns: 1, startIndex: 0)
        nav.move(.left); nav.move(.right); nav.move(.up); nav.move(.down)
        nav.next(); nav.previous()
        try expectEqual(nav.index, 0)
    }

    suite.test("empty grid keeps index at zero") {
        var nav = GridNavigator(count: 0, columns: 1, startIndex: 0)
        nav.move(.right); nav.next()
        try expectEqual(nav.index, 0)
    }
}
