import AppKit
import Foundation
import AltTabCore

/// Automated end-to-end sequence driving the real coordinator/state/panel
/// pipeline with synthetic (CG-sourced) window data. Shared by the AltTabE2E
/// runner and the real app's `--selftest` launch mode.
public enum SelfTest {
    @discardableResult
    public static func shell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Windows from the CG list — available without the AX permission.
    public static func syntheticWindows(limit: Int = 8) -> [WindowModel] {
        var models: [WindowModel] = []
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard
                    let id = entry[kCGWindowNumber as String] as? UInt32,
                    let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                    (entry[kCGWindowLayer as String] as? Int ?? 0) == 0,
                    pid != ProcessInfo.processInfo.processIdentifier
                else { continue }
                let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
                let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
                guard !bounds.isEmpty else { continue }
                models.append(WindowModel(
                    id: id, ownerPID: pid, appName: owner,
                    title: "\(owner) 窗口", minimized: false, frame: bounds
                ))
                if models.count >= limit { break }
            }
        }
        return models
    }

    /// Drops a marker file so an outer verifier (with screen-recording
    /// permission) can capture the screen at exactly this step.
    private static func signal(_ dir: String, _ name: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(dir)/\(name)", contents: nil)
    }

    /// Schedules the show → tab → arrow → escape sequence, screenshotting
    /// each step into `dir`. The process must keep its run loop alive (the
    /// sequence terminates it via exit()).
    public static func run(coordinator: AppCoordinator, panel: SwitcherPanel, dir: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            coordinator.start() // event tap fails without TCC; everything else runs
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let fake = syntheticWindows()
            guard fake.count >= 2 else {
                print("E2E-UI: FAIL — no CG windows available")
                exit(1)
            }
            print("E2E-UI: synthetic window set: \(fake.map(\.appName))")

            coordinator.apply(coordinator.state.send(.windowsChanged(living: fake, visibleFrontToBack: fake)))
            coordinator.apply(coordinator.state.send(.hotkeyTriggered))

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                print("E2E-UI: panel frame=\(panel.frame) onScreen=\(panel.isVisible) occlusionVisible=\(panel.occlusionState.contains(.visible)) windowNumber=\(panel.windowNumber)")
                try? """
                panel.frame = \(panel.frame)
                panel.screen = \(String(describing: panel.screen?.frame))
                panel.windowNumber = \(panel.windowNumber)
                panel.occlusion = \(panel.occlusionState)
                panel.alphaValue = \(panel.alphaValue)
                panel.contentView frame = \(String(describing: panel.contentView?.frame))
                NSScreen.main = \(String(describing: NSScreen.main?.frame))
                NSScreen.screens = \(NSScreen.screens.map(\.frame))
                app policy = \(NSApp.activationPolicy().rawValue)
                app isActive = \(NSApp.isActive)
                """.write(toFile: "\(dir)/diag.txt", atomically: true, encoding: .utf8)
                signal(dir, "step1")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coordinator.apply(coordinator.state.send(.tabPressed(shift: false)))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("E2E-UI: shot2 (focus advanced)")
                        signal(dir, "step2")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            coordinator.apply(coordinator.state.send(.arrowPressed(.right)))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                signal(dir, "step3")

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    coordinator.apply(coordinator.state.send(.escapePressed))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        let hidden = !coordinator.state.isVisible
                                        signal(dir, "step4")
                                        print("E2E-UI: shot4 (hidden=\(hidden))")
                                        signal(dir, "done")
                                        let pass = hidden && panel.frame.width > 500
                                        print(pass ? "E2E-UI: PASS" : "E2E-UI: FAIL")
                                        exit(pass ? 0 : 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Only scheduled async work from here on; caller keeps the run loop.
    }
}
