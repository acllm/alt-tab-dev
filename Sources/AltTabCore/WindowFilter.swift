import Foundation
import CoreGraphics

/// Filters raw system window descriptors down to the windows the switcher
/// should show, mirroring alt-tab-macos's `windowsToShow` core rules:
/// only normal-layer windows of regular apps, never our own windows,
/// deduplicated by window id. Minimized windows are kept (they are
/// switchable); fully empty ghosts (no title *and* no bounds) are dropped.
public enum WindowFilter {
    public static func windows(from raw: [RawWindowInfo]) -> [WindowModel] {
        var seen = Set<UInt32>()
        var result: [WindowModel] = []
        for w in raw {
            guard w.layer == 0 else { continue }
            guard w.ownerPolicy == .regular else { continue }
            guard !w.isSelf else { continue }
            guard !w.title.isEmpty || !w.bounds.isEmpty else { continue }
            guard seen.insert(w.windowID).inserted else { continue }
            result.append(
                WindowModel(
                    id: w.windowID,
                    ownerPID: w.ownerPID,
                    appName: w.ownerName,
                    title: w.title,
                    minimized: w.minimized,
                    frame: w.bounds
                )
            )
        }
        return result
    }
}
