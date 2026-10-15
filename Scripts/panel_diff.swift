// Pixel-level panel detection for verify-app.sh:
// compares the panel-area mean brightness between the "shown" and "hidden"
// screenshots. A rendered dark translucent panel darkens its area
// substantially; wallpaper drift stays near zero (checked against a corner).
import CoreGraphics
import Foundation
import ImageIO

func loadGray(_ path: String) -> (pixels: [UInt8], width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (pixels, w, h)
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/alttab-e2e"
guard let show = loadGray("\(dir)/vshot1_show.png"),
      let hidden = loadGray("\(dir)/vshot4_hidden.png")
else {
    print("PANEL-RENDER: cannot load screenshots")
    exit(1)
}

func meanDelta(_ a: (pixels: [UInt8], width: Int, height: Int),
               _ b: (pixels: [UInt8], width: Int, height: Int),
               box: CGRect) -> Double {
    let x0 = Int(box.minX), y0 = Int(box.minY)
    let x1 = Int(box.maxX), y1 = Int(box.maxY)
    var total = 0; var count = 0
    for y in stride(from: y0, to: y1, by: 3) {
        for x in stride(from: x0, to: x1, by: 3) {
            guard x < a.width, y < a.height, x < b.width, y < b.height else { continue }
            total += Int(a.pixels[y * a.width + x]) - Int(b.pixels[y * b.width + x])
            count += 1
        }
    }
    return count > 0 ? Double(total) / Double(count) : 0
}

// Panel frame in CG top-left coords at 2x: (712, 398, 2744, 1914)
let panelBox = CGRect(x: 712, y: 398, width: 2032, height: 1516)
// Top-right corner: wallpaper-only reference
let cornerBox = CGRect(x: 3260, y: 80, width: 140, height: 140)

let panelDelta = meanDelta(show, hidden, box: panelBox)
let noise = meanDelta(show, hidden, box: cornerBox)
print(String(format: "panel-area mean delta: %+.1f (wallpaper drift: %+.2f)", panelDelta, noise))

if panelDelta < -4 && abs(noise) < 4 {
    print("PANEL-RENDER: VERIFIED")
    exit(0)
} else {
    print("PANEL-RENDER: NOT DETECTED")
    exit(1)
}
