import AppKit
import CoreGraphics
import Foundation
import AltTabCore

/// Captures window screenshots for the switcher cells.
///
/// The Screen Recording permission is unreliable to detect on modern macOS:
/// when missing, CGWindowListCreateImage *silently degrades* — it still
/// returns images, but they are composites of whatever is currently on
/// screen at the window's rectangle (every cell shows the frontmost app).
/// Showing those wrong thumbnails is worse than showing none, so before
/// capturing anything the provider runs a behavioral probe: capture two
/// different windows and compare content fingerprints. Captures are only
/// enabled when the two are actually distinguishable; otherwise every cell
/// renders the app icon — stable, correct, and permission-free.
public final class ThumbnailProvider {
    private let repository: WindowRepository
    private var cache: [UInt32: NSImage] = [:]
    private let queue = DispatchQueue(label: "alttab.thumbnails", qos: .userInteractive)

    /// Decided once per session by the behavioral probe; nil = not probed yet.
    private var capturesEnabled: Bool?

    public init(repository: WindowRepository) {
        self.repository = repository
    }

    public func cachedThumbnail(for id: UInt32) -> NSImage? {
        guard capturesEnabled == true else { return nil }
        return cache[id]
    }

    public func appIcon(for window: WindowModel) -> NSImage? {
        return repository.appIcon(pid: window.ownerPID)
    }

    /// Kick off captures for `windows` (skips minimized ones). Each capture
    /// is delivered on the main thread via `onUpdate`.
    public func loadThumbnails(for windows: [WindowModel], onUpdate: @escaping (UInt32) -> Void) {
        // Drop cache entries of windows that no longer exist.
        let ids = Set(windows.map(\.id))
        cache = cache.filter { ids.contains($0.key) }

        queue.async {
            if self.capturesEnabled == nil {
                self.capturesEnabled = self.probeCaptureAbility(windows)
                DiagLog.log("thumbnails: capture probe → \(self.capturesEnabled == true ? "ENABLED (real window content)" : "DISABLED (degraded captures; using app icons)")")
            }
            guard self.capturesEnabled == true else { return }

            for window in windows where !window.minimized && !window.frame.isEmpty {
                if self.cache[window.id] == nil {
                    // screenBounds takes *screen* coordinates: passing the
                    // window's own frame captures exactly that window
                    // (CGRect.null returns a whole-screen grab instead).
                    // Aspect-fit scaling happens at draw time.
                    let image = CGCompat.windowImage(
                        bounds: window.frame,
                        listOption: [],
                        windowID: window.id,
                        imageOption: [.boundsIgnoreFraming]
                    ).map { cgImage in
                        NSImage(cgImage: cgImage,
                                size: NSSize(width: cgImage.width, height: cgImage.height))
                    }
                    if let image {
                        self.cache[window.id] = image
                    }
                }
                let id = window.id
                DispatchQueue.main.async { onUpdate(id) }
            }
        }
    }

    // MARK: - Behavioral probe

    /// Decide whether window captures return real window content.
    ///
    /// Method: pick a non-frontmost window (almost always at least partly
    /// occluded), capture it through the window API, and crop the same
    /// rectangle out of a full-screen capture. In degraded (unauthorized)
    /// mode the window API silently composites from the screen, so the two
    /// match exactly; with the permission working, an occluded window's own
    /// content differs from what the screen shows there.
    /// Conservative by design: a false "disabled" just means app icons.
    private func probeCaptureAbility(_ windows: [WindowModel]) -> Bool {
        let candidates = windows.filter { !$0.minimized && !$0.frame.isEmpty }
        guard candidates.count >= 2 else { return false }
        let probe = candidates[1] // MRU order: not the frontmost window

        guard let windowImage = CGCompat.windowImage(
            bounds: probe.frame, listOption: [], windowID: probe.id,
            imageOption: [.boundsIgnoreFraming]
        ) else { return false }

        guard let screenImage = CGDisplayCreateImage(CGMainDisplayID()),
              let scale = NSScreen.main?.backingScaleFactor, scale > 0
        else { return false }

        // probe.frame is in global points (top-left origin, same axis as the
        // captured screen image); convert to pixels and clamp to bounds.
        let pixelRect = CGRect(
            x: probe.frame.minX * scale, y: probe.frame.minY * scale,
            width: probe.frame.width * scale, height: probe.frame.height * scale
        ).intersection(CGRect(x: 0, y: 0, width: screenImage.width, height: screenImage.height))
        guard !pixelRect.isEmpty, let screenRegion = screenImage.cropping(to: pixelRect) else {
            return false
        }

        return fingerprint(windowImage) != fingerprint(screenRegion)
    }

    /// 8x8 grayscale average hash — robust to scaling, good enough to tell
    /// "two different windows" from "the same screen composite twice".
    private func fingerprint(_ image: CGImage) -> UInt64 {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        ctx?.interpolationQuality = .medium
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var hash: UInt64 = 0
        for (i, pixel) in pixels.enumerated() where Int(pixel) > mean {
            hash |= 1 << UInt64(i)
        }
        return hash
    }
}
