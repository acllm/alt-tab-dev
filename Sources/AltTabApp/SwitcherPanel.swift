import AppKit
import AltTabCore

/// The switcher overlay: a borderless non-activating panel that renders the
/// window grid. All keyboard input arrives through the global event tap, so
/// the panel never needs key focus.
public final class SwitcherPanel: NSPanel {
    private let gridView = SwitcherView()

    /// Supplies thumbnails/icons at draw time; set by the coordinator.
    public var visuals: ThumbnailProvider? {
        get { gridView.visuals }
        set { gridView.visuals = newValue }
    }

    /// NSPanel floating semantics (mirrors the original app): the panel stays
    /// frontmost even while the app itself is not active — the single most
    /// important flag for an overlay switcher.
    public override var canBecomeKey: Bool { true }

    public init() {
        // Non-zero initial content rect: windows created with a zero frame
        // can end up with a surface that never attaches to the compositor
        // (invisible forever even though isVisible reports true).
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        contentView = gridView
        // Layer-backed: content in a transparent (clear-background) window
        // only composites correctly when the view hierarchy is layer-backed.
        gridView.wantsLayer = true
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        // popUpMenu like the original: above app windows and context menus,
        // below screensaver (which is excluded from screen capture anyway).
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isReleasedWhenClosed = false
    }

    public func showSwitcher(windows: [WindowModel], focusIndex: Int) {
        gridView.update(windows: windows, focusIndex: focusIndex)
        setFrameCentered(size: gridView.preferredSize())
        // An accessory app's windows otherwise stay in the app's original
        // space; activating (macOS 14+ no-arg form — the ignoringOtherApps
        // variant is a no-op there) pins the panel onto the current space.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKeyAndOrderFront(nil)
    }

    public func reloadSwitcher(windows: [WindowModel], focusIndex: Int) {
        gridView.update(windows: windows, focusIndex: focusIndex)
        // Window set changed — the grid may need a different size.
        let size = gridView.preferredSize()
        if size != frame.size {
            setFrameCentered(size: size)
        } else {
            gridView.needsDisplay = true
        }
    }

    public func setFocus(_ index: Int) {
        gridView.setFocus(index)
    }

    /// Repaint (e.g. a thumbnail capture just arrived).
    public func refresh() {
        gridView.needsDisplay = true
    }

    public func hideSwitcher() {
        orderOut(nil)
    }

    private func setFrameCentered(size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2
        setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
    }
}

/// Draws the dark translucent grid of window cells.
public final class SwitcherView: NSView {
    struct Metrics {
        static let outerPadding: CGFloat = 16
        static let spacing: CGFloat = 12
        static let thumbSize = CGSize(width: 320, height: 200)
        static let labelHeight: CGFloat = 24
        static var cellSize: CGSize {
            CGSize(width: thumbSize.width, height: thumbSize.height + labelHeight)
        }
        static let footerHeight: CGFloat = 30
        static let cornerRadius: CGFloat = 18
    }

    public var visuals: ThumbnailProvider?

    private var windows: [WindowModel] = []
    private var focusIndex: Int = 0
    private var columns: Int { GridLayout.columns(for: windows.count) }

    public override var isFlipped: Bool { true }

    public func update(windows: [WindowModel], focusIndex: Int) {
        self.windows = windows
        self.focusIndex = focusIndex
        needsDisplay = true
    }

    public func setFocus(_ index: Int) {
        focusIndex = index
        needsDisplay = true
    }

    public func preferredSize() -> NSSize {
        let count = max(windows.count, 1)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let width = Metrics.outerPadding * 2
            + CGFloat(columns) * Metrics.cellSize.width
            + CGFloat(columns - 1) * Metrics.spacing
        let height = Metrics.outerPadding * 2
            + CGFloat(rows) * Metrics.cellSize.height
            + CGFloat(rows - 1) * Metrics.spacing
            + Metrics.footerHeight
        return NSSize(width: width, height: height)
    }

    private func cellRect(_ index: Int) -> NSRect {
        let col = CGFloat(GridLayout.column(of: index, columns: columns))
        let row = CGFloat(GridLayout.row(of: index, columns: columns))
        return NSRect(
            x: Metrics.outerPadding + col * (Metrics.cellSize.width + Metrics.spacing),
            y: Metrics.outerPadding + row * (Metrics.cellSize.height + Metrics.spacing),
            width: Metrics.cellSize.width,
            height: Metrics.cellSize.height
        )
    }

    public override func draw(_ dirtyRect: NSRect) {
        // Translucent dark backdrop, like the original switcher.
        let background = NSBezierPath(roundedRect: bounds, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius)
        NSColor(calibratedWhite: 0.10, alpha: 0.85).setFill()
        background.fill()

        for (index, window) in windows.enumerated() {
            drawCell(window, in: cellRect(index), focused: index == focusIndex)
        }

        drawFooter()
    }

    private func drawCell(_ window: WindowModel, in rect: NSRect, focused: Bool) {
        // Focus ring + slightly lifted cell background.
        if focused {
            let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 12, yRadius: 12)
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            highlight.lineWidth = 4
            highlight.stroke()
        }

        let cellBackground = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        (focused
            ? NSColor(calibratedWhite: 1.0, alpha: 0.16)
            : NSColor(calibratedWhite: 1.0, alpha: 0.06)).setFill()
        cellBackground.fill()

        // Thumbnail area.
        let thumbRect = NSRect(
            x: rect.minX + 4, y: rect.minY + 4,
            width: rect.width - 8, height: Metrics.thumbSize.height - 8
        )
        let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0, alpha: 0.35).setFill()
        thumbPath.fill()

        if let image = visuals?.cachedThumbnail(for: window.id), image.size != .zero {
            drawFitted(image, in: thumbRect)
        } else if let icon = visuals?.appIcon(for: window) {
            // No live capture (minimized / no screen permission): big app icon.
            let side: CGFloat = min(thumbRect.width, thumbRect.height) * 0.4
            let iconRect = NSRect(
                x: thumbRect.midX - side / 2,
                y: thumbRect.midY - side / 2,
                width: side, height: side
            )
            icon.draw(in: iconRect)
        }

        // Label: app icon + window title.
        let iconSide: CGFloat = 16
        let iconRect = NSRect(x: rect.minX + 6, y: rect.maxY - Metrics.labelHeight + 3,
                              width: iconSide, height: iconSide)
        visuals?.appIcon(for: window)?.draw(in: iconRect)

        let titleRect = NSRect(
            x: iconRect.maxX + 5, y: rect.maxY - Metrics.labelHeight,
            width: rect.width - iconRect.maxX - 12, height: Metrics.labelHeight
        )
        let title = NSAttributedString(string: window.title.isEmpty ? window.appName : window.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        title.draw(with: titleRect, options: [.truncatesLastVisibleLine])
    }

    /// Draw `image` inside `rect` preserving aspect ratio, centered.
    private func drawFitted(_ image: NSImage, in rect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        let origin = NSPoint(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2)
        image.draw(in: NSRect(origin: origin, size: fitted))
    }

    private func drawFooter() {
        let footerRect = NSRect(
            x: Metrics.outerPadding,
            y: bounds.maxY - Metrics.outerPadding - Metrics.footerHeight + 4,
            width: bounds.width - Metrics.outerPadding * 2,
            height: Metrics.footerHeight
        )
        let text = "\(windows.count) 个窗口 · Tab / ←→↑↓ 选择 · ↵ 或松开 ⌥ 切换 · esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let str = NSAttributedString(string: text, attributes: attributes)
        let strRect = str.boundingRect(with: footerRect.size, options: [.truncatesLastVisibleLine])
        str.draw(at: NSPoint(x: footerRect.minX, y: footerRect.midY - strRect.height / 2))
    }
}
