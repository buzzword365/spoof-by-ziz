// Draws the 1024px app icon: a dark rounded square, a purple-to-cyan map pin, and "BY ZIZ".
// Usage: swift make_icon.swift out.png

import Cocoa

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Background (macOS icon grid: 824px square with ~185px corner radius, centred).
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.09, green: 0.08, blue: 0.16, alpha: 1),
                    NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)])!.draw(in: bg, angle: -90)

// Soft purple glow behind the pin.
ctx.saveGState()
bg.addClip()
NSGradient(colors: [NSColor(red: 0.49, green: 0.36, blue: 1, alpha: 0.55), .clear])!
    .draw(fromCenter: NSPoint(x: 512, y: 600), radius: 0, toCenter: NSPoint(x: 512, y: 600), radius: 420, options: [])
ctx.restoreGState()

// Map pin: circle on top, tapering to a point.
let cx: CGFloat = 512, cy: CGFloat = 610, r: CGFloat = 200, tipY: CGFloat = 290
let pin = NSBezierPath()
pin.move(to: NSPoint(x: cx, y: tipY))
pin.curve(to: NSPoint(x: cx - r, y: cy), controlPoint1: NSPoint(x: cx - 60, y: tipY + 110), controlPoint2: NSPoint(x: cx - r, y: cy - 120))
pin.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 180, endAngle: 0, clockwise: true)
pin.curve(to: NSPoint(x: cx, y: tipY), controlPoint1: NSPoint(x: cx + r, y: cy - 120), controlPoint2: NSPoint(x: cx + 60, y: tipY + 110))
pin.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.6).cgColor)
NSGradient(colors: [NSColor(red: 0.49, green: 0.36, blue: 1, alpha: 1),
                    NSColor(red: 0.35, green: 0.49, blue: 1, alpha: 1),
                    NSColor(red: 0, green: 0.83, blue: 1, alpha: 1)])!.draw(in: pin, angle: -35)
ctx.restoreGState()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: cx - 72, y: cy - 72, width: 144, height: 144)).fill()

// "BY ZIZ"
let text = "BY ZIZ" as NSString
let font = NSFont.systemFont(ofSize: 120, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .kern: -4]
let textSize = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: 140), withAttributes: attrs)

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
