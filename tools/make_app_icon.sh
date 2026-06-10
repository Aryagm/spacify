#!/bin/sh
# Renders Resources/AppIcon.icns: a macOS rounded-rect tile with a waveform
# inside a tilted orbit ring (sound placed in 3D space).
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

// Soft glow behind the mark, clipped to the tile.
tilePath.setClip()
NSGradient(
    starting: NSColor(calibratedWhite: 1, alpha: 0.18),
    ending: NSColor(calibratedWhite: 1, alpha: 0)
)!.draw(
    fromCenter: NSPoint(x: canvas / 2, y: canvas / 2 + 40), radius: 0,
    toCenter: NSPoint(x: canvas / 2, y: canvas / 2 + 40), radius: 380,
    options: []
)

let center = NSPoint(x: canvas / 2, y: canvas / 2)

// Orbit ring: a unit-circle arc scaled to an ellipse, tilted. The upper half
// passes behind the waveform, the lower half in front of it.
func orbitArc(from startAngle: CGFloat, to endAngle: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendArc(withCenter: .zero, radius: 1, startAngle: startAngle, endAngle: endAngle)
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: -16)
    transform.scaleX(by: 286, yBy: 112)
    path.transform(using: transform as AffineTransform)
    path.lineWidth = 30
    path.lineCapStyle = .round
    return path
}

NSColor(calibratedWhite: 1, alpha: 0.38).set()
orbitArc(from: 8, to: 172).stroke()

// Waveform bars.
let barWidth: CGFloat = 56
let barHeights: [CGFloat] = [164, 276, 392, 276, 164]
NSColor.white.set()
for (index, height) in barHeights.enumerated() {
    let x = center.x + CGFloat(index - 2) * 96 - barWidth / 2
    NSBezierPath(
        roundedRect: NSRect(x: x, y: center.y - height / 2, width: barWidth, height: height),
        xRadius: barWidth / 2,
        yRadius: barWidth / 2
    ).fill()
}

NSColor(calibratedWhite: 1, alpha: 0.96).set()
orbitArc(from: 188, to: 352).stroke()

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
