import AppKit
import AltTabCore
import AltTabApp

// Diagnostic mode: enumerate switchable windows and exit. Useful to verify
// the CG+AX pipeline and permissions without the GUI:
//   AltTab --dump
if CommandLine.arguments.contains("--dump") {
    let verbose = CommandLine.arguments.contains("--verbose")
    WindowRepository.dumpDiagnostics(verbose: verbose)
    exit(0)
}

// Self-test mode: launchd/`open` context, drives the full pipeline with
// synthetic data and screenshots each step. Used by Scripts/verify-app.sh
// to verify the shipped bundle end-to-end:
//   open "build/AltTab Dev.app" --args --selftest
if CommandLine.arguments.contains("--selftest") {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let repository = WindowRepository()
    let thumbnails = ThumbnailProvider(repository: repository)
    let panel = SwitcherPanel()
    let coordinator = AppCoordinator(
        state: SwitcherState(),
        repository: repository,
        panel: panel,
        thumbnails: thumbnails
    )
    SelfTest.run(coordinator: coordinator, panel: panel, dir: "/tmp/alttab-e2e")
    app.run()
}

// Entry point: a faceless (accessory) background app. The only UI surfaces
// are the switcher overlay and a small status bar menu.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
