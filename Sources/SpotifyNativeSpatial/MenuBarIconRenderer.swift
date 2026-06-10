import AppKit

/// Renders the Spacify earbuds glyph as a template menu bar image, so it
/// follows the menu bar's light/dark appearance like a system icon.
@MainActor
enum MenuBarIconRenderer {
    static let idle = render(filled: false)
    static let active = render(filled: true)

    private static func render(filled: Bool) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let scale = rect.width / 24

            for path in earbudsPaths(scale: scale) {
                path.lineWidth = 2 * scale
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                NSColor.black.set()
                if filled {
                    path.fill()
                }
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The earbuds mark from a 24x24 viewbox, scaled into menu bar points.
    private static func earbudsPaths(scale: CGFloat) -> [NSBezierPath] {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: x * scale, y: (24 - y) * scale)
        }

        func curve(_ path: NSBezierPath, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            path.curve(to: p(x, y), controlPoint1: p(x1, y1), controlPoint2: p(x2, y2))
        }

        let leftBud = NSBezierPath()
        leftBud.move(to: p(2, 7.625))
        curve(leftBud, 2, 9.90317, 3.84683, 11.75, 6.125, 11.75)
        curve(leftBud, 6.43089, 11.75, 6.58383, 11.75, 6.66308, 11.7773)
        curve(leftBud, 6.82888, 11.8345, 6.91545, 11.9211, 6.97266, 12.0869)
        curve(leftBud, 7, 12.1662, 7, 12.2903, 7, 12.5386)
        leftBud.line(to: p(7, 18.875))
        curve(leftBud, 7, 19.7725, 7.72754, 20.5, 8.625, 20.5)
        curve(leftBud, 9.52246, 20.5, 10.25, 19.7725, 10.25, 18.875)
        leftBud.line(to: p(10.25, 7.625))
        curve(leftBud, 10.25, 5.34683, 8.40317, 3.5, 6.125, 3.5)
        curve(leftBud, 3.84683, 3.5, 2, 5.34683, 2, 7.625)
        leftBud.close()

        let rightBud = NSBezierPath()
        rightBud.move(to: p(22, 7.625))
        curve(rightBud, 22, 9.90317, 20.1532, 11.75, 17.875, 11.75)
        curve(rightBud, 17.5691, 11.75, 17.4162, 11.75, 17.3369, 11.7773)
        curve(rightBud, 17.1711, 11.8345, 17.0845, 11.9211, 17.0273, 12.0869)
        curve(rightBud, 17, 12.1662, 17, 12.2903, 17, 12.5386)
        rightBud.line(to: p(17, 18.875))
        curve(rightBud, 17, 19.7725, 16.2725, 20.5, 15.375, 20.5)
        curve(rightBud, 14.4775, 20.5, 13.75, 19.7725, 13.75, 18.875)
        rightBud.line(to: p(13.75, 7.625))
        curve(rightBud, 13.75, 5.34683, 15.5968, 3.5, 17.875, 3.5)
        curve(rightBud, 20.1532, 3.5, 22, 5.34683, 22, 7.625)
        rightBud.close()

        return [leftBud, rightBud]
    }
}
