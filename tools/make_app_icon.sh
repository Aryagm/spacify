#!/bin/sh
# Renders Resources/AppIcon.icns: a macOS rounded-rect tile with an earbuds
# glyph (converted from the project's SVG mark).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/render_icon.swift" <<'SWIFT'
import AppKit

let canvas: CGFloat = 1024
let outputPath = CommandLine.arguments[1]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's macOS icon grid: 832pt tile centered in a 1024pt canvas.
let tile = NSRect(x: 96, y: 96, width: 832, height: 832)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
NSGradient(
    starting: NSColor(calibratedRed: 0.45, green: 0.27, blue: 1.00, alpha: 1),
    ending: NSColor(calibratedRed: 0.07, green: 0.04, blue: 0.28, alpha: 1)
)!.draw(in: tilePath, angle: -70)

// Soft glow behind the glyph, clipped to the tile.
tilePath.setClip()
NSGradient(
    starting: NSColor(calibratedWhite: 1, alpha: 0.16),
    ending: NSColor(calibratedWhite: 1, alpha: 0)
)!.draw(
    fromCenter: NSPoint(x: canvas / 2, y: canvas / 2), radius: 0,
    toCenter: NSPoint(x: canvas / 2, y: canvas / 2), radius: 380,
    options: []
)

// Earbuds glyph, converted from a 24x24 SVG (stroke-width 2, round caps).
let scale: CGFloat = 24
let offset = (canvas - 24 * scale) / 2

func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: offset + x * scale, y: offset + (24 - y) * scale)
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

NSColor.white.set()
for path in [leftBud, rightBud] {
    path.lineWidth = 2 * scale
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$WORK/render_icon.swift" "$WORK/master.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
sips -s format png --resampleWidth 512 "$ROOT/Resources/AppIcon.icns" --out "$ROOT/Resources/AppIcon.png" > /dev/null
echo "Wrote $ROOT/Resources/AppIcon.icns and AppIcon.png"
