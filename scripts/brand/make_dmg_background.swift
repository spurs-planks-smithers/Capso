// Fork: draws the Nextshot disk image background.
//
// Finder always draws a disk image window that has a background picture in
// light mode, with black icon labels, so the picture stays light. The
// picture carries the instruction itself: macOS 26 can draw the Applications
// alias icon blank (create-dmg issue #202), and the title and arrow must still
// say what to do.
//
// The layout matches scripts/dmg-settings.py (dmgbuild): a 660 by 400 point
// window, 128 point icons centered at (170, 190) and (490, 190). Change both
// together.
//
// Usage: swift scripts/brand/make_dmg_background.swift <output.tiff>
// Writes a 1x and a 2x picture into one TIFF, so Retina screens stay sharp.
import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
let appCenter = CGPoint(x: 170, y: 190)
let applicationsCenter = CGPoint(x: 490, y: 190)

let graphite = NSColor(srgbRed: 0x23 / 255, green: 0x28 / 255, blue: 0x2C / 255, alpha: 1)
let gray = NSColor(srgbRed: 0x5B / 255, green: 0x66 / 255, blue: 0x6E / 255, alpha: 1)
// The brand teal (#3CCDBE) is too light on a white field, so the arrow uses a
// darker teal with the same hue.
let teal = NSColor(srgbRed: 0x1F / 255, green: 0xA3 / 255, blue: 0x96 / 255, alpha: 1)
let fieldTop = NSColor(srgbRed: 0xFC / 255, green: 0xFD / 255, blue: 0xFD / 255, alpha: 1)
let fieldBottom = NSColor(srgbRed: 0xEC / 255, green: 0xF1 / 255, blue: 0xF1 / 255, alpha: 1)

let title = "Drag Nextshot to Applications"
// The second line sits under the title, not at the bottom: when Finder
// opens the image as a tab, the window keeps its old size and can cut off
// the bottom of the picture. Finder cannot replace a running app, so an
// update starts from the copy on the image (DiskImageInstaller), not from a
// drag.
let subtitle = "Already installed? Double-click Nextshot here to update."

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Draw in Finder's coordinates: origin top left, y down.
    let cg = context.cgContext
    cg.translateBy(x: 0, y: height)
    cg.scaleBy(x: 1, y: -1)

    NSGradient(starting: fieldTop, ending: fieldBottom)!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    drawCentered(title, y: 50, font: .systemFont(ofSize: 20, weight: .semibold), color: graphite)
    drawCentered(subtitle, y: 82, font: .systemFont(ofSize: 13, weight: .regular), color: gray)
    drawArrow(in: cg)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Draws one line of text centered across the window, with its middle at `y`.
func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let line = NSAttributedString(string: text, attributes: attributes)
    let size = line.size()
    // The context is flipped, so draw the text through a flipped transform
    // to keep the glyphs upright.
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: (width - size.width) / 2, yBy: y + size.height / 2)
    transform.scaleX(by: 1, yBy: -1)
    transform.concat()
    line.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
}

/// A straight shaft with a chevron head, round ends, like the chevron in the mark.
func drawArrow(in cg: CGContext) {
    let start = appCenter.x + 92
    let end = applicationsCenter.x - 92
    let y = appCenter.y
    let head: CGFloat = 16

    cg.setStrokeColor(teal.cgColor)
    cg.setLineWidth(7)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)

    cg.move(to: CGPoint(x: start, y: y))
    cg.addLine(to: CGPoint(x: end, y: y))
    cg.strokePath()

    cg.move(to: CGPoint(x: end - head, y: y - head))
    cg.addLine(to: CGPoint(x: end, y: y))
    cg.addLine(to: CGPoint(x: end - head, y: y + head))
    cg.strokePath()
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift make_dmg_background.swift <output.tiff>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let reps = [render(scale: 1), render(scale: 2)]
guard let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0) else {
    FileHandle.standardError.write(Data("Could not encode the TIFF.\n".utf8))
    exit(1)
}
try data.write(to: output)
// A PNG copy of the 2x picture, for review.
if let png = reps[1].representation(using: .png, properties: [:]) {
    try png.write(to: output.deletingPathExtension().appendingPathExtension("png"))
}
print("Wrote \(output.path)")
