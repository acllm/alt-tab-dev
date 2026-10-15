import Foundation

/// Maintains the most-recently-used-first ordering of switchable windows.
///
/// The front of the list is the most recently used window. Ordering inputs:
///  - explicit `focus(id:)` events (window was focused via the switcher or
///    otherwise), which move a window to the front;
///  - z-order snapshots of visible windows (`applySnapshot`) — the system
///    window list front-to-back is a good approximation of recency. Windows
///    absent from the snapshot (minimized, hidden) keep their previous
///    relative order at the end of the list;
///  - `reconcile(living:)` drops closed windows and registers new ones.
public final class MruWindowList {
    public private(set) var windows: [WindowModel] = []

    public init(seed: [WindowModel]) {
        windows = seed
    }

    /// A window was focused: move it to the front of the list.
    public func focus(id: UInt32) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows.remove(at: index)
        windows.insert(window, at: 0)
    }

    /// Reorder according to a front-to-back z-order snapshot of visible
    /// windows. Windows not in the snapshot trail behind, keeping their
    /// previous relative order. Snapshot entries can include windows that
    /// were not known before (they just became visible).
    public func applySnapshot(frontToBack: [WindowModel]) {
        var known: [UInt32: WindowModel] = [:]
        known.reserveCapacity(windows.count + frontToBack.count)
        for window in windows { known[window.id] = window }
        for window in frontToBack { known[window.id] = window }

        let snapshotIDs = Set(frontToBack.map(\.id))
        let tail = windows.filter { !snapshotIDs.contains($0.id) }
        windows = frontToBack.compactMap { known[$0.id] } + tail
    }

    /// Sync with the set of windows that currently exist (visible + minimized).
    /// Closed windows are dropped; the data of living windows is refreshed;
    /// brand-new windows are appended at the back until a snapshot or focus
    /// event places them.
    public func reconcile(living: [WindowModel]) {
        var livingByID: [UInt32: WindowModel] = [:]
        livingByID.reserveCapacity(living.count)
        for window in living { livingByID[window.id] = window }

        var result = windows.compactMap { livingByID[$0.id] }
        let knownIDs = Set(result.map(\.id))
        result += living.filter { !knownIDs.contains($0.id) }
        windows = result
    }

    public func window(at index: Int) -> WindowModel? {
        guard windows.indices.contains(index) else { return nil }
        return windows[index]
    }

    public func indexOf(id: UInt32) -> Int? {
        windows.firstIndex(where: { $0.id == id })
    }
}
