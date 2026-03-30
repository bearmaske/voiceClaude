#!/usr/bin/swift
import AppKit

// Generate app icon PNGs for macOS .iconset
// Draws a microphone on a gradient background

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
    (1024, "icon_512x512@2x.png"),
]

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"

// Create output directory
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // --- Rounded rect clip (macOS icon shape) ---
    let radius = s * 0.185
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.clip()

    // --- Gradient background: deep purple to warm coral ---
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(colorSpace: colorSpace, components: [0.30, 0.10, 0.55, 1.0])!,  // deep purple
        CGColor(colorSpace: colorSpace, components: [0.55, 0.20, 0.65, 1.0])!,  // mid purple
        CGColor(colorSpace: colorSpace, components: [0.85, 0.35, 0.45, 1.0])!,  // warm coral
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.5, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: s, y: 0),
            options: []
        )
    }

    // --- Subtle inner glow / highlight ---
    context.saveGState()
    let glowColor = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.08])!
    context.setFillColor(glowColor)
    let glowRect = CGRect(x: s * 0.1, y: s * 0.5, width: s * 0.8, height: s * 0.45)
    let glowPath = CGPath(ellipseIn: glowRect, transform: nil)
    context.addPath(glowPath)
    context.fillPath()
    context.restoreGState()

    // --- Draw microphone ---
    let white = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.95])!
    context.setFillColor(white)
    context.setStrokeColor(white)
    context.setLineWidth(s * 0.028)
    context.setLineCap(.round)

    let cx = s * 0.5  // center x

    // Mic body (rounded rectangle)
    let micW = s * 0.22
    let micH = s * 0.34
    let micX = cx - micW / 2
    let micY = s * 0.42
    let micRadius = micW / 2

    let micRect = CGRect(x: micX, y: micY, width: micW, height: micH)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micRadius, cornerHeight: micRadius, transform: nil)
    context.addPath(micPath)
    context.fillPath()

    // Mic arc (the holder curve below the mic)
    let arcCenterY = micY + micH * 0.15
    let arcRadius = s * 0.18
    let lineW = s * 0.032

    context.setLineWidth(lineW)
    context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0])!)

    // Draw the U-shaped arc
    let arcStart = CGFloat.pi * 0.15
    let arcEnd = CGFloat.pi * 0.85
    context.addArc(center: CGPoint(x: cx, y: arcCenterY + s * 0.08),
                   radius: arcRadius,
                   startAngle: arcStart,
                   endAngle: arcEnd,
                   clockwise: false)
    context.strokePath()

    // Vertical stem from arc bottom to base
    let stemTopY = arcCenterY + s * 0.08 - arcRadius * sin(CGFloat.pi * 0.5) + s * 0.01
    let stemBottomY = s * 0.20
    context.move(to: CGPoint(x: cx, y: stemTopY))
    context.addLine(to: CGPoint(x: cx, y: stemBottomY))
    context.strokePath()

    // Base horizontal line
    let baseW = s * 0.16
    context.move(to: CGPoint(x: cx - baseW / 2, y: stemBottomY))
    context.addLine(to: CGPoint(x: cx + baseW / 2, y: stemBottomY))
    context.strokePath()

    // --- Sound wave arcs on sides ---
    let waveColor = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.5])!
    context.setStrokeColor(waveColor)
    context.setLineWidth(s * 0.018)

    let waveCenterY = micY + micH * 0.5

    // Left waves
    for i in 1...2 {
        let r = s * (0.18 + CGFloat(i) * 0.06)
        let alpha = 0.5 - CGFloat(i) * 0.15
        let wc = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, alpha])!
        context.setStrokeColor(wc)
        context.addArc(center: CGPoint(x: cx, y: waveCenterY),
                       radius: r,
                       startAngle: CGFloat.pi * 0.6,
                       endAngle: CGFloat.pi * 0.9,
                       clockwise: false)
        context.strokePath()
    }

    // Right waves
    for i in 1...2 {
        let r = s * (0.18 + CGFloat(i) * 0.06)
        let alpha = 0.5 - CGFloat(i) * 0.15
        let wc = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, alpha])!
        context.setStrokeColor(wc)
        context.addArc(center: CGPoint(x: cx, y: waveCenterY),
                       radius: r,
                       startAngle: CGFloat.pi * 0.1,
                       endAngle: CGFloat.pi * 0.4,
                       clockwise: false)
        context.strokePath()
    }

    image.unlockFocus()
    return image
}

for (size, filename) in sizes {
    let image = drawIcon(size: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(filename)")
        continue
    }
    let filePath = (outputDir as NSString).appendingPathComponent(filename)
    try! pngData.write(to: URL(fileURLWithPath: filePath))
    print("Generated \(filename) (\(size)x\(size))")
}

print("Done! Icon set at: \(outputDir)")
