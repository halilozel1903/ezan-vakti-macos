import AppKit
import Foundation

let size = 1024
let bitmap = NSBitmapImageRep(
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
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let tile = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 210, yRadius: 210)
tile.addClip()
let charcoal = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1)
let orange = NSColor(calibratedRed: 1, green: 0.49, blue: 0.09, alpha: 1)
charcoal.setFill()
tile.fill()

orange.setFill()
NSBezierPath(ovalIn: NSRect(x: 226, y: 210, width: 575, height: 575)).fill()
charcoal.setFill()
NSBezierPath(ovalIn: NSRect(x: 380, y: 360, width: 520, height: 520)).fill()

func star(center: NSPoint, outer: CGFloat, inner: CGFloat, points: Int) -> NSBezierPath {
    let path = NSBezierPath()
    for index in 0..<(points * 2) {
        let angle = CGFloat(index) * .pi / CGFloat(points) + .pi / 2
        let radius = index.isMultiple(of: 2) ? outer : inner
        let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if index == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}

orange.setFill()
star(center: NSPoint(x: 725, y: 748), outer: 73, inner: 34, points: 5).fill()
star(center: NSPoint(x: 811, y: 625), outer: 28, inner: 11, points: 4).fill()

NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: "EzanVakti/Resources/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
