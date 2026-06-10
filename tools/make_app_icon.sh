#!/bin/sh
# Renders Resources/AppIcon.icns: a macOS rounded-rect tile with a waveform glyph.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/render_icon.swift" <<'SWIFT'
import AppKit

let canvas = 1024
let outputPath = CommandLine.arguments[1]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
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
    starting: NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.98, alpha: 1),
    ending: NSColor(calibratedRed: 0.08, green: 0.05, blue: 0.30, alpha: 1)
)!.draw(in: tilePath, angle: -75)

let configuration = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let white = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }

    let glyphWidth: CGFloat = 480
    let glyphHeight = glyphWidth * symbol.size.height / symbol.size.width
    white.draw(in: NSRect(
        x: (CGFloat(canvas) - glyphWidth) / 2,
        y: (CGFloat(canvas) - glyphHeight) / 2,
        width: glyphWidth,
        height: glyphHeight
    ))
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
echo "Wrote $ROOT/Resources/AppIcon.icns"
