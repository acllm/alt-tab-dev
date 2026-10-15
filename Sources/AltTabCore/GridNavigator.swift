import Foundation

/// Which direction the focus moves in the switcher grid.
public enum MoveDirection {
    case left, right, up, down
}

/// Pure math for the adaptive grid layout used by the switcher.
public enum GridLayout {
    /// Number of columns for a given window count: roughly square, capped.
    public static func columns(for count: Int, maxColumns: Int = 7) -> Int {
        guard count > 1 else { return 1 }
        let root = Int(Double(count).squareRoot().rounded(.up))
        return max(1, min(maxColumns, root))
    }

    public static func row(of index: Int, columns: Int) -> Int {
        guard columns > 0 else { return 0 }
        return index / columns
    }

    public static func column(of index: Int, columns: Int) -> Int {
        guard columns > 0 else { return 0 }
        return index % columns
    }
}

/// Tracks the focused cell in the switcher grid.
///
/// Semantics mirror alt-tab-macos / Windows behavior:
///  - horizontal moves wrap around the whole list ends;
///  - vertical moves do not wrap: `up` stops at the first row, `down`
///    clamps onto the last existing cell when the target row is short.
public struct GridNavigator {
    public let count: Int
    public let columns: Int
    public private(set) var index: Int

    public init(count: Int, columns: Int? = nil, startIndex: Int = 0) {
        self.count = count
        self.columns = columns ?? GridLayout.columns(for: count)
        self.index = count > 0 ? min(max(startIndex, 0), count - 1) : 0
    }

    public mutating func move(_ direction: MoveDirection) {
        switch direction {
        case .right:
            next()
        case .left:
            previous()
        case .down:
            let target = index + columns
            if target < count { index = target } else if index < count - 1 { index = count - 1 }
        case .up:
            let target = index - columns
            if target >= 0 { index = target }
        }
    }

    public mutating func next() {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    public mutating func previous() {
        guard count > 0 else { return }
        index = (index - 1 + count) % count
    }
}
