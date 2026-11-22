import AppKit

// Shared, locally rendered artwork for the app, installer, and download page.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = root.appendingPathComponent("docs/assets", isDirectory: true)
let packaging = root.appendingPathComponent("Assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: packaging, withIntermediateDirectories: true)

func color(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1)
}
let ink = color(0x172024)
let mint = color(0xA1EDCB)
let muted = color(0x687478)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, fill: NSColor = ink,
          width: CGFloat = 700, align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size * 3),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: fill, .paragraphStyle: paragraph])
}
func icon(x: CGFloat, y: CGFloat, size: CGFloat) {
    rounded(NSRect(x: x, y: y, width: size, height: size), size * 0.23, ink)
    let track = NSBezierPath()
    track.appendArc(withCenter: NSPoint(x: x + size / 2, y: y + size / 2),
                    radius: size * 0.30, startAngle: 0, endAngle: 360)
    track.lineWidth = size * 0.065
    color(0x3D514D).setStroke(); track.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: x + size / 2, y: y + size / 2),
                  radius: size * 0.30, startAngle: -90, endAngle: 208, clockwise: false)
    arc.lineWidth = size * 0.065; arc.lineCapStyle = .round
    mint.setStroke(); arc.stroke()
    text(">_", x: x, y: y + size * 0.315, size: size * 0.245,
         weight: .semibold, fill: .white, width: size, align: .center)
}
func arrow(x: CGFloat, y: CGFloat, width: CGFloat = 90) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: y)); path.line(to: NSPoint(x: x + width, y: y))
    path.move(to: NSPoint(x: x + width - 15, y: y - 14))
    path.line(to: NSPoint(x: x + width, y: y)); path.line(to: NSPoint(x: x + width - 15, y: y + 14))
    path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round
    color(0x88A99B).setStroke(); path.stroke()
}
func folder(x: CGFloat, y: CGFloat, size: CGFloat) {
    rounded(NSRect(x: x, y: y + size * 0.1, width: size * 0.48, height: size * 0.3), 7, color(0x72C4F4))
    rounded(NSRect(x: x, y: y + size * 0.23, width: size, height: size * 0.66), 9, color(0x8BD3FA))
    text("A", x: x, y: y + size * 0.28, size: size * 0.40,
         weight: .light, fill: color(0x3E8BBC), width: size, align: .center)
}
func render(_ url: URL, width: Int, height: Int, scale: Int = 2, draw: () -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: CGFloat(height * scale))
    cg.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    rep.size = NSSize(width: width, height: height)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try render(assets.appendingPathComponent("app-icon.png"), width: 512, height: 512) {
    icon(x: 16, y: 16, size: 480)
}
try render(packaging.appendingPathComponent("dmg-background.png"), width: 720, height: 460) {
    color(0xF5F8F7).setFill(); NSRect(x: 0, y: 0, width: 720, height: 460).fill()
    text("TOKEN CODEX INFO", x: 40, y: 28, size: 13, weight: .semibold, fill: muted)
    text("One drag. Ready to go.", x: 0, y: 82, size: 32, weight: .semibold, width: 720, align: .center)
    text("Drag the app into Applications to install.", x: 0, y: 130, size: 16, fill: muted, width: 720, align: .center)
    arrow(x: 315, y: 257)
    text("Then open Token Codex Info from Applications.", x: 0, y: 369, size: 15, fill: muted, width: 720, align: .center)
    text("Your Codex limits, right in your menu bar.", x: 0, y: 401, size: 13, fill: muted, width: 720, align: .center)
}
try render(assets.appendingPathComponent("install-guide.png"), width: 900, height: 540) {
    color(0xEAF1EE).setFill(); NSRect(x: 0, y: 0, width: 900, height: 540).fill()
    rounded(NSRect(x: 60, y: 40, width: 780, height: 460), 18, color(0xFFFFFF))
    for (index, tint) in [0xFF6058, 0xFFBD2E, 0x28C840].enumerated() {
        color(UInt32(tint)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 82 + index * 20, y: 60, width: 11, height: 11)).fill()
    }
    text("Token Codex Info", x: 0, y: 55, size: 14, weight: .medium, width: 900, align: .center)
    text("One drag. Ready to go.", x: 0, y: 125, size: 32, weight: .semibold, width: 900, align: .center)
    text("Drag the app into Applications to install.", x: 0, y: 175, size: 17, fill: muted, width: 900, align: .center)
    icon(x: 230, y: 258, size: 104); folder(x: 570, y: 249, size: 112)
    arrow(x: 405, y: 307)
    text("Token Codex Info", x: 183, y: 380, size: 15, width: 200, align: .center)
    text("Applications", x: 526, y: 380, size: 15, width: 200, align: .center)
    text("Then launch the app from Applications.", x: 0, y: 449, size: 14, fill: muted, width: 900, align: .center)
}
try render(assets.appendingPathComponent("app-preview.png"), width: 1200, height: 620) {
    color(0xEAF1EE).setFill(); NSRect(x: 0, y: 0, width: 1200, height: 620).fill()
    rounded(NSRect(x: 85, y: 65, width: 1030, height: 490), 22, color(0xD0E0D9))
    rounded(NSRect(x: 85, y: 65, width: 1030, height: 38), 14, color(0xF8FBF9))
    text("●    Finder    File    Edit    View    Go", x: 105, y: 75, size: 14, weight: .medium)
    rounded(NSRect(x: 824, y: 70, width: 127, height: 28), 7, ink)
    text("83% · 2:14", x: 824, y: 75, size: 15, weight: .semibold, fill: .white, width: 127, align: .center)
    text("Sun  9:41", x: 983, y: 75, size: 14)
    rounded(NSRect(x: 742, y: 115, width: 225, height: 218), 10, .white)
    text("Reported limits", x: 760, y: 130, size: 13, fill: muted)
    text("Data & Settings…", x: 760, y: 163, size: 16)
    text("✓   Launch at Login", x: 760, y: 211, size: 16)
    text("     Refresh", x: 760, y: 256, size: 16)
    text("     Quit", x: 760, y: 296, size: 16)
    icon(x: 150, y: 194, size: 90)
    text("Your Codex limits.\nA glance away.", x: 150, y: 312, size: 40, weight: .semibold)
    text("Remaining usage and reset time, in your menu bar.", x: 150, y: 443, size: 18, fill: muted)
    text("Illustrative preview", x: 85, y: 575, size: 13, fill: muted)
}
print("Rendered app, installer, and page artwork.")
