import AppKit
import ApplicationServices
import CoreGraphics

/// AltTab needs two TCC permissions to fully work:
///  - Accessibility: global hotkey event tap + AX window control
///  - Screen Recording: window thumbnails and titles via CG window APIs
/// Both degrade gracefully (titles/thumbnails missing, hotkey dead) when
/// not granted. This center checks, prompts, and points the user at the
/// right System Settings pane.
public final class PermissionsCenter {
    public var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    public var hasScreenRecording: Bool {
        // Try to capture a pixel of some other app's window: without the
        // permission CG returns a nil/empty image even when windows exist.
        var windowIDs: [UInt32] = []
        let option: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] {
            let selfPID = ProcessInfo.processInfo.processIdentifier
            windowIDs = list.compactMap { entry in
                guard
                    let id = entry[kCGWindowNumber as String] as? UInt32,
                    let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                    pid != selfPID,
                    (entry[kCGWindowLayer as String] as? Int ?? 0) == 0
                else { return nil }
                return id
            }
        }
        guard let probe = windowIDs.first else { return true } // nothing to probe
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGCompat.windowImage(bounds: bounds, listOption: [], windowID: probe, imageOption: [.nominalResolution]) != nil
    }

    public func promptIfMissing() {
        if !hasAccessibility {
            requestAccessibility()
        }
        if !hasScreenRecording {
            requestScreenRecording()
        }
    }

    private func requestAccessibility() {
        // Passing the prompt option makes macOS show its own grant dialog.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestScreenRecording() {
        showAlert(
            title: "需要「屏幕录制」权限",
            message: "AltTab 需要屏幕录制权限来截取窗口缩略图与读取窗口标题。\n请在系统设置中勾选 AltTab 后重启应用。不授权仍可切换窗口，但没有缩略图。"
        )
        openSettings(pane: "Privacy_ScreenCapture")
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func openSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
