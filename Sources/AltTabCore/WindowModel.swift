import Foundation
import CoreGraphics

/// Activation policy of the app owning a window, mirroring
/// NSApplication.ActivationPolicy as a pure value so it stays testable.
public enum AppPolicy: Equatable {
    case regular
    case accessory
    case prohibited
}

/// Raw window descriptor as reported by the system (CG window list + AX),
/// before any filtering is applied.
public struct RawWindowInfo: Equatable {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let ownerName: String
    public let title: String
    public let layer: Int
    public let bounds: CGRect
    public let isOnscreen: Bool
    public let minimized: Bool
    public let ownerPolicy: AppPolicy
    public let isSelf: Bool

    public init(
        windowID: UInt32,
        ownerPID: Int32,
        ownerName: String,
        title: String,
        layer: Int,
        bounds: CGRect,
        isOnscreen: Bool,
        minimized: Bool,
        ownerPolicy: AppPolicy,
        isSelf: Bool
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.layer = layer
        self.bounds = bounds
        self.isOnscreen = isOnscreen
        self.minimized = minimized
        self.ownerPolicy = ownerPolicy
        self.isSelf = isSelf
    }
}

/// A switchable window, after filtering. Identity is the CG window id.
public struct WindowModel: Equatable, Identifiable {
    public let id: UInt32
    public let ownerPID: Int32
    public let appName: String
    public let title: String
    public let minimized: Bool
    public let frame: CGRect

    public init(
        id: UInt32,
        ownerPID: Int32,
        appName: String,
        title: String,
        minimized: Bool,
        frame: CGRect
    ) {
        self.id = id
        self.ownerPID = ownerPID
        self.appName = appName
        self.title = title
        self.minimized = minimized
        self.frame = frame
    }
}
