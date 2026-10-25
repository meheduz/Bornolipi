// Draws the disk image window background: a quiet arrow from the app to Applications and one line
// of instruction. Writes <out>/background.png (1x) and <out>/background@2x.png.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "build/dmg-art"
let size = NSSize(width: 600, height: 380)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: NSColor(white: 0.985, alpha: 1), ending: NSColor(white: 0.94, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Arrow between the two icons (centred at x 160 and 440, y 190 from the top).
    let y = size.height - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: y)); arrow.line(to: NSPoint(x: 334, y: y))
    arrow.move(to: NSPoint(x: 322, y: y + 11)); arrow.line(to: NSPoint(x: 336, y: y)); arrow.line(to: NSPoint(x: 322, y: y - 11))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor(white: 0.62, alpha: 1).setStroke()
    arrow.stroke()

    let caption = "Drag Bornolipi to Applications to install"
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .regular),
                                                 .foregroundColor: NSColor(white: 0.45, alpha: 1), .paragraphStyle: style]
    caption.draw(in: NSRect(x: 0, y: 52, width: size.width, height: 20), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: URL(fileURLWithPath: "\(out)/background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: "\(out)/background@2x.png"))
