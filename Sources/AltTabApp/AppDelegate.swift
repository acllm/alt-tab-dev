import AppKit
import AltTabCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionsCenter()
    private let repository = WindowRepository()
    private lazy var thumbnails = ThumbnailProvider(repository: repository)
    private lazy var panel = SwitcherPanel()
    private lazy var coordinator = AppCoordinator(
        state: SwitcherState(),
        repository: repository,
        panel: panel,
        thumbnails: thumbnails
    )
    private var statusMenu: StatusMenuController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.log("launch: ax=\(permissions.hasAccessibility) screenRecording=\(permissions.hasScreenRecording)")
        coordinator.start()
        statusMenu = StatusMenuController(permissions: permissions)
        permissions.promptIfMissing()
    }
}
