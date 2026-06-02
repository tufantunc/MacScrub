import AppKit

// Renders a 1280x640 GitHub social-preview card: light background, the app icon
// on the left, title + tagline on the right. Usage:
//   swift scripts/generate-social-preview.swift <icon.png> <output.png>
let W = 1280, H = 640
let size = NSSize(width: W, height: H)

guard CommandLine.arguments.count >= 3 else { fatalError("usage: <icon.png> <output.png>") }
let iconPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
guard let icon = NSImage(contentsOfFile: iconPath) else { fatalError("cannot load icon \(iconPath)") }

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("rep") }
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// background: light vertical gradient with a faint teal tint
let bg = NSGradient(colors: [
    NSColor(srgbRed: 0.97, green: 0.99, blue: 0.99, alpha: 1),
    NSColor(srgbRed: 0.90, green: 0.95, blue: 0.96, alpha: 1)
])!
bg.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// app icon on the left, vertically centered
let iconSize: CGFloat = 320
let iconX: CGFloat = 96
let iconY = (CGFloat(H) - iconSize) / 2
icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))

// text block on the right
let teal = NSColor(srgbRed: 0.12, green: 0.56, blue: 0.64, alpha: 1)
let label = NSColor.black.withAlphaComponent(0.84)
let secondary = NSColor.black.withAlphaComponent(0.5)
let textX = iconX + iconSize + 70
let textW = CGFloat(W) - textX - 80

// y is the distance from the bottom edge of the rect to the image bottom (AppKit's
// non-flipped space); text fills from the top of the rect downward. The three bands
// below do not overlap.
func draw(_ s: String, font: NSFont, color: NSColor, atY y: CGFloat, height: CGFloat) {
    let para = NSMutableParagraphStyle(); para.alignment = .left; para.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    (s as NSString).draw(in: NSRect(x: textX, y: y, width: textW, height: height), withAttributes: attrs)
}

// Title (top band)
draw("MacScrub", font: .systemFont(ofSize: 84, weight: .bold), color: label, atY: 392, height: 120)
// Tagline (middle band, up to 3 lines)
draw("Safely clean your Mac’s keyboard and\ntrackpad — input locked until you’re done.",
     font: .systemFont(ofSize: 30, weight: .regular), color: secondary, atY: 196, height: 100)
// Meta line (bottom band)
draw("macOS 14+   ·   notarized   ·   free & open source",
     font: .systemFont(ofSize: 22, weight: .semibold), color: teal, atY: 132, height: 36)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(W)x\(H))")
