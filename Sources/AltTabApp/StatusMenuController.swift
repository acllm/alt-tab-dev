import AppKit

/// Faceless app has no Dock icon — a status bar item is the only way out.
/// Quit only: permission guidance happens once at launch (PermissionsCenter
/// .promptIfMissing), so there is no settings surface to expose here yet.
public final class StatusMenuController: NSObject {
    private let item: NSStatusItem

    public override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3",
                                   accessibilityDescription: "AltTab")
        }

        let menu = NSMenu()
        let quitItem = menu.addItem(withTitle: "退出 AltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        item.menu = menu
    }
}
