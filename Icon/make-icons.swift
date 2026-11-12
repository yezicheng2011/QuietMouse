// Draws the Quiet Mouse logo in light and dark variants.
// Usage: swift make-icons.swift <output dir>
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

struct Palette {
    let bgTop, bgBottom, body, bodyEdge, accent: NSColor
    let shadow: NSColor
}
let light = Palette(bgTop: color(0xF8FAFC), bgBottom: color(0xD9E0EA), body: color(0x1E293B), bodyEdge: color(0x334155),
                    accent: color(0x38BDF8), shadow: color(0x0F172A, 0.28))
let dark = Palette(bgTop: color(0x1E293B), bgBottom: color(0x0B1220), body: color(0xF1F5F9), bodyEdge: color(0xCBD5E1),
                   accent: color(0x2563EB), shadow: color(0x000000, 0.55))

func draw(_ p: Palette, size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // Background tile (macOS icon grid: 824pt tile centred in 1024).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x000000, 0.25).cgColor)
    p.bgBottom.setFill(); tilePath.fill()
    ctx.restoreGState()
    ctx.saveGState()
    tilePath.addClip()
    NSGradient(starting: p.bgTop, ending: p.bgBottom)!.draw(in: tile, angle: -90)
    ctx.restoreGState()

    // Mouse body: a tall capsule, like a Magic Mouse seen from above.
    let body = CGRect(x: 512 - 150, y: 512 - 290, width: 300, height: 580)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 150, yRadius: 150)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: p.shadow.cgColor)
    p.body.setFill(); bodyPath.fill()
    ctx.restoreGState()
    ctx.saveGState()
    bodyPath.addClip()
    NSGradient(starting: p.body, ending: p.bodyEdge)!.draw(in: body, angle: -90)

    // Tap ripple on the left half of the surface.
    let c = CGPoint(x: 512 - 62, y: 512 + 120)
    p.accent.setFill()
    NSBezierPath(ovalIn: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)).fill()
    for (r, a) in [(88.0, 0.75), (146.0, 0.42), (204.0, 0.2)] as [(CGFloat, CGFloat)] {
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ring.lineWidth = 15
        p.accent.withAlphaComponent(a).setStroke()
        ring.stroke()
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
save(draw(light, size: 1024), "\(out)/Logo-Light.png")
save(draw(dark, size: 1024), "\(out)/Logo-Dark.png")

// Finder icon (.icns source) uses the light variant.
let set = "\(out)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    save(draw(light, size: base), "\(set)/icon_\(base)x\(base).png")
    save(draw(light, size: base * 2), "\(set)/icon_\(base)x\(base)@2x.png")
}
