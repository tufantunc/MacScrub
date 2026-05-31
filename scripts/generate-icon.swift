import AppKit

// Renders a 1024x1024 app-icon master: a light squircle with the teal "sparkles"
// mark centered. Usage: swift scripts/generate-icon.swift <output.png>
let px = 1024
let size = CGFloat(px)
let canvas = NSSize(width: size, height: size)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("rep") }
rep.size = canvas

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor.clear.set()
NSRect(origin: .zero, size: canvas).fill()

let inset: CGFloat = 96
let r = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = r.width * 0.2237
let squircle = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)

let gradient = NSGradient(colors: [
    NSColor.white,
    NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)
])!
gradient.draw(in: squircle, angle: -90)

NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.06).set()
squircle.lineWidth = 2
squircle.stroke()

let teal = NSColor(srgbRed: 0.12, green: 0.56, blue: 0.64, alpha: 1)
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular)
if let base = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let glyph = NSImage(size: base.size)
    glyph.lockFocus()
    teal.set()
    let gr = NSRect(origin: .zero, size: base.size)
    base.draw(in: gr)
    gr.fill(using: .sourceAtop)
    glyph.unlockFocus()
    let gx = (size - base.size.width) / 2
    let gy = (size - base.size.height) / 2
    glyph.draw(in: NSRect(x: gx, y: gy, width: base.size.width, height: base.size.height))
}

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(px)x\(px))")
