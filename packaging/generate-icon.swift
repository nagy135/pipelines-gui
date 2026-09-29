import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let base = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 195, yRadius: 195)
NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.38, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.37, alpha: 1))!.draw(in: base, angle: -80)
let line = NSBezierPath()
line.move(to: NSPoint(x: 340, y: 310))
line.line(to: NSPoint(x: 340, y: 714))
line.move(to: NSPoint(x: 340, y: 430))
line.curve(to: NSPoint(x: 675, y: 665), controlPoint1: NSPoint(x: 675, y: 430), controlPoint2: NSPoint(x: 675, y: 535))
line.lineWidth = 58; line.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.92).setStroke(); line.stroke()
for (x, y) in [(340.0, 310.0), (340.0, 714.0), (675.0, 665.0)] {
    NSColor(calibratedRed: 0.49, green: 0.91, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 75, y: y - 75, width: 150, height: 150)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 37, y: y - 37, width: 74, height: 74)).fill()
}
image.unlockFocus()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
