import CoreGraphics
import Foundation

/// Runtime-resolved CGWindowListCreateImage.
///
/// The symbol was obsoleted in the macOS 15 SDK (SwiftPM treats it as a
/// warning, the JIT runner as an error; a future SDK will drop it). The
/// replacement (ScreenCaptureKit) needs an async permission flow that is
/// overkill for the core feature, so we resolve the classic symbol at
/// runtime — exactly what the original project did for years.
public enum CGCompat {
    private static let windowListCreateImage: (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> CGImage? = {
        guard
            let handle = dlopen(nil, RTLD_LAZY),
            let symbol = dlsym(handle, "CGWindowListCreateImage")
        else { return { _, _, _, _ in nil } }
        let fn = unsafeBitCast(symbol, to: (@convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?).self)
        return { bounds, listOption, windowID, imageOption in
            fn(bounds, listOption, windowID, imageOption)?.takeRetainedValue()
        }
    }()

    public static func windowImage(bounds: CGRect,
                            listOption: CGWindowListOption,
                            windowID: CGWindowID,
                            imageOption: CGWindowImageOption) -> CGImage? {
        return windowListCreateImage(bounds, listOption, windowID, imageOption)
    }
}
