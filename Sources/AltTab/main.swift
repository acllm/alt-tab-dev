import AppKit
import AltTabCore
import AltTabApp

// Diagnostic mode: enumerate switchable windows and exit. Useful to verify
// the CG+AX pipeline and permissions without the GUI:
//   AltTab --dump
// Add `--thumbnails <dir>` to also capture each window through the real
// ThumbnailProvider pipeline and save the images as PNGs there:
//   AltTab --dump --thumbnails /tmp/alttab-thumbs
if CommandLine.arguments.contains("--dump") {
    let verbose = CommandLine.arguments.contains("--verbose")
    WindowRepository.dumpDiagnostics(verbose: verbose)

    let args = CommandLine.arguments
    if let flag = args.firstIndex(of: "--thumbnails"), flag + 1 < args.count {
        dumpThumbnails(to: args[flag + 1])
    }
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

/// Capture a thumbnail for every living window via the production
/// ThumbnailProvider path and save each as <windowID>.png in `dir`.
func dumpThumbnails(to dir: String) {
    let repository = WindowRepository()
    let provider = ThumbnailProvider(repository: repository)
    let living = repository.enumerate().living
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    var pending = Set(living.filter { !$0.minimized }.map(\.id))
    var names: [UInt32: String] = [:]
    for window in living { names[window.id] = "\(window.appName)-\(window.title.prefix(20))" }

    provider.beginSession()
    provider.loadThumbnails(for: living) { id in
        pending.remove(id)
        guard let image = provider.cachedThumbnail(for: id) else { return }
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let safe = names[id]?.replacingOccurrences(of: "/", with: "_") ?? String(id)
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(id)-\(safe).png"))
        }
    }

    print("thumbnails → \(dir) (\(pending.count) pending captures)")
    let deadline = Date().addingTimeInterval(5)
    while !pending.isEmpty && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    for id in pending.sorted() {
        print("  no thumbnail: \(id) \(names[id] ?? "?")")
    }
}
