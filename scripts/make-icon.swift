#!/usr/bin/env swift
import AppKit

// Generates a 1024x1024 PNG app icon master at the path given as argv[1].
// Draws a macOS-style rounded squircle with a paper/document and an AI sparkle.

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master.png"
let size = 1024.0

guard let rep = NSBitmapImageRep(
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
) else {
    fatalError("Could not create bitmap representation")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("No context") }

// Background squircle with vertical gradient
let inset = size * 0.06
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = (size - inset * 2) * 0.225
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
squircle.addClip()

let top = NSColor(calibratedRed: 0.36, green: 0.45, blue: 0.95, alpha: 1).cgColor
let bottom = NSColor(calibratedRed: 0.20, green: 0.28, blue: 0.78, alpha: 1).cgColor
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [top, bottom] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// Paper sheet
let paperW = size * 0.46
let paperH = size * 0.58
let paperX = (size - paperW) / 2 - size * 0.02
let paperY = (size - paperH) / 2 - size * 0.01
let paperRect = CGRect(x: paperX, y: paperY, width: paperW, height: paperH)
let paper = NSBezierPath(roundedRect: paperRect, xRadius: size * 0.03, yRadius: size * 0.03)
NSColor.white.setFill()
paper.fill()

// Text lines on the paper
NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
let lineH = size * 0.022
let lineGap = size * 0.052
let lineX = paperX + paperW * 0.14
var lineY = paperY + paperH - paperH * 0.18
let lineWidths: [CGFloat] = [0.72, 0.62, 0.7, 0.5, 0.66, 0.42]
for w in lineWidths {
    let lr = CGRect(x: lineX, y: lineY, width: paperW * w * 0.78, height: lineH)
    NSBezierPath(roundedRect: lr, xRadius: lineH / 2, yRadius: lineH / 2).fill()
    lineY -= lineGap
}

// AI sparkle (four-point star) in lower-right
func sparkle(center: CGPoint, r: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    let waist = r * 0.32
    p.move(to: CGPoint(x: center.x, y: center.y + r))
    p.curve(to: CGPoint(x: center.x + r, y: center.y),
            controlPoint1: CGPoint(x: center.x + waist, y: center.y + waist),
            controlPoint2: CGPoint(x: center.x + waist, y: center.y + waist))
    p.curve(to: CGPoint(x: center.x, y: center.y - r),
            controlPoint1: CGPoint(x: center.x + waist, y: center.y - waist),
            controlPoint2: CGPoint(x: center.x + waist, y: center.y - waist))
    p.curve(to: CGPoint(x: center.x - r, y: center.y),
            controlPoint1: CGPoint(x: center.x - waist, y: center.y - waist),
            controlPoint2: CGPoint(x: center.x - waist, y: center.y - waist))
    p.curve(to: CGPoint(x: center.x, y: center.y + r),
            controlPoint1: CGPoint(x: center.x - waist, y: center.y + waist),
            controlPoint2: CGPoint(x: center.x - waist, y: center.y + waist))
    color.setFill()
    p.fill()
}

sparkle(center: CGPoint(x: paperX + paperW * 0.78, y: paperY + paperH * 0.22),
        r: size * 0.10, color: NSColor(calibratedRed: 0.36, green: 0.45, blue: 0.95, alpha: 1))
sparkle(center: CGPoint(x: paperX + paperW * 0.95, y: paperY + paperH * 0.40),
        r: size * 0.045, color: NSColor(calibratedRed: 0.42, green: 0.52, blue: 0.98, alpha: 1))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
do {
    try data.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote icon master to \(outputPath)")
} catch {
    fatalError("Write failed: \(error)")
}
