import AppKit
import Foundation
import AltTabCore

/// Wires everything together: global hotkey events and a window-set poller
/// feed the pure `SwitcherState`; its effects drive the overlay panel and
/// the window repository.
public final class AppCoordinator {
    // Internal (not private) so the single-file e2e runner can drive the
    // pipeline directly: Scripts/run-e2e.sh.
    public let state: SwitcherState
    public let repository: WindowRepository
    public let panel: SwitcherPanel
    public let thumbnails: ThumbnailProvider

    private var eventTap: HotkeyEventTap?
    private var pollTimer: Timer?

    public init(state: SwitcherState,
         repository: WindowRepository,
         panel: SwitcherPanel,
         thumbnails: ThumbnailProvider) {
        self.state = state
        self.repository = repository
        self.panel = panel
        self.thumbnails = thumbnails
        panel.visuals = thumbnails
    }

    public func start() {
        refreshWindows()

        eventTap = HotkeyEventTap { [weak self] event in
            self?.handleHotkey(event) ?? false
        }
        _ = eventTap?.start()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshWindows()
        }
    }

    // MARK: - Event plumbing

    /// Returns true when the key event was consumed and must not reach the
    /// system. The show shortcut is always consumed; navigation keys are
    /// consumed only while the switcher is on screen.
    private func handleHotkey(_ event: HotkeyEvent) -> Bool {
        let wasVisible = state.isVisible
        DiagLog.log("hotkey event: \(event) wasVisible=\(wasVisible)")

        let coreEvent: SwitcherEvent
        var alwaysConsume = false
        switch event {
        case .hotkey:
            coreEvent = .hotkeyTriggered
            alwaysConsume = true
        case .appWindowsHotkey:
            // Frontmost app's windows only (⌥+`). The switcher itself never
            // activates, so frontmost is still the app being used.
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
            coreEvent = .appWindowsHotkeyTriggered(pid: pid)
            alwaysConsume = true
        case .tab(let shift):
            coreEvent = .tabPressed(shift: shift)
        case .arrow(let direction):
            coreEvent = .arrowPressed(direction)
        case .enter:
            coreEvent = .enterPressed
        case .escape:
            coreEvent = .escapePressed
        case .shortcutRelease:
            coreEvent = .shortcutReleased
        }

        apply(state.send(coreEvent))
        DiagLog.log("→ handled: switcher visible=\(state.isVisible)")
        return alwaysConsume || wasVisible
    }

    public func apply(_ effects: [SwitcherEffect]) {
        for effect in effects {
            switch effect {
            case .show(let windows, let focusIndex):
                panel.showSwitcher(windows: windows, focusIndex: focusIndex)
                // Fresh invocation → recapture every window so thumbnails
                // match current content instead of the first-ever capture.
                thumbnails.beginSession()
                loadThumbnails(for: windows)

            case .reload(let windows, let focusIndex):
                panel.reloadSwitcher(windows: windows, focusIndex: focusIndex)
                loadThumbnails(for: windows)

            case .updateFocus(let index):
                panel.setFocus(index)

            case .focusWindow(let window):
                repository.focusWindow(window)

            case .hide:
                panel.hideSwitcher()
            }
        }
    }

    private func loadThumbnails(for windows: [WindowModel]) {
        thumbnails.loadThumbnails(for: windows) { [weak self] _ in
            // A capture landed — repaint whichever cell it belongs to.
            self?.panel.refresh()
        }
    }

    /// Re-enumerate system windows and feed the change into the state
    /// machine (reorders MRU from z-order, picks up new/closed windows).
    /// Without the Accessibility permission enumeration would come back
    /// empty — keep the current list rather than flashing an empty grid.
    private func refreshWindows() {
        guard repository.isAXAvailable else { return }
        let snapshot = repository.enumerate()
        apply(state.send(.windowsChanged(
            living: snapshot.living,
            visibleFrontToBack: snapshot.visibleFrontToBack
        )))
    }
}
