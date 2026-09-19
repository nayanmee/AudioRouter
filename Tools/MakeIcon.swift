import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
        cg.setFillColor(NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.16, alpha: 1).cgColor)
        cg.addPath(CGPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928), cornerWidth: 205, cornerHeight: 205, transform: nil))
        cg.fillPath()
        cg.setStrokeColor(NSColor.systemCyan.cgColor)
        cg.setLineWidth(55); cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.move(to: CGPoint(x: 505, y: 512)); cg.addLine(to: CGPoint(x: 670, y: 512))
        cg.addCurve(to: CGPoint(x: 800, y: 720), control1: CGPoint(x: 770, y: 512), control2: CGPoint(x: 710, y: 720))
        cg.strokePath()
        cg.move(to: CGPoint(x: 650, y: 512))
        cg.addCurve(to: CGPoint(x: 800, y: 305), control1: CGPoint(x: 770, y: 512), control2: CGPoint(x: 710, y: 305))
        cg.strokePath()
        cg.setFillColor(NSColor.white.cgColor)
        cg.move(to: CGPoint(x: 235, y: 415)); cg.addLine(to: CGPoint(x: 330, y: 415)); cg.addLine(to: CGPoint(x: 485, y: 300))
        cg.addLine(to: CGPoint(x: 485, y: 725)); cg.addLine(to: CGPoint(x: 330, y: 610)); cg.addLine(to: CGPoint(x: 235, y: 610)); cg.closePath(); cg.fillPath()
        cg.setFillColor(NSColor.systemCyan.cgColor)
        for y: CGFloat in [305, 720] { cg.fillEllipse(in: CGRect(x: 752, y: y-48, width: 96, height: 96)) }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: destination).appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
// Standard ICNS container using PNG representations. This avoids requiring the
// IconServices helper during sandboxed builds. Type tags come from IconStorage.h.
func bigEndian(_ number: UInt32) -> Data {
    var value = number.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var chunks = Data()
for (tag, file) in [("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: URL(fileURLWithPath: destination).appendingPathComponent(file))
    chunks.append(Data(tag.utf8)); chunks.append(bigEndian(UInt32(png.count + 8))); chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(UInt32(chunks.count + 8))); icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
