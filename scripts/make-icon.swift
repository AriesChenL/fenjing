import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 208, yRadius: 208).fill()
        for index in 0..<3 {
            let y = CGFloat(300 + index * 145)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 240, y: y)); path.line(to: NSPoint(x: 512, y: y - 135)); path.line(to: NSPoint(x: 784, y: y)); path.line(to: NSPoint(x: 512, y: y + 135)); path.close()
            NSColor(calibratedRed: 0.12, green: 0.50, blue: 1.0, alpha: CGFloat(0.38 + Double(index) * 0.31)).setFill(); path.fill()
            NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.10, alpha: 1).setStroke(); path.lineWidth = 24; path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
    }
}
