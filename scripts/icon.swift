import AppKit

let destination = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let outline = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.26, alpha: 1), ending: NSColor(calibratedRed: 0.045, green: 0.07, blue: 0.13, alpha: 1))!.draw(in: outline, angle: 90)
    let monitor = NSBezierPath(roundedRect: NSRect(x: 190, y: 285, width: 644, height: 450), xRadius: 55, yRadius: 55)
    NSColor(calibratedWhite: 0.94, alpha: 1).setStroke(); monitor.lineWidth = 36; monitor.stroke()
    let stand = NSBezierPath(); stand.move(to: NSPoint(x: 512, y: 285)); stand.line(to: NSPoint(x: 512, y: 195)); stand.move(to: NSPoint(x: 392, y: 195)); stand.line(to: NSPoint(x: 632, y: 195)); stand.lineWidth = 36; stand.lineCapStyle = .round; stand.stroke()
    NSColor(calibratedRed: 1, green: 0.55, blue: 0.25, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 430, y: 428, width: 164, height: 164)).fill()
    NSColor(calibratedRed: 1, green: 0.55, blue: 0.25, alpha: 1).setStroke()
    for i in 0..<8 {
        let angle = Double(i) * .pi / 4
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 512 + 118 * cos(angle), y: 510 + 118 * sin(angle)))
        line.line(to: NSPoint(x: 512 + 154 * cos(angle), y: 510 + 154 * sin(angle)))
        line.lineWidth = 25; line.lineCapStyle = .round; line.stroke()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
