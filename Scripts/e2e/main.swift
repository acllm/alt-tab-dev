// E2E UI verification entry: real binary + real NSApplication, synthetic
// window data. `swift run AltTabE2E`

import AppKit
import AltTabCore
import AltTabApp

let app = NSApplication.shared
// A bare never-activated accessory process can't get windows onto the
// user's space; regular works for this in-process verification.
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
