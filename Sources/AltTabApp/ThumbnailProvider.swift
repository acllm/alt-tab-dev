import AppKit
import CoreGraphics
import Foundation
import AltTabCore

/// Captures down-scaled window screenshots for the switcher cells.
///
/// Uses CGWindowListCreateImage (deprecated but functional, same call the
/// original project relied on for years). Requires the Screen Recording
/// permission; without it captures come back empty and cells fall back to
/// app-icon-only rendering. Minimized windows have no live capture either.
public final class ThumbnailProvider {
    private let repository: WindowRepository
    private var cache: [UInt32: NSImage] = [:]
    private let queue = DispatchQueue(label: "alttab.thumbnails", qos: .userInteractive)
    private(set) var cellSize = CGSize(width: 320, height: 200)

    public init(repository: WindowRepository) {
        self.repository = repository
    }

    public func cachedThumbnail(for id: UInt32) -> NSImage? {
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
            for window in windows where !window.minimized {
                if self.cache[window.id] == nil {
                    let bounds = CGRect(origin: .zero, size: self.cellSize)
                    let image = CGCompat.windowImage(
                        bounds: bounds,
                        listOption: [],
                        windowID: window.id,
                        imageOption: [.nominalResolution, .boundsIgnoreFraming]
                    ).map { NSImage(cgImage: $0, size: self.cellSize) }
                    if let image {
                        self.cache[window.id] = image
                    }
                }
                let id = window.id
                DispatchQueue.main.async { onUpdate(id) }
            }
        }
    }
}
