import AppKit
import CoreGraphics
import Foundation
import AltTabCore

/// Keyboard events the switcher cares about, already translated from raw
/// key codes so the coordinator stays declarative.
public enum HotkeyEvent {
    /// ⌥+Tab pressed (the show/advance shortcut).
    case hotkey
    /// Tab (or ⇧+Tab) pressed without the shortcut modifier.
    case tab(shift: Bool)
    case arrow(MoveDirection)
    case enter
    case escape
    /// The ⌥ modifier was released (commits the selection).
    case shortcutRelease
}

/// Global keyboard listener built on a CG session event tap.
///
/// The handler returns `true` for events the app consumed — those are
/// swallowed so the system never sees them (no beep, no focus change).
/// ⌥ press/release is tracked via flags-changed so the switcher can commit
/// on modifier release, Windows-style.
public final class HotkeyEventTap {
    public typealias Handler = (HotkeyEvent) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionHeld = false

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Returns false when the Accessibility permission is missing.
    public func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let eventTap = Unmanaged<HotkeyEventTap>.fromOpaque(info).takeUnretainedValue()
                if let result = eventTap.handle(type: type, event: event) {
                    return Unmanaged.passUnretained(result)
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DiagLog.log("event tap: CREATE FAILED (accessibility not granted?)")
            return false
        }

        self.tap = tap
        if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagLog.log("event tap: STARTED ok")
        return true
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }

    /// Returns the event to pass through to the system, or nil to swallow.
    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByUserInput, .tapDisabledByTimeout:
            // Timeouts can disable the tap; re-arm instead of going deaf.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event

        case .flagsChanged:
            let optionNow = event.flags.contains(.maskAlternate)
            if optionHeld && !optionNow {
                optionHeld = false
                _ = handler(.shortcutRelease)
            } else if optionNow {
                optionHeld = true
            }
            return event

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let translated: HotkeyEvent?
            switch keyCode {
            case 48: // Tab
                translated = optionHeld
                    ? .hotkey
                    : .tab(shift: event.flags.contains(.maskShift))
            case 123: translated = .arrow(.left)
            case 124: translated = .arrow(.right)
            case 125: translated = .arrow(.down)
            case 126: translated = .arrow(.up)
            case 36, 76: translated = .enter
            // Escape is deliberately not intercepted: per product decision the
            // switcher has no cancel-on-escape behavior, and the key should
            // pass through to whatever would otherwise receive it.
            default: translated = nil
            }
            if let translated, handler(translated) {
                return nil
            }
            return event

        default:
            return event
        }
    }
}
