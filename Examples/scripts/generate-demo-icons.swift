#!/usr/bin/env swift

import AppKit
import Darwin
import Foundation

private enum DemoIconKind {
    case markdown
    case streaming
    case documentReader
}

private struct DemoIconSpec {
    var appName: String
    var kind: DemoIconKind
    var topColor: NSColor
    var bottomColor: NSColor
    var accentColor: NSColor
    var secondaryColor: NSColor
}

private let fileManager = FileManager.default
private let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let examplesRoot = repoRoot.appendingPathComponent("Examples", isDirectory: true)
private let buildRoot = repoRoot.appendingPathComponent(".build/demo-icons", isDirectory: true)

private let iconSpecs = [
    DemoIconSpec(
        appName: "MarkdownDemoApp",
        kind: .markdown,
        topColor: color(0.08, 0.32, 0.46),
        bottomColor: color(0.02, 0.08, 0.16),
        accentColor: color(0.32, 0.82, 0.93),
        secondaryColor: color(0.84, 0.96, 1.0)
    ),
    DemoIconSpec(
        appName: "StreamingTranscriptDemo",
        kind: .streaming,
        topColor: color(0.06, 0.36, 0.32),
        bottomColor: color(0.02, 0.12, 0.12),
        accentColor: color(0.42, 0.92, 0.68),
        secondaryColor: color(0.84, 1.0, 0.92)
    ),
    DemoIconSpec(
        appName: "DocumentReaderDemo",
        kind: .documentReader,
        topColor: color(0.42, 0.28, 0.12),
        bottomColor: color(0.10, 0.08, 0.07),
        accentColor: color(0.98, 0.72, 0.28),
        secondaryColor: color(1.0, 0.93, 0.78)
    )
]

do {
    try generateDemoIcons()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

private func generateDemoIcons() throws {
    try fileManager.createDirectory(at: buildRoot, withIntermediateDirectories: true)

    for spec in iconSpecs {
        let iconsetURL = buildRoot.appendingPathComponent("\(spec.appName).iconset", isDirectory: true)
        let supportURL = examplesRoot
            .appendingPathComponent(spec.appName, isDirectory: true)
            .appendingPathComponent("Support", isDirectory: true)
        let outputURL = supportURL.appendingPathComponent("\(spec.appName).icns")

        try? fileManager.removeItem(at: iconsetURL)
        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)

        try writeIconset(spec: spec, to: iconsetURL)

        try? fileManager.removeItem(at: outputURL)
        try runIconutil(iconsetURL: iconsetURL, outputURL: outputURL)
        try fileManager.removeItem(at: iconsetURL)

        print("wrote \(outputURL.path)")
    }
}

private func writeIconset(spec: DemoIconSpec, to iconsetURL: URL) throws {
    let entries: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for entry in entries {
        let data = try pngData(for: spec, pixels: entry.pixels)
        try data.write(to: iconsetURL.appendingPathComponent(entry.name))
    }
}

private func pngData(for spec: DemoIconSpec, pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconGenerationError.bitmapCreationFailed(pixels)
    }

    bitmap.size = NSSize(width: 1024, height: 1024)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGenerationError.graphicsContextCreationFailed(pixels)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)
    context.cgContext.setShouldSmoothFonts(true)

    drawIcon(spec)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.pngEncodingFailed(pixels)
    }

    return data
}

private func drawIcon(_ spec: DemoIconSpec) {
    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSColor.clear.setFill()
    canvas.fill()

    let iconRect = canvas.insetBy(dx: 58, dy: 58)
    let iconPath = rounded(iconRect, radius: 210)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.28)
    shadow.shadowBlurRadius = 46
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSGradient(colors: [spec.topColor, spec.bottomColor])?.draw(in: iconPath, angle: -38)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    iconPath.addClip()
    drawBackgroundTexture(in: iconRect, accent: spec.accentColor)
    NSGraphicsContext.restoreGraphicsState()

    rounded(iconRect, radius: 210).stroke(color(1, 1, 1, 0.18), lineWidth: 6)

    switch spec.kind {
    case .markdown:
        drawMarkdownGlyph(spec)
    case .streaming:
        drawStreamingGlyph(spec)
    case .documentReader:
        drawDocumentReaderGlyph(spec)
    }
}

private func drawBackgroundTexture(in rect: NSRect, accent: NSColor) {
    for index in 0..<9 {
        let offset = CGFloat(index) * 126 - 240
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + offset, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + offset + 470, y: rect.maxY))
        path.stroke(accent.withAlphaComponent(0.055), lineWidth: 8)
    }

    for radius in stride(from: 80, through: 380, by: 75) {
        rounded(
            NSRect(
                x: rect.midX - CGFloat(radius),
                y: rect.midY - CGFloat(radius),
                width: CGFloat(radius) * 2,
                height: CGFloat(radius) * 2
            ),
            radius: CGFloat(radius)
        ).stroke(color(1, 1, 1, 0.035), lineWidth: 4)
    }
}

private func drawMarkdownGlyph(_ spec: DemoIconSpec) {
    let page = NSRect(x: 228, y: 182, width: 568, height: 662)
    drawCard(page, radius: 72, fill: color(0.96, 0.99, 1.0, 0.96))

    rounded(NSRect(x: 292, y: 686, width: 104, height: 104), radius: 30)
        .fill(spec.accentColor)
    drawText(
        "#",
        in: NSRect(x: 292, y: 683, width: 104, height: 104),
        font: .systemFont(ofSize: 72, weight: .heavy),
        color: spec.bottomColor,
        alignment: .center
    )

    drawLine(x: 430, y: 750, width: 250, height: 28, color: spec.bottomColor.withAlphaComponent(0.28))
    drawLine(x: 430, y: 700, width: 304, height: 20, color: spec.bottomColor.withAlphaComponent(0.18))

    for (index, width) in [392, 470, 332].enumerated() {
        drawLine(
            x: 292,
            y: 588 - CGFloat(index) * 62,
            width: CGFloat(width),
            height: 28,
            color: spec.bottomColor.withAlphaComponent(0.20)
        )
    }

    rounded(NSRect(x: 292, y: 262, width: 440, height: 156), radius: 42)
        .fill(color(0.03, 0.09, 0.16, 0.92))
    drawText(
        "M",
        in: NSRect(x: 324, y: 270, width: 132, height: 132),
        font: .systemFont(ofSize: 118, weight: .black),
        color: spec.accentColor,
        alignment: .center
    )

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 574, y: 380))
    arrow.line(to: NSPoint(x: 574, y: 300))
    arrow.line(to: NSPoint(x: 526, y: 300))
    arrow.line(to: NSPoint(x: 614, y: 220))
    arrow.line(to: NSPoint(x: 702, y: 300))
    arrow.line(to: NSPoint(x: 654, y: 300))
    arrow.line(to: NSPoint(x: 654, y: 380))
    arrow.close()
    arrow.fill(spec.secondaryColor)
}

private func drawStreamingGlyph(_ spec: DemoIconSpec) {
    drawBubble(
        rect: NSRect(x: 170, y: 402, width: 610, height: 300),
        tail: [
            NSPoint(x: 292, y: 402),
            NSPoint(x: 226, y: 320),
            NSPoint(x: 384, y: 402)
        ],
        fill: color(0.94, 1.0, 0.98, 0.96),
        stroke: color(1, 1, 1, 0.55)
    )

    drawBubble(
        rect: NSRect(x: 410, y: 222, width: 432, height: 216),
        tail: [
            NSPoint(x: 710, y: 222),
            NSPoint(x: 808, y: 158),
            NSPoint(x: 784, y: 244)
        ],
        fill: spec.accentColor.withAlphaComponent(0.94),
        stroke: color(1, 1, 1, 0.42)
    )

    for (index, width) in [370, 286, 438].enumerated() {
        drawLine(
            x: 252,
            y: 614 - CGFloat(index) * 66,
            width: CGFloat(width),
            height: 30,
            color: spec.bottomColor.withAlphaComponent(0.26)
        )
    }

    for index in 0..<3 {
        circle(
            center: NSPoint(x: 530 + CGFloat(index) * 66, y: 320),
            radius: 24,
            color: spec.bottomColor.withAlphaComponent(index == 2 ? 0.76 : 0.46)
        )
    }

    for index in 0..<4 {
        let x = 194 + CGFloat(index) * 72
        drawLine(
            x: x,
            y: 230 + CGFloat(index % 2) * 34,
            width: 46,
            height: 14,
            color: spec.secondaryColor.withAlphaComponent(0.50)
        )
    }
}

private func drawDocumentReaderGlyph(_ spec: DemoIconSpec) {
    let leftPage = NSRect(x: 188, y: 184, width: 312, height: 666)
    let rightPage = NSRect(x: 524, y: 184, width: 312, height: 666)

    drawCard(NSRect(x: 158, y: 154, width: 708, height: 726), radius: 78, fill: color(0.08, 0.06, 0.04, 0.24))
    drawCard(leftPage, radius: 50, fill: color(1.0, 0.98, 0.92, 0.97))
    drawCard(rightPage, radius: 50, fill: color(1.0, 0.98, 0.92, 0.97))

    drawLine(x: 498, y: 210, width: 28, height: 612, color: color(0.17, 0.11, 0.07, 0.20))
    rounded(NSRect(x: 700, y: 626, width: 66, height: 192), radius: 20)
        .fill(spec.accentColor)

    for (index, width) in [168, 214, 186, 226, 150].enumerated() {
        drawLine(
            x: 260,
            y: 738 - CGFloat(index) * 76,
            width: CGFloat(width),
            height: 24,
            color: spec.bottomColor.withAlphaComponent(0.24)
        )
    }

    for (index, width) in [216, 172, 224, 198, 152].enumerated() {
        drawLine(
            x: 578,
            y: 738 - CGFloat(index) * 76,
            width: CGFloat(width),
            height: 24,
            color: spec.bottomColor.withAlphaComponent(0.24)
        )
    }

    rounded(NSRect(x: 240, y: 270, width: 196, height: 54), radius: 22)
        .fill(spec.accentColor.withAlphaComponent(0.82))
    drawText(
        "Aa",
        in: NSRect(x: 246, y: 267, width: 182, height: 62),
        font: .systemFont(ofSize: 46, weight: .bold),
        color: spec.bottomColor,
        alignment: .center
    )

    let lens = NSBezierPath(ovalIn: NSRect(x: 610, y: 270, width: 112, height: 112))
    lens.stroke(spec.bottomColor.withAlphaComponent(0.38), lineWidth: 20)
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 694, y: 290))
    handle.line(to: NSPoint(x: 760, y: 224))
    handle.stroke(spec.bottomColor.withAlphaComponent(0.38), lineWidth: 20)
}

private func drawCard(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.24)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    rounded(rect, radius: radius).fill(fill)
    NSGraphicsContext.restoreGraphicsState()
    rounded(rect, radius: radius).stroke(color(1, 1, 1, 0.42), lineWidth: 4)
}

private func drawBubble(rect: NSRect, tail: [NSPoint], fill: NSColor, stroke: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.22)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()

    let path = rounded(rect, radius: 86)
    path.fill(fill)

    let tailPath = NSBezierPath()
    tailPath.move(to: tail[0])
    tailPath.line(to: tail[1])
    tailPath.line(to: tail[2])
    tailPath.close()
    tailPath.fill(fill)
    NSGraphicsContext.restoreGraphicsState()

    rounded(rect, radius: 86).stroke(stroke, lineWidth: 4)
}

private func drawLine(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
    rounded(NSRect(x: x, y: y, width: width, height: height), radius: height / 2)
        .fill(color)
}

private func circle(center: NSPoint, radius: CGFloat, color: NSColor) {
    NSBezierPath(
        ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    ).fill(color)
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    NSString(string: text).draw(in: rect, withAttributes: attributes)
}

private func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private extension NSBezierPath {
    func fill(_ color: NSColor) {
        color.setFill()
        fill()
    }

    func stroke(_ color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        self.lineWidth = lineWidth
        stroke()
    }
}

private func runIconutil(iconsetURL: URL, outputURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = [
        "-c",
        "icns",
        "-o",
        outputURL.path,
        iconsetURL.path
    ]

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw IconGenerationError.iconutilFailed(process.terminationStatus)
    }
}

private enum IconGenerationError: Error, CustomStringConvertible {
    case bitmapCreationFailed(Int)
    case graphicsContextCreationFailed(Int)
    case pngEncodingFailed(Int)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case let .bitmapCreationFailed(pixels):
            return "failed to create \(pixels)x\(pixels) bitmap"
        case let .graphicsContextCreationFailed(pixels):
            return "failed to create graphics context for \(pixels)x\(pixels) bitmap"
        case let .pngEncodingFailed(pixels):
            return "failed to encode \(pixels)x\(pixels) png"
        case let .iconutilFailed(status):
            return "iconutil failed with status \(status)"
        }
    }
}
