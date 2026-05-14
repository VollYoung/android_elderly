import AppKit
import Foundation

private struct IconSize {
    let folder: String
    let pixels: Int
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let sizes = [
    IconSize(folder: "mipmap-mdpi", pixels: 48),
    IconSize(folder: "mipmap-hdpi", pixels: 72),
    IconSize(folder: "mipmap-xhdpi", pixels: 96),
    IconSize(folder: "mipmap-xxhdpi", pixels: 144),
    IconSize(folder: "mipmap-xxxhdpi", pixels: 192),
]

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / 512
    context.scaleBy(x: scale, y: scale)

    let baseRect = NSRect(x: 0, y: 0, width: 512, height: 512)
    let base = NSBezierPath(roundedRect: baseRect, xRadius: 116, yRadius: 116)
    NSGradient(colors: [
        color(0x00695C),
        color(0x00897B),
        color(0x26A69A),
    ])!.draw(in: base, angle: 120)

    color(0xFFFFFF, alpha: 0.08).setFill()
    NSBezierPath(roundedRect: NSRect(x: 66, y: 66, width: 380, height: 380), xRadius: 88, yRadius: 88).fill()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x003C36, alpha: 0.28).cgColor)
    drawShield(fill: color(0xE0F2F1), stroke: nil)
    context.restoreGState()

    drawShield(fill: color(0xFFFFFF), stroke: color(0xB2DFDB))

    color(0x00796B).setStroke()
    drawWifiArc(center: NSPoint(x: 244, y: 226), radius: 120, start: 34, end: 146, width: 30)
    drawWifiArc(center: NSPoint(x: 244, y: 226), radius: 76, start: 40, end: 140, width: 28)

    color(0x00695C).setFill()
    NSBezierPath(ovalIn: NSRect(x: 220, y: 206, width: 48, height: 48)).fill()

    color(0x00796B).setFill()
    let barWidth: CGFloat = 24
    let barRadius: CGFloat = 12
    for (x, height) in [(326.0, 58.0), (362.0, 88.0), (398.0, 118.0)] {
        NSBezierPath(
            roundedRect: NSRect(x: x, y: 190, width: barWidth, height: height),
            xRadius: barRadius,
            yRadius: barRadius
        ).fill()
    }

    color(0xFFB300).setFill()
    NSBezierPath(ovalIn: NSRect(x: 344, y: 318, width: 74, height: 74)).fill()
    color(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 376, y: 346, width: 10, height: 32), xRadius: 5, yRadius: 5).fill()
    NSBezierPath(ovalIn: NSRect(x: 374, y: 330, width: 14, height: 14)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func drawShield(fill: NSColor, stroke: NSColor?) {
    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: 256, y: 94))
    shield.curve(to: NSPoint(x: 382, y: 142), controlPoint1: NSPoint(x: 294, y: 108), controlPoint2: NSPoint(x: 336, y: 120))
    shield.curve(to: NSPoint(x: 360, y: 316), controlPoint1: NSPoint(x: 382, y: 222), controlPoint2: NSPoint(x: 378, y: 278))
    shield.curve(to: NSPoint(x: 256, y: 410), controlPoint1: NSPoint(x: 340, y: 360), controlPoint2: NSPoint(x: 304, y: 390))
    shield.curve(to: NSPoint(x: 152, y: 316), controlPoint1: NSPoint(x: 208, y: 390), controlPoint2: NSPoint(x: 172, y: 360))
    shield.curve(to: NSPoint(x: 130, y: 142), controlPoint1: NSPoint(x: 134, y: 278), controlPoint2: NSPoint(x: 130, y: 222))
    shield.curve(to: NSPoint(x: 256, y: 94), controlPoint1: NSPoint(x: 176, y: 120), controlPoint2: NSPoint(x: 218, y: 108))
    shield.close()
    fill.setFill()
    shield.fill()
    if let stroke {
        stroke.setStroke()
        shield.lineWidth = 8
        shield.stroke()
    }
}

private func drawWifiArc(center: NSPoint, radius: CGFloat, start: CGFloat, end: CGFloat, width: CGFloat) {
    let arc = NSBezierPath()
    arc.lineCapStyle = .round
    arc.lineJoinStyle = .round
    arc.lineWidth = width
    arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    arc.stroke()
}

private func writeIcon(size: Int, to url: URL) throws {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 1)
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

for iconSize in sizes {
    let url = root
        .appendingPathComponent("android/app/src/main/res")
        .appendingPathComponent(iconSize.folder)
        .appendingPathComponent("ic_launcher.png")
    try writeIcon(size: iconSize.pixels, to: url)
}

try writeIcon(size: 512, to: root.appendingPathComponent("assets/icon/network_guard_launcher_preview.png"))
