#!/usr/bin/env swift

import AppKit

struct Preview {
    let filename: String
    let screenshot: String
    let title: String
    let backgroundStart: NSColor
    let backgroundEnd: NSColor
    let accent: NSColor
}

let canvasSize = NSSize(width: 1242, height: 2688)
let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let rawDirectory = workspace.appendingPathComponent("Artifacts/AppPreviews/raw")
let outputDirectory = workspace.appendingPathComponent("Artifacts/AppPreviews/final")

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

let previews = [
    Preview(
        filename: "01-break-the-autopilot-loop.png",
        screenshot: "onboarding.png",
        title: "Break the\nautopilot loop",
        backgroundStart: color(248, 242, 232),
        backgroundEnd: color(236, 210, 170),
        accent: color(201, 124, 28)
    ),
    Preview(
        filename: "02-set-your-own-tiny-cost.png",
        screenshot: "protection.png",
        title: "Put value on\nyour attention",
        backgroundStart: color(247, 239, 226),
        backgroundEnd: color(229, 196, 146),
        accent: color(187, 108, 18)
    ),
    Preview(
        filename: "03-free-time-comes-first.png",
        screenshot: "shield.png",
        title: "Choose your daily\ngrace period",
        backgroundStart: color(243, 238, 227),
        backgroundEnd: color(209, 221, 203),
        accent: color(111, 128, 104)
    ),
    Preview(
        filename: "04-start-with-two-dollars.png",
        screenshot: "home.png",
        title: "Start with\nincluded credits",
        backgroundStart: color(245, 240, 230),
        backgroundEnd: color(214, 223, 208),
        accent: color(111, 128, 104)
    ),
    Preview(
        filename: "05-see-your-progress.png",
        screenshot: "progress.png",
        title: "See your\nprogress",
        backgroundStart: color(239, 243, 235),
        backgroundEnd: color(194, 211, 187),
        accent: color(96, 119, 90)
    )
]

let titleColor = color(39, 37, 33)

for preview in previews {
    let screenshotURL = rawDirectory.appendingPathComponent(preview.screenshot)
    guard let screenshot = NSImage(contentsOf: screenshotURL) else {
        throw NSError(
            domain: "AppPreviewGenerator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to load \(screenshotURL.path)"]
        )
    }

    let image = NSImage(size: canvasSize)
    image.lockFocusFlipped(true)

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        throw NSError(
            domain: "AppPreviewGenerator",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create drawing context"]
        )
    }

    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    let canvasRect = NSRect(origin: .zero, size: canvasSize)
    NSGradient(
        starting: preview.backgroundStart,
        ending: preview.backgroundEnd
    )?.draw(in: canvasRect, angle: 90)

    preview.accent.withAlphaComponent(0.10).setFill()
    NSBezierPath(
        ovalIn: NSRect(x: -590, y: 1050, width: 1410, height: 1410)
    ).fill()

    NSColor.white.withAlphaComponent(0.20).setFill()
    NSBezierPath(
        ovalIn: NSRect(x: 535, y: 1610, width: 1210, height: 1210)
    ).fill()

    preview.accent.withAlphaComponent(0.75).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 565, y: 160, width: 112, height: 14),
        xRadius: 7,
        yRadius: 7
    ).fill()

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.minimumLineHeight = 114
    paragraphStyle.maximumLineHeight = 114

    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 102, weight: .semibold),
        .foregroundColor: titleColor,
        .paragraphStyle: paragraphStyle,
        .kern: -2.0
    ]

    let titleRect = NSRect(x: 90, y: 220, width: 1063, height: 300)
    NSAttributedString(
        string: preview.title,
        attributes: titleAttributes
    ).draw(with: titleRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

    let outerPhoneRect = NSRect(x: 170, y: 650, width: 903, height: 1908)
    let screenRect = outerPhoneRect.insetBy(dx: 24, dy: 24)
    let phonePath = NSBezierPath(
        roundedRect: outerPhoneRect,
        xRadius: 154,
        yRadius: 154
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: 20)
    shadow.set()
    color(31, 29, 27).setFill()
    phonePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: screenRect,
        xRadius: 132,
        yRadius: 132
    ).addClip()
    screenshot.draw(
        in: screenRect,
        from: NSRect(origin: .zero, size: screenshot.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.22).setStroke()
    phonePath.lineWidth = 3
    phonePath.stroke()

    image.unlockFocus()

    guard let rgbContext = CGContext(
        data: nil,
        width: Int(canvasSize.width),
        height: Int(canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(canvasSize.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(
            domain: "AppPreviewGenerator",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unable to flatten \(preview.filename)"]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    let rgbGraphicsContext = NSGraphicsContext(
        cgContext: rgbContext,
        flipped: true
    )
    NSGraphicsContext.current = rgbGraphicsContext
    image.draw(
        in: canvasRect,
        from: canvasRect,
        operation: .copy,
        fraction: 1
    )
    rgbGraphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard
        let flattenedImage = rgbContext.makeImage(),
        let png = NSBitmapImageRep(cgImage: flattenedImage).representation(
        using: .png,
        properties: [.compressionFactor: 1]
        )
    else {
        throw NSError(
            domain: "AppPreviewGenerator",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode \(preview.filename)"]
        )
    }

    try png.write(to: outputDirectory.appendingPathComponent(preview.filename))
}

print("Generated \(previews.count) app previews in \(outputDirectory.path)")
