#!/usr/bin/env swift
import AppKit
import CoreText
import Foundation

/// Renders a minimal app icon — accent-coloured rounded-rect with a white "N".
/// Generates the required sizes and runs `iconutil` to produce NARC.icns.

let size: CGFloat = 1024
let inset: CGFloat = size * 0.1
let backgroundRect = NSRect(
    x: inset,
    y: inset,
    width: size - inset * 2,
    height: size - inset * 2
)

// Render at 1x so the output is exactly 1024×1024 pixels.
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
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

// Accent-colour rounded-rect background
let bgPath = NSBezierPath(
    roundedRect: backgroundRect,
    xRadius: size * 0.22,
    yRadius: size * 0.22
)
NSColor.controlAccentColor.setFill()
bgPath.fill()

// Center the visible glyph outline, not the font's typographic line box.
// The previous 0.38 multiplier placed the mark visibly below the icon center.
let appKitFont = NSFont.systemFont(ofSize: size * 0.50, weight: .heavy)
let coreTextFont = CTFontCreateWithName(
    appKitFont.fontName as CFString,
    appKitFont.pointSize,
    nil
)
var character: UniChar = 78 // "N"
var glyph = CGGlyph()
guard CTFontGetGlyphsForCharacters(coreTextFont, &character, &glyph, 1),
      let glyphPath = CTFontCreatePathForGlyph(coreTextFont, glyph, nil) else {
    print("❌ Failed to create the N glyph outline")
    exit(1)
}

let glyphBounds = glyphPath.boundingBoxOfPath
var centerTransform = CGAffineTransform(
    translationX: backgroundRect.midX - glyphBounds.midX,
    y: backgroundRect.midY - glyphBounds.midY
)
guard let centeredGlyphPath = glyphPath.copy(using: &centerTransform),
      let context = NSGraphicsContext.current?.cgContext else {
    print("❌ Failed to center the N glyph outline")
    exit(1)
}

context.addPath(centeredGlyphPath)
context.setFillColor(NSColor.white.cgColor)
context.fillPath()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("❌ Failed to render icon PNG")
    exit(1)
}

let iconset = "build/NARC.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Write the 1024×1024 source, then use sips to generate all required sizes.
let src = "\(iconset)/icon_512x512@2x.png"
try png.write(to: URL(fileURLWithPath: src))

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
]

for (px, name) in sizes {
    let task = Process()
    task.launchPath = "/usr/bin/sips"
    task.arguments = ["-z", "\(px)", "\(px)", src, "--out", "\(iconset)/\(name)"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", "-o", "build/NARC.icns", iconset]
try? task.run()
task.waitUntilExit()

if fm.fileExists(atPath: "build/NARC.icns") {
    print("✅ NARC.icns generated")
} else {
    print("❌ iconutil failed")
    exit(1)
}
