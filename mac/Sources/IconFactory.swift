import AppKit

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Brand colours shared by the break screen and the branded windows (same values as the Windows app).
enum Brand {
    static let bg = rgb(14, 22, 28)
    static let panel = rgb(22, 32, 40)
    static let accent = rgb(70, 205, 180)
    static let teal = rgb(30, 158, 138)
    static let soft = rgb(200, 212, 220)
    static let dim = rgb(130, 145, 155)
    static let warn = rgb(240, 170, 80)
}

/// Draws the ScreenRest "eye" in code, so no image files are needed.
enum IconFactory {
    static let brand = Brand.teal
    static let paused = rgb(120, 128, 136)
    static let due = rgb(232, 140, 40)

    /// The eye shape (white almond with a coloured pupil) inside `r`, in a flipped (top-left origin) context.
    private static func drawEye(in r: CGRect, pupil: NSColor) {
        let s = r.width
        let w = s * 0.74, h = s * 0.42
        let x = r.minX + (s - w) / 2, y = r.minY + (s - h) / 2, mid = r.minY + s / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: mid))
        path.curve(to: NSPoint(x: x + w, y: mid),
                   controlPoint1: NSPoint(x: x + w * 0.25, y: y - h * 0.2),
                   controlPoint2: NSPoint(x: x + w * 0.75, y: y - h * 0.2))
        path.curve(to: NSPoint(x: x, y: mid),
                   controlPoint1: NSPoint(x: x + w * 0.75, y: y + h * 1.2),
                   controlPoint2: NSPoint(x: x + w * 0.25, y: y + h * 1.2))
        NSColor.white.setFill()
        path.fill()
        let pr = s * 0.14
        pupil.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.midX - pr, y: mid - pr, width: 2 * pr, height: 2 * pr)).fill()
    }

    /// Round coloured eye, like the Windows tray icon. Used for the menu bar (teal / grey / orange).
    static func roundEye(_ size: CGFloat, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let p = rect.width * 0.03
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: p, dy: p)).fill()
            drawEye(in: rect, pupil: color)
            return true
        }
    }

    /// Menu bar icon: 18 pt image with a 16 pt eye.
    static func menuBarIcon(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let r = NSRect(x: 1, y: 1, width: 16, height: 16)
            color.setFill()
            NSBezierPath(ovalIn: r).fill()
            drawEye(in: r, pupil: color)
            return true
        }
    }

    /// macOS-style app icon: rounded-square teal tile (Apple's 824/1024 grid) with the eye.
    static func appIcon(_ size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let inset = rect.width * 100 / 1024
            let tile = rect.insetBy(dx: inset, dy: inset)
            let radius = tile.width * 0.225
            let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = rect.width * 0.02
            shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.01)
            shadow.set()
            Brand.teal.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGradient(starting: rgb(64, 196, 172), ending: rgb(22, 128, 112))?.draw(in: shape, angle: 90)
            let e = tile.insetBy(dx: tile.width * 0.06, dy: tile.width * 0.06)
            drawEye(in: e, pupil: rgb(24, 136, 120))
            return true
        }
    }

    /// Writes an .iconset folder (for `iconutil -c icns`), used by build.sh.
    static func writeIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                rep.size = NSSize(width: px, height: px)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                appIcon(CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
