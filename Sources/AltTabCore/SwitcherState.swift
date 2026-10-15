import Foundation

/// What the UI layer should do in response to a switcher event.
public enum SwitcherEffect: Equatable {
    /// Present the overlay with this window list, focusing this index.
    case show([WindowModel], focusIndex: Int)
    /// The window list changed while shown; redisplay and refocus.
    case reload([WindowModel], focusIndex: Int)
    /// Move the focus ring.
    case updateFocus(Int)
    /// Focus this window in the system and hide the overlay.
    case focusWindow(WindowModel)
    /// Hide the overlay without focusing anything.
    case hide
}

/// Events fed in from the global hotkey / system observers.
public enum SwitcherEvent {
    /// The show shortcut fired (modifier held + trigger key pressed).
    case hotkeyTriggered
    /// The app-windows shortcut fired (⌥+`): switch only between windows of
    /// the app with this pid.
    case appWindowsHotkeyTriggered(pid: Int32)
    /// Tab (or shift-tab) pressed while shown.
    case tabPressed(shift: Bool)
    /// An arrow key pressed while shown.
    case arrowPressed(MoveDirection)
    /// Enter pressed while shown.
    case enterPressed
    /// The held shortcut modifier was released.
    case shortcutReleased
    /// Escape pressed while shown.
    case escapePressed
    /// The system window set changed: `living` is everything that exists
    /// (visible + minimized), `visibleFrontToBack` is the z-order snapshot.
    case windowsChanged(living: [WindowModel], visibleFrontToBack: [WindowModel])
}

/// The heart of the switcher: translates events into effects.
///
/// Mirrors alt-tab-macos behavior: opening the switcher focuses the
/// previously-used window (MRU index 1), tab/arrows move the focus ring,
/// releasing the shortcut or pressing enter commits, escape cancels. While
/// shown, the focus ring follows the *window* across list changes, not the
/// list position.
public final class SwitcherState {
    public private(set) var isVisible: Bool = false

    private enum Scope: Equatable {
        case allWindows
        case appWindows(pid: Int32)
    }
    private var scope: Scope = .allWindows

    private let mru: MruWindowList
    private var navigator = GridNavigator(count: 0)

    public init(windows: [WindowModel] = []) {
        mru = MruWindowList(seed: windows)
    }

    /// The list the switcher currently displays: the MRU list, filtered to
    /// the active scope (all windows, or one app's windows for ⌥+`).
    public var windows: [WindowModel] {
        switch scope {
        case .allWindows:
            return mru.windows
        case .appWindows(let pid):
            return mru.windows.filter { $0.ownerPID == pid }
        }
    }

    private func displayWindow(at index: Int) -> WindowModel? {
        let display = windows
        guard display.indices.contains(index) else { return nil }
        return display[index]
    }

    public func send(_ event: SwitcherEvent) -> [SwitcherEffect] {
        switch event {
        case .appWindowsHotkeyTriggered(let pid):
            if isVisible, scope == .appWindows(pid: pid) {
                navigator.next()
                return [.updateFocus(navigator.index)]
            }
            scope = .appWindows(pid: pid)
            return show()

        case .hotkeyTriggered:
            if isVisible, scope == .allWindows {
                navigator.next()
                return [.updateFocus(navigator.index)]
            }
            scope = .allWindows
            return show()

        case .tabPressed(let shift):
            guard isVisible else { return [] }
            if shift { navigator.previous() } else { navigator.next() }
            return [.updateFocus(navigator.index)]

        case .arrowPressed(let direction):
            guard isVisible else { return [] }
            navigator.move(direction)
            return [.updateFocus(navigator.index)]

        case .enterPressed, .shortcutReleased:
            return commit()

        case .escapePressed:
            guard isVisible else { return [] }
            isVisible = false
            scope = .allWindows
            return [.hide]

        case .windowsChanged(let living, let visibleFrontToBack):
            let focusedID = isVisible ? displayWindow(at: navigator.index)?.id : nil
            mru.reconcile(living: living)
            mru.applySnapshot(frontToBack: visibleFrontToBack)
            guard isVisible else { return [] }
            // Keep the focus ring on the same window when it survives the
            // change; otherwise clamp the old index into the new bounds.
            let display = windows
            let fallback = min(navigator.index, max(0, display.count - 1))
            let start = focusedID.flatMap { id in display.firstIndex(where: { $0.id == id }) } ?? fallback
            navigator = GridNavigator(count: display.count, startIndex: start)
            return [.reload(display, focusIndex: navigator.index)]
        }
    }

    private func show() -> [SwitcherEffect] {
        let display = windows
        guard !display.isEmpty else { return [] }
        navigator = GridNavigator(count: display.count, startIndex: min(1, display.count - 1))
        isVisible = true
        return [.show(display, focusIndex: navigator.index)]
    }

    private func commit() -> [SwitcherEffect] {
        guard isVisible, let target = displayWindow(at: navigator.index) else { return [] }
        isVisible = false
        scope = .allWindows
        mru.focus(id: target.id)
        return [.focusWindow(target), .hide]
    }
}
