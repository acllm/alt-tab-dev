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
        // Without the permission CGWindowListCreateImage degrades silently:
        // it still returns an image, but composited from the current screen
        // (occluded windows are unreadable). The reliable signal is the CG
        // window list: other apps' window *titles* are stripped without the
        // grant. If any other app shows a title, the permission is on.
        let option: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for entry in list {
            guard
                let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                pid != selfPID,
                (entry[kCGWindowLayer as String] as? Int ?? 0) == 0
            else { continue }
            if let title = entry[kCGWindowName as String] as? String, !title.isEmpty {
                return true
            }
        }
        // Saw other apps' windows but none with a title: treat as denied.
        return list.contains { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32 else { return false }
            return pid != selfPID && (entry[kCGWindowLayer as String] as? Int ?? 0) == 0
        } == false
    }

    public func promptIfMissing() {
        if !hasAccessibility {
            requestAccessibility()
        }
        // The screen-recording alert is advisory (the app degrades to
        // icon-only thumbnails without it) — nagging on every launch is
        // worse than the missing feature. Show it once, ever.
        if !hasScreenRecording {
            let defaultsKey = "didPromptScreenRecording"
            if !UserDefaults.standard.bool(forKey: defaultsKey) {
                UserDefaults.standard.set(true, forKey: defaultsKey)
                requestScreenRecording()
            }
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
