// Pixel-level panel detection for verify-app.sh (display-agnostic).
// The panel rect is derived from the diagnostics the app itself wrote
// (diag.txt: panel.frame + panel.screen in AppKit points, bottom-left
// origin) and converted into screenshot device pixels (top-left origin,
// scale self-calibrated from the screenshot width). Verdicts:
//   1. screen evidence — the panel area changes substantially between
//      shown/hidden while a reference corner on the same screen stays
//      stable (direction is content-dependent: darkens over a bright
//      background, brightens with thumbnails over a dark one);
//   2. focus evidence  — shot1 → shot2 differ inside the panel area
//      (the focus ring moved after Tab);
//   3. direct evidence — the panel window's own capture (panel_direct.png,
//      when available) is dark and non-uniform: real rendered content.
import CoreGraphics
import Foundation
import ImageIO

typealias GrayImage = (pixels: [UInt8], width: Int, height: Int)

func loadGray(_ path: String) -> GrayImage? {
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

/// All numeric literals in a diagnostics line, e.g.
/// `panel.frame = (772.0, 328.0, 1016.0, 758.0)` → [772, 328, 1016, 758].
func numbers(in line: Substring) -> [Double] {
    var result: [Double] = []
    var current = ""
    for ch in line {
        if ch.isNumber || ch == "." || ch == "-" {
            current.append(ch)
        } else if !current.isEmpty {
            if let d = Double(current) { result.append(d) }
            current = ""
        }
    }
    if !current.isEmpty, let d = Double(current) { result.append(d) }
    return result
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/alttab-e2e"
guard let show = loadGray("\(dir)/vshot1_show.png"),
      let afterTab = loadGray("\(dir)/vshot2_tab.png"),
      let hidden = loadGray("\(dir)/vshot4_hidden.png"),
      let diag = try? String(contentsOfFile: "\(dir)/diag.txt", encoding: .utf8)
else {
    print("PANEL-RENDER: cannot load screenshots/diagnostics from \(dir)")
    exit(1)
}

let lines = diag.split(separator: "\n")
func diagLine(_ prefix: String) -> Substring? {
    lines.first { $0.hasPrefix(prefix) }
}

guard let frameLine = diagLine("panel.frame"),
      let screenLine = diagLine("panel.screen"),
      numbers(in: frameLine).count >= 4,
      numbers(in: screenLine).count >= 4
else {
    print("PANEL-RENDER: diag.txt lacks panel.frame / panel.screen")
    exit(1)
}
let frameNums = numbers(in: frameLine)
let screenNums = numbers(in: screenLine)
let panelFrame = CGRect(x: frameNums[0], y: frameNums[1], width: frameNums[2], height: frameNums[3])
let anchorScreen = CGRect(x: screenNums[0], y: screenNums[1], width: screenNums[2], height: screenNums[3])

// `screencapture -x` (no flags) captures the primary display; AppKit's
// global coordinates share its origin, so panelFrame maps directly.
// A panel on another display can't be verified from this screenshot —
// say so instead of silently sampling the wrong area.
if anchorScreen.origin != .zero {
    print("PANEL-RENDER: note — panel is on a non-primary screen \(anchorScreen); " +
          "screenshot shows the primary display only")
}

// Scale self-calibrated from the screenshot vs the anchor screen size.
let scale = Double(show.width) / anchorScreen.width
if abs(Double(show.height) - anchorScreen.height * scale) / Double(show.height) > 0.05 {
    print(String(format: "PANEL-RENDER: warning — screenshot %dx%d vs anchor %.0fx%.0fpt mismatch",
                 show.width, show.height, anchorScreen.width, anchorScreen.height))
}

// AppKit points (bottom-left origin) → screenshot device px (top-left origin).
var panelBox = CGRect(
    x: panelFrame.minX * scale,
    y: (anchorScreen.maxY - panelFrame.maxY) * scale,
    width: panelFrame.width * scale,
    height: panelFrame.height * scale
)
panelBox = panelBox.intersection(CGRect(x: 0, y: 0, width: Double(show.width), height: Double(show.height)))
guard panelBox.width > 50, panelBox.height > 50 else {
    print("PANEL-RENDER: panel box degenerate \(panelBox)")
    exit(1)
}

// Reference corner: same screen as the panel, clear of the menu bar and
// (checked) of the panel itself — shared rendering conditions, so any
// brightness drift there means global change, not the panel.
let cornerBox = CGRect(x: 8 * scale, y: 40 * scale, width: 70 * scale, height: 70 * scale)
let noiseValid = !cornerBox.intersects(panelBox)

func meanDelta(_ a: GrayImage, _ b: GrayImage, box: CGRect) -> Double {
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

/// Fraction of sampled pixels inside `box` whose gray level moved by more
/// than `threshold` between the two shots.
func changedFraction(_ a: GrayImage, _ b: GrayImage, box: CGRect, threshold: Int = 20) -> Double {
    let x0 = Int(box.minX), y0 = Int(box.minY)
    let x1 = Int(box.maxX), y1 = Int(box.maxY)
    var changed = 0; var count = 0
    for y in stride(from: y0, to: y1, by: 3) {
        for x in stride(from: x0, to: x1, by: 3) {
            guard x < a.width, y < a.height, x < b.width, y < b.height else { continue }
            if abs(Int(a.pixels[y * a.width + x]) - Int(b.pixels[y * b.width + x])) > threshold {
                changed += 1
            }
            count += 1
        }
    }
    return count > 0 ? Double(changed) / Double(count) : 0
}

func grayStats(_ img: GrayImage) -> (mean: Double, std: Double) {
    var total = 0.0; var totalSq = 0.0; var count = 0.0
    for y in stride(from: 0, to: img.height, by: 3) {
        for x in stride(from: 0, to: img.width, by: 3) {
            let v = Double(img.pixels[y * img.width + x])
            total += v; totalSq += v * v; count += 1
        }
    }
    guard count > 0 else { return (0, 0) }
    let mean = total / count
    return (mean, (totalSq / count - mean * mean).squareRoot())
}

print(String(format: "panel box (device px): (%.0f, %.0f, %.0f, %.0f) scale=%.2f",
             panelBox.minX, panelBox.minY, panelBox.width, panelBox.height, scale))

// 1. Screen evidence: the panel substantially alters its area between
//    shown and hidden (darkens over a bright background, brightens with
//    thumbnails over a dark one — direction is content-dependent, so the
//    verdict uses the magnitude of change, not its sign).
let panelDelta = meanDelta(show, hidden, box: panelBox)
let panelChanged = changedFraction(show, hidden, box: panelBox)
let noise = noiseValid ? meanDelta(show, hidden, box: cornerBox) : 0
let screenOK = panelChanged > 0.02 && (!noiseValid || abs(noise) < 4)
print(String(format: "screen evidence: %.1f%% of panel pixels changed (mean delta %+.1f, reference drift %+.2f) → %@",
             panelChanged * 100, panelDelta, noise, screenOK ? "OK" : "FAIL"))

// 2. Focus evidence: the focus ring moved between shot1 and shot2.
let moved = changedFraction(show, afterTab, box: panelBox)
let focusOK = moved > 0.0005
print(String(format: "focus evidence: %.3f%% of panel pixels changed after Tab → %@",
             moved * 100, focusOK ? "OK" : "FAIL"))

// 3. Direct evidence: the panel window's own capture is dark + non-uniform.
var directOK: Bool?
if let direct = loadGray("\(dir)/panel_direct.png") {
    let stats = grayStats(direct)
    directOK = stats.mean < 140 && stats.std > 4
    print(String(format: "direct evidence: %dx%d mean=%.1f std=%.1f → %@",
                 direct.width, direct.height, stats.mean, stats.std, directOK! ? "OK" : "FAIL"))
} else {
    print("direct evidence: panel_direct.png missing — screen evidence only")
}

if screenOK && focusOK && directOK != false {
    print("PANEL-RENDER: VERIFIED")
    exit(0)
} else {
    print("PANEL-RENDER: NOT DETECTED")
    exit(1)
}
