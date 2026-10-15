import AppKit

/// Faceless app has no Dock icon — a status bar item is the only way out.
public final class StatusMenuController: NSObject {
    private let item: NSStatusItem
    private let permissions: PermissionsCenter

    public init(permissions: PermissionsCenter) {
        self.permissions = permissions
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3",
                                   accessibilityDescription: "AltTab")
        }

        let menu = NSMenu()
        let permissionsItem = menu.addItem(withTitle: "权限设置…", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出 AltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        item.menu = menu
    }

    @objc private func openPermissions() {
        permissions.promptIfMissing()
    }
}
