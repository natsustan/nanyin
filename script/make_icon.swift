// Draws the app icon: a glossy lime Aqua disc with a white note on a
// graphite tile. Run: swift script/make_icon.swift <AppIcon.appiconset dir>
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func rgb(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // Tile: macOS icon grid, 824 pt square with a 185 pt corner radius.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    rgb(0x2A2A2A).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0x5A5A5A), ending: rgb(0x262626))!.draw(in: tilePath, angle: -90)
    rgb(0xFFFFFF, 0.18).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3 * s, dy: 3 * s), xRadius: 182 * s, yRadius: 182 * s)
    rim.lineWidth = 4 * s
    rim.stroke()

    // Disc.
    let disc = NSRect(x: 232 * s, y: 232 * s, width: 560 * s, height: 560 * s)
    let discPath = NSBezierPath(ovalIn: disc)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = .black.withAlphaComponent(0.6)
    glow.shadowOffset = NSSize(width: 0, height: -10 * s)
    glow.shadowBlurRadius = 30 * s
    glow.set()
    rgb(0x84BD00).setFill()
    discPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0xB8E04A), rgb(0x84BD00), rgb(0x4E7A00)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: discPath, relativeCenterPosition: NSPoint(x: 0, y: -0.35))
    rgb(0x2E4A00, 0.8).setStroke()
    discPath.lineWidth = 6 * s
    discPath.stroke()

    // Note: two heads joined by a beam.
    rgb(0xFFFFFF).setFill()
    let note = NSBezierPath()
    func head(_ x: CGFloat, _ y: CGFloat) {
        let transform = AffineTransform(rotationByDegrees: -22)
        let oval = NSBezierPath(ovalIn: NSRect(x: -62 * s, y: -44 * s, width: 124 * s, height: 88 * s))
        oval.transform(using: transform)
        oval.transform(using: AffineTransform(translationByX: x * s, byY: y * s))
        note.append(oval)
    }
    head(418, 388)
    head(626, 430)
    note.appendRect(NSRect(x: 462 * s, y: 404 * s, width: 30 * s, height: 270 * s))
    note.appendRect(NSRect(x: 670 * s, y: 446 * s, width: 30 * s, height: 270 * s))
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: 462 * s, y: 674 * s))
    beam.line(to: NSPoint(x: 700 * s, y: 716 * s))
    beam.line(to: NSPoint(x: 700 * s, y: 646 * s))
    beam.line(to: NSPoint(x: 462 * s, y: 604 * s))
    beam.close()
    note.append(beam)
    NSGraphicsContext.saveGraphicsState()
    let noteShadow = NSShadow()
    noteShadow.shadowColor = rgb(0x2E4A00, 0.7)
    noteShadow.shadowOffset = NSSize(width: 0, height: -6 * s)
    noteShadow.shadowBlurRadius = 8 * s
    noteShadow.set()
    note.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Aqua gloss over the top half of the disc.
    let gloss = NSBezierPath(ovalIn: NSRect(x: 292 * s, y: 520 * s, width: 440 * s, height: 250 * s))
    NSGradient(starting: rgb(0xFFFFFF, 0.75), ending: rgb(0xFFFFFF, 0.05))!.draw(in: gloss, angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = draw(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!
        try data.write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: dir.appendingPathComponent("Contents.json"))
