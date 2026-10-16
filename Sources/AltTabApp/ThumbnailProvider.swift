import AppKit
import CoreGraphics
import Foundation
import AltTabCore

/// Captures window screenshots for the switcher cells.
///
/// Two things must hold for a capture to show the right pixels, both
/// established empirically on macOS 15 and both matching the SDK header:
///
///  - The list option must be `.optionIncludingWindow` ("use only the
///    window specified by windowID"). Any other list option ignores the
///    window id — with `.optionAll` (raw 0, what `[]` passes) the call
///    composites *every on-screen window* at the requested rect, so each
///    thumbnail shows whatever happens to be on screen there: the
///    frontmost app, another app's window, or bare desktop.
///  - The Screen Recording permission must be granted; without it the
///    window "can't be read" and the API returns a transparent black
///    image (a blank rounded rectangle in the cell). The official
///    CGPreflightScreenCaptureAccess() check gates this reliably — the
///    behavioral probe it replaced flipped randomly depending on what
///    happened to be on screen at first launch.
///
/// With both satisfied, `CGRect.null` bounds returns exactly the window's
/// own rectangle, occluders excluded, even for fully covered windows.
/// Off-Space and minimized windows have no readable surface and come back
/// nil — those cells honestly fall back to the app icon.
///
/// Threading: all mutable state lives on the main thread; only the
/// CGWindowListCreateImage calls run on the capture queue.
public final class ThumbnailProvider {
    private let repository: WindowRepository
    private var cache: [UInt32: NSImage] = [:]
    private let queue = DispatchQueue(label: "alttab.thumbnails", qos: .userInteractive)

    /// Re-checked at every load: a grant + app relaunch takes effect
    /// without restarting the provider. Main thread only.
    private var capturesPermitted = false
    /// Set by beginSession() so the next load recaptures every window —
    /// the cache alone would keep showing each window's first-ever
    /// capture forever. Main thread only.
    private var recaptureAll = false

    public init(repository: WindowRepository) {
        self.repository = repository
    }

    public func cachedThumbnail(for id: UInt32) -> NSImage? {
        guard capturesPermitted else { return nil }
        return cache[id]
    }

    public func appIcon(for window: WindowModel) -> NSImage? {
        return repository.appIcon(pid: window.ownerPID)
    }

    /// Start a fresh switcher invocation: the next loadThumbnails pass
    /// recaptures every window. Old images stay on screen until their
    /// replacement lands, so cells never flash back to icons.
    public func beginSession() {
        recaptureAll = true
    }

    /// Kick off captures for `windows` (skips minimized ones). Each
    /// captured image is stored and delivered on the main thread via
    /// `onUpdate`.
    public func loadThumbnails(for windows: [WindowModel], onUpdate: @escaping (UInt32) -> Void) {
        // Drop cache entries of windows that no longer exist.
        let ids = Set(windows.map(\.id))
        cache = cache.filter { ids.contains($0.key) }

        capturesPermitted = CGPreflightScreenCaptureAccess()
        if !capturesPermitted {
            DiagLog.log("thumbnails: screen recording not granted — using app icons")
            return
        }

        let recapture = recaptureAll
        recaptureAll = false
        let targets = windows.filter {
            !$0.minimized && !$0.frame.isEmpty && (recapture || cache[$0.id] == nil)
        }
        guard !targets.isEmpty else { return }

        queue.async {
            for window in targets {
                // .null bounds = "the bounding box of the specified
                // windows" — with .optionIncludingWindow that is exactly
                // this window's rect, in whatever Space it lives, with no
                // coordinate math of our own to get wrong.
                guard let cgImage = CGCompat.windowImage(
                    bounds: .null,
                    listOption: .optionIncludingWindow,
                    windowID: window.id,
                    imageOption: [.boundsIgnoreFraming, .nominalResolution]
                ), !Self.isBlank(cgImage) else { continue }
                let image = NSImage(cgImage: cgImage,
                                    size: NSSize(width: cgImage.width, height: cgImage.height))
                let id = window.id
                DispatchQueue.main.async {
                    self.cache[id] = image
                    onUpdate(id)
                }
            }
        }
    }

    /// Detect the documented degraded return — "a transparent black
    /// image" — which shows up as an empty rectangle in the cell. Real
    /// window content always has opaque pixels somewhere.
    private static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 8 {
            return false
        }
        return true
    }
}
