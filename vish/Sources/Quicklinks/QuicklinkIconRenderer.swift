import AppKit

@MainActor
enum QuicklinkIconRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for record: QuicklinkRecord, size: CGFloat) -> NSImage? {
        image(for: record.resultIcon, size: size)
    }

    static func image(for icon: ResultIcon?, size: CGFloat) -> NSImage? {
        guard let icon else { return nil }

        switch icon {
        case .imageData(let data):
            return customImage(data, size: size)
        case .quicklink(let kind):
            return builtInImage(kind, size: size)
        case .symbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.size = NSSize(width: size, height: size)
            return image
        }
    }

    private static func builtInImage(_ kind: QuicklinkIconKind, size: CGFloat) -> NSImage {
        let key = "quicklink:\(kind.rawValue):\(Int(size.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: NSImage
        switch kind {
        case .github:
            image = drawGitHub(size: size)
        case .maps:
            image = drawMaps(size: size)
        case .youtube:
            image = drawYouTube(size: size)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func customImage(_ data: Data, size: CGFloat) -> NSImage? {
        let key = "custom:\(data.count):\(data.hashValue):\(Int(size.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let source = NSImage(data: data), let image = fit(source, size: size) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func drawYouTube(size: CGFloat) -> NSImage {
        draw(size: size) { rect in
            NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.05, alpha: 1).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.18),
                xRadius: size * 0.20,
                yRadius: size * 0.20
            ).fill()

            NSColor.white.setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: size * 0.43, y: size * 0.33))
            path.line(to: NSPoint(x: size * 0.43, y: size * 0.67))
            path.line(to: NSPoint(x: size * 0.70, y: size * 0.50))
            path.close()
            path.fill()
        }
    }

    private static func drawGitHub(size: CGFloat) -> NSImage {
        draw(size: size) { rect in
            NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.05, dy: size * 0.05)).fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.34, weight: .black),
                .foregroundColor: NSColor.white
            ]
            let text = NSString(string: "GH")
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 - size * 0.01),
                withAttributes: attributes
            )
        }
    }

    private static func drawMaps(size: CGFloat) -> NSImage {
        draw(size: size) { rect in
            NSColor(calibratedRed: 0.12, green: 0.50, blue: 1.0, alpha: 1).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06),
                xRadius: size * 0.22,
                yRadius: size * 0.22
            ).fill()

            NSColor.white.setFill()
            let pin = NSBezierPath()
            pin.appendOval(in: NSRect(x: size * 0.32, y: size * 0.40, width: size * 0.36, height: size * 0.36))
            pin.move(to: NSPoint(x: size * 0.50, y: size * 0.16))
            pin.line(to: NSPoint(x: size * 0.37, y: size * 0.46))
            pin.line(to: NSPoint(x: size * 0.63, y: size * 0.46))
            pin.close()
            pin.fill()

            NSColor(calibratedRed: 0.12, green: 0.50, blue: 1.0, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: size * 0.43, y: size * 0.51, width: size * 0.14, height: size * 0.14)).fill()
        }
    }

    private static func draw(size: CGFloat, _ drawBlock: (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        drawBlock(NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func fit(_ source: NSImage, size: CGFloat) -> NSImage? {
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(size / sourceSize.width, size / sourceSize.height)
        let fitted = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let target = NSImage(size: NSSize(width: size, height: size))
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: (size - fitted.width) / 2, y: (size - fitted.height) / 2, width: fitted.width, height: fitted.height),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1
        )
        target.unlockFocus()
        target.isTemplate = false
        return target
    }
}
