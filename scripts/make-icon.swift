import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let browser = CommandLine.arguments.dropFirst(2).first == "browser"
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = browser ? NSColor(calibratedRed: 0.13, green: 0.095, blue: 0.075, alpha: 1) : NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.10, alpha: 1)
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 208, yRadius: 208).fill()
        if browser {
            let amber = NSColor(calibratedRed: 1.0, green: 0.67, blue: 0.29, alpha: 1)
            amber.withAlphaComponent(0.12).setFill()
            NSBezierPath(ovalIn: NSRect(x: 228, y: 228, width: 568, height: 568)).fill()
            amber.setStroke()
            let globe = NSBezierPath(ovalIn: NSRect(x: 238, y: 238, width: 548, height: 548))
            globe.lineWidth = 32; globe.stroke()
            let meridian = NSBezierPath(ovalIn: NSRect(x: 401, y: 238, width: 222, height: 548))
            meridian.lineWidth = 21; meridian.stroke()
            for y: CGFloat in [386, 638] {
                let latitude = NSBezierPath()
                latitude.move(to: NSPoint(x: 264, y: y))
                latitude.curve(to: NSPoint(x: 760, y: y), controlPoint1: NSPoint(x: 390, y: y + (y < 512 ? -54 : 54)), controlPoint2: NSPoint(x: 634, y: y + (y < 512 ? -54 : 54)))
                latitude.lineWidth = 21; latitude.stroke()
            }
            let equator = NSBezierPath(); equator.move(to: NSPoint(x: 240, y: 512)); equator.line(to: NSPoint(x: 784, y: 512)); equator.lineWidth = 21; equator.stroke()
            // A distinct small navigation arrow keeps the browser legible in the Dock.
            background.setFill(); NSBezierPath(ovalIn: NSRect(x: 635, y: 190, width: 196, height: 196)).fill()
            NSColor(calibratedRed: 1, green: 0.87, blue: 0.66, alpha: 1).setFill()
            let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 690, y: 238)); arrow.line(to: NSPoint(x: 784, y: 335)); arrow.line(to: NSPoint(x: 676, y: 310)); arrow.line(to: NSPoint(x: 720, y: 285)); arrow.close(); arrow.fill()
        } else {
        for index in 0..<3 {
            let y = CGFloat(300 + index * 145)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 240, y: y)); path.line(to: NSPoint(x: 512, y: y - 135)); path.line(to: NSPoint(x: 784, y: y)); path.line(to: NSPoint(x: 512, y: y + 135)); path.close()
            NSColor(calibratedRed: 0.12, green: 0.50, blue: 1.0, alpha: CGFloat(0.38 + Double(index) * 0.31)).setFill(); path.fill()
            NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.10, alpha: 1).setStroke(); path.lineWidth = 24; path.stroke()
        }
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
    }
}
