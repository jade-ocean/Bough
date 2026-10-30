import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// make_appicon.swift - vector-drawn Bough app icon (Liquid Glass friendly):
// - square, full-bleed OPAQUE background layer (gradient)
// - crisp-edged foreground layer (branch + commit nodes), no feathering
// - core content inside the central ~80% safe area (112..912 on 1024)
// Rendered at every size from the same vector pass, so small sizes stay sharp.

let canvas: CGFloat = 1024
let safeMin: CGFloat = 112
let safeMax: CGFloat = 912

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let paperTop = color(0xF8F2E7)
let paperBottom = color(0xE7DDC4)
let bark = color(0x3E5C50)      // deep moss-green branch
let moss = color(0x6B9080)      // brand accent (leaves / ring)
let amber = color(0xD98E4A)     // warm accent node

func drawIcon(size: CGFloat) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Design-space: 1024 units, top-left origin (y grows downward).
    let scale = size / canvas
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: scale, y: -scale)

    // --- Background layer (opaque, full bleed) ---
    let gradient = CGGradient(colorsSpace: space,
                              colors: [paperTop, paperBottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: 0),
                           end: CGPoint(x: canvas, y: canvas),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // --- Foreground layer: branch + nodes ---
    // Main stem: rooted bottom-left, sweeping to upper right.
    let main = CGMutablePath()
    main.move(to: CGPoint(x: 205, y: 875))
    main.addCurve(to: CGPoint(x: 690, y: 185),
                  control1: CGPoint(x: 330, y: 700),
                  control2: CGPoint(x: 555, y: 430))
    // Fork: clear Y split toward the upper right.
    let fork = CGMutablePath()
    fork.move(to: CGPoint(x: 470, y: 585))
    fork.addCurve(to: CGPoint(x: 870, y: 330),
                  control1: CGPoint(x: 650, y: 505),
                  control2: CGPoint(x: 765, y: 410))

    func stroke(_ path: CGPath, _ width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(bark)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
    stroke(main, 92)
    stroke(fork, 66)

    // Leaves: pointed ovals sprouting from the branch sides, crisp edges.
    func leaf(at point: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, _ fill: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: angle)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: length, y: 0),
                          control: CGPoint(x: length / 2, y: -width))
        path.addQuadCurve(to: CGPoint(x: 0, y: 0),
                          control: CGPoint(x: length / 2, y: width))
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
        ctx.restoreGState()
    }
    leaf(at: CGPoint(x: 360, y: 725), angle: -2.1, length: 175, width: 50, moss)
    leaf(at: CGPoint(x: 690, y: 430), angle: -1.5, length: 155, width: 46, moss)

    // Commit nodes (history-graph echo): split point + both tips.
    func node(_ center: CGPoint, _ radius: CGFloat, _ fill: CGColor) {
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
    }
    node(CGPoint(x: 690, y: 185), 62, amber)   // main tip
    node(CGPoint(x: 870, y: 330), 48, moss)    // fork tip

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG write failed: \(url.lastPathComponent)"])
    }
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appiconset = repoRoot.appendingPathComponent("Bough/Resources/Assets.xcassets/AppIcon.appiconset")
let previews = repoRoot.appendingPathComponent("build/icon-preview")
try fileManager.createDirectory(at: appiconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: previews, withIntermediateDirectories: true)

// Classic icns size set (16..1024 incl. @2x) - what actool reliably compiles for macOS.
let iconSizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for entry in iconSizes {
    try writePNG(drawIcon(size: entry.pixels),
                 to: appiconset.appendingPathComponent(entry.name))
}

// Preview set for small-size legibility checks.
for size in [16.0, 32.0, 64.0, 128.0, 256.0, 512.0, 1024.0] as [CGFloat] {
    try writePNG(drawIcon(size: size), to: previews.appendingPathComponent("icon_\(Int(size)).png"))
}
print("icon rendered: 10-size set + previews in build/icon-preview/")
