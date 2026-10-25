// Renders the "ব" glyph into the menu bar icon (InputIcon.tiff, template image) and
// AppIcon.icns. Needs macOS (uses AppKit and the system Bengali font).
//   swift scripts/make-icons.swift <output-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(size: Int, glyph: String, color: NSColor, background: NSColor?, corner: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    if let bg = background {
        bg.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * corner, yRadius: s * corner).fill()
    }
    let font = NSFont(name: "Kohinoor Bangla", size: s * 0.66) ?? NSFont.systemFont(ofSize: s * 0.66)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: glyph, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Menu bar icon: black glyph on transparent, 18pt @1x and @2x in one TIFF.
let menu1 = render(size: 18, glyph: "ব", color: .black, background: nil, corner: 0)
let menu2 = render(size: 36, glyph: "ব", color: .black, background: nil, corner: 0)
menu1.size = NSSize(width: 18, height: 18)
menu2.size = NSSize(width: 18, height: 18)
let tiff = NSImage(size: NSSize(width: 18, height: 18))
tiff.addRepresentation(menu1)
tiff.addRepresentation(menu2)
if let data = tiff.tiffRepresentation { try data.write(to: out.appendingPathComponent("InputIcon.tiff")) }

// App icon.
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let green = NSColor(calibratedRed: 0.11, green: 0.30, blue: 0.62, alpha: 1)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = render(size: px, glyph: "ব", color: .white, background: green, corner: 0.22)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
