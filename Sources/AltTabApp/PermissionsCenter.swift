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
        // The official TCC check (10.15+). The old title-probing heuristic
        // this replaced could not distinguish "denied" from "no window on
        // screen happens to have a title".
        CGPreflightScreenCaptureAccess()
    }

    /// Guide the user once per launch toward whatever is missing. A working
    /// hotkey implies Accessibility; without Screen Recording the switcher
    /// can only show app icons, so that grant is worth asking for too.
    public func promptIfMissing() {
        if !hasAccessibility {
            requestAccessibility()
        } else if !hasScreenRecording {
            requestScreenRecording()
        }
    }

    private func requestAccessibility() {
        // Passing the prompt option makes macOS show its own grant dialog.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestScreenRecording() {
        // CGRequestScreenCaptureAccess registers the app with TCC and shows
        // the system prompt while the state is undetermined. Without this
        // call a fresh install never appears in the Screen Recording list
        // the guidance below points at, leaving nothing to toggle. It is
        // synchronous while the system dialog is up, so run it off-main;
        // it returns false when already denied (remembered) or just now.
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                guard !granted else { return }
                self.showAlert(
                    title: "需要「屏幕录制」权限",
                    message: "AltTab 需要屏幕录制权限来截取窗口缩略图与读取窗口标题。\n请在系统设置中勾选 AltTab 后重启应用。不授权仍可切换窗口，但没有缩略图。"
                )
                self.openSettings(pane: "Privacy_ScreenCapture")
            }
        }
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
