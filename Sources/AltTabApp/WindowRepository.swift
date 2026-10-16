import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import AltTabCore

/// Bridges the system's window APIs into the pure core models.
///
/// Enumeration merges two sources:
///  - `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` — z-order, layers,
///    bounds, fallback titles of *visible* windows;
///  - the Accessibility API per running app — full window list including
///    minimized windows, reliable titles, and the AX refs needed to focus.
///
/// Windows are keyed by their CG window id, obtained from AX elements via
/// the `_AXUIElementGetWindow` private symbol (same approach as
/// alt-tab-macos). AX elements that don't yield an id are skipped.
public final class WindowRepository {
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    /// AX refs of the windows found by the last `enumerate()` pass,
    /// keyed by CG window id — used later to focus them.
    private var axWindowsByID: [UInt32: AXUIElement] = [:]

    private let getWindowID: (AXUIElement) -> UInt32?

    public init() {
        if let handle = dlopen(nil, RTLD_LAZY),
           let symbol = dlsym(handle, "_AXUIElementGetWindow") {
            let fn = unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError).self)
            getWindowID = { element in
                var id: UInt32 = 0
                return fn(element, &id) == .success ? id : nil
            }
        } else {
            // Private symbol unavailable (removed?) — enumeration still works
            // for windows visible in the CG list; minimized ones drop out.
            getWindowID = { _ in nil }
        }
    }

    // MARK: - Enumeration

    /// Snapshot of everything switchable right now.
    /// True when the Accessibility permission is granted. Without it AX
    /// enumeration returns nothing, so callers keep their previous data
    /// instead of wiping the switcher on every poll.
    public var isAXAvailable: Bool {
        AXIsProcessTrusted()
    }

    public func enumerate() -> (living: [WindowModel], visibleFrontToBack: [WindowModel]) {
        var cgByID: [UInt32: (layer: Int, bounds: CGRect, title: String)] = [:]
        var cgOrder: [UInt32] = []

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard
                    let id = entry[kCGWindowNumber as String] as? UInt32,
                    let pid = entry[kCGWindowOwnerPID as String] as? Int32
                else { continue }
                let layer = entry[kCGWindowLayer as String] as? Int ?? 0
                let title = entry[kCGWindowName as String] as? String ?? ""
                let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
                cgByID[id] = (layer, bounds, title)
                cgOrder.append(id)
                _ = pid // kept for future per-app filtering from CG side
            }
        }

        var appsByPID: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appsByPID[app.processIdentifier] = app
        }

        var raws: [RawWindowInfo] = []
        axWindowsByID.removeAll(keepingCapacity: true)

        for (pid, app) in appsByPID where app.activationPolicy == .regular && pid != selfPID {
            let policy: AppPolicy
            switch app.activationPolicy {
            case .regular: policy = .regular
            case .accessory: policy = .accessory
            case .prohibited: policy = .prohibited
            @unknown default: policy = .prohibited
            }

            let axApp = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement]
            else { continue }

            for axWindow in axWindows {
                guard let id = getWindowID(axWindow) else { continue }
                axWindowsByID[id] = axWindow

                let cg = cgByID[id]
                let axTitle = Self.string(axWindow, kAXTitleAttribute) ?? ""
                let title = !axTitle.isEmpty ? axTitle : (cg?.title ?? "")
                let minimized = Self.bool(axWindow, kAXMinimizedAttribute) ?? false
                // AX rects arrive only for windows missing from the CG list
                // (minimized, other Spaces) — convert their coordinate space
                // so `bounds` always matches CG's top-left-origin globals.
                let axBounds = Self.rect(axWindow).map(Self.toCGGlobal)
                let bounds = minimized
                    ? (axBounds ?? cg?.bounds ?? .zero)
                    : (cg?.bounds.isEmpty == false ? cg!.bounds : (axBounds ?? .zero))

                raws.append(RawWindowInfo(
                    windowID: id,
                    ownerPID: pid,
                    ownerName: app.localizedName ?? "",
                    title: title,
                    layer: cg?.layer ?? 0,
                    bounds: bounds,
                    isOnscreen: cg != nil,
                    minimized: minimized,
                    ownerPolicy: policy,
                    isSelf: false
                ))
            }
        }

        let living = WindowFilter.windows(from: raws)
        let visibleFrontToBack = cgOrder.compactMap { id in
            living.first { $0.id == id }
        }
        return (living, visibleFrontToBack)
    }

    // MARK: - Focusing

    /// Bring `window` to the front: un-minimize, raise via AX, activate the
    /// owning app, and set it as the app's focused window. The system moves
    /// the window's Space on screen as needed.
    public func focusWindow(_ window: WindowModel) {
        guard let axWindow = axWindowsByID[window.id] ?? rediscoAXWindow(matching: window) else {
            // Window vanished (app quit?) — at least bring its app forward.
            NSRunningApplication(processIdentifier: window.ownerPID)?
                .activate(options: [.activateIgnoringOtherApps])
            return
        }

        if Self.bool(axWindow, kAXMinimizedAttribute) == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)

        if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            app.activate(options: [.activateIgnoringOtherApps])
            let axApp = AXUIElementCreateApplication(window.ownerPID)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, axWindow)
        }
    }

    /// App icon for the switcher cell.
    public func appIcon(pid: Int32) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    // MARK: - Diagnostics

    /// Print what the enumeration pipeline sees; `--verbose` adds per-app
    /// AX results to debug permission problems.
    public static func dumpDiagnostics(verbose: Bool) {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        print("pid: \(selfPID)")
        print("accessibility trusted: \(AXIsProcessTrusted())")

        if let handle = dlopen(nil, RTLD_LAZY),
           dlsym(handle, "_AXUIElementGetWindow") != nil {
            print("_AXUIElementGetWindow: available")
        } else {
            print("_AXUIElementGetWindow: MISSING (minimized windows unsupported)")
        }

        let repository = WindowRepository()
        let snapshot = repository.enumerate()
        print("living windows: \(snapshot.living.count)")
        for window in snapshot.living {
            let state = window.minimized ? " [minimized]" : ""
            print("  [\(window.id)] \(window.appName) — «\(window.title)»\(state)")
        }
        print("visible front-to-back: \(snapshot.visibleFrontToBack.map(\.id))")

        if verbose {
            print("--- per-app AX results ---")
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                var value: CFTypeRef?
                let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
                let count = (value as? [AXUIElement])?.count ?? -1
                print("  \(app.localizedName ?? "?"): err=\(err.rawValue) windows=\(count)")
            }
        }
    }

    // MARK: - Private

    /// AX positions use the AppKit-style global space (origin at the
    /// bottom-left of the main display, y up); CG window bounds use a
    /// top-left origin (y down). Flip so both sources produce rects in
    /// the same space — CG's — which capture APIs also expect.
    private static func toCGGlobal(_ rect: CGRect) -> CGRect {
        let main = CGDisplayBounds(CGMainDisplayID())
        return CGRect(x: rect.minX, y: main.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }

    /// The cached AX ref may be stale (window closed/reopened) — re-enumerate
    /// the app's windows and match by id, falling back to title equality.
    private func rediscoAXWindow(matching window: WindowModel) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(window.ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement]
        else { return nil }

        for axWindow in axWindows {
            if let id = getWindowID(axWindow), id == window.id { return axWindow }
        }
        for axWindow in axWindows {
            if Self.string(axWindow, kAXTitleAttribute) == window.title { return axWindow }
        }
        return nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    /// kAXPositionAttribute + kAXSizeAttribute as a rect.
    private static func rect(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }
}
