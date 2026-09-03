#!/usr/bin/env swift

//
//  generate-branding.swift
//  Float Assist
//
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//
//  Draws the Float Assist mark, the application icon, the menu bar template
//  and the README artwork with AppKit and Core Graphics only. Usage:
//
//      swift scripts/generate-branding.swift [repository-root]
//

import AppKit
import Foundation

// MARK: - Colours

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

enum Palette {
    static let paperTop = rgb(0xFFFDF9)
    static let paperBottom = rgb(0xF1EADE)
    static let ink = rgb(0x1F1B17)
    static let inkSoft = rgb(0x6B6259)
}

/// Every ray is painted with one of three two-stop gradients.
enum Accent {
    case ember, drift, leaf

    var gradient: [CGColor] {
        switch self {
        case .ember: return [rgb(0xF2926F), rgb(0xBF4E33)]
        case .drift: return [rgb(0x5C97FF), rgb(0x2450D8)]
        case .leaf: return [rgb(0x3FC98A), rgb(0x10945A)]
        }
    }

    var flat: CGColor {
        switch self {
        case .ember: return rgb(0xC4553A)
        case .drift: return rgb(0x2450D8)
        case .leaf: return rgb(0x139A5E)
        }
    }
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 1]
    )!
}

// MARK: - Petal geometry

/// One ray, drawn along +X and then placed by `transform`. The silhouette is a
/// tapered lens: narrow at the hub, widest around the middle, blunt at the tip.
func petalPath(
    innerRadius r0: CGFloat,
    outerRadius r1: CGFloat,
    halfWidth: CGFloat,
    transform: CGAffineTransform
) -> CGPath {
    let length = r1 - r0
    let path = CGMutablePath()
    var t = transform

    path.move(to: CGPoint(x: r0, y: 0))
    path.addCurve(
        to: CGPoint(x: r1, y: 0),
        control1: CGPoint(x: r0 + length * 0.42, y: halfWidth * 0.98),
        control2: CGPoint(x: r1 - length * 0.06, y: halfWidth * 0.72)
    )
    path.addCurve(
        to: CGPoint(x: r0, y: 0),
        control1: CGPoint(x: r1 - length * 0.06, y: -halfWidth * 0.72),
        control2: CGPoint(x: r0 + length * 0.42, y: -halfWidth * 0.98)
    )
    path.closeSubpath()
    return path.copy(using: &t) ?? path
}

struct Ray {
    let angle: CGFloat      // degrees, 0 = up, clockwise
    let inner: CGFloat      // fraction of R
    let outer: CGFloat      // fraction of R
    let halfWidth: CGFloat  // fraction of R
    let drift: CGFloat      // outward offset, fraction of R
    let tilt: CGFloat       // extra rotation, degrees
    let accent: Accent
}

/// Twelve rays, long and short alternating — except the two at 11 and 1
/// o'clock, which have broken away from the hub and drifted outwards in blue
/// and green. Those two are the point of the mark: this is Float Assist, not
/// any of the assistants it opens.
func rays() -> [Ray] {
    (0..<12).map { index in
        let angle = CGFloat(index) * 30

        if index == 1 || index == 11 {
            return Ray(
                angle: angle,
                inner: 0.30,
                outer: 1.02,
                halfWidth: 0.118,
                drift: 0.19,
                tilt: index == 1 ? 9 : -9,
                accent: index == 1 ? .leaf : .drift
            )
        }

        let isLong = index % 2 == 0
        return Ray(
            angle: angle,
            inner: 0.085,
            outer: isLong ? 1.0 : 0.66,
            halfWidth: isLong ? 0.115 : 0.092,
            drift: 0,
            tilt: 0,
            accent: .ember
        )
    }
}

func path(for ray: Ray, center: CGPoint, radius R: CGFloat, widthScale: CGFloat = 1) -> CGPath {
    // 0° points up and angles run clockwise, in a bottom-left origin space.
    let radians = (90 - ray.angle - ray.tilt) * .pi / 180
    let driftAngle = (90 - ray.angle) * .pi / 180
    let transform = CGAffineTransform(
        translationX: center.x + cos(driftAngle) * ray.drift * R,
        y: center.y + sin(driftAngle) * ray.drift * R
    ).rotated(by: radians)

    return petalPath(
        innerRadius: ray.inner * R,
        outerRadius: ray.outer * R,
        halfWidth: ray.halfWidth * R * widthScale,
        transform: transform
    )
}

/// Draws the burst. `monochrome` paints every ray one colour, which is what a
/// menu bar template image needs.
func drawMark(
    in context: CGContext,
    center: CGPoint,
    radius R: CGFloat,
    widthScale: CGFloat = 1,
    monochrome: CGColor? = nil
) {
    let groups: [(Accent, CGMutablePath)] = [
        (.ember, CGMutablePath()), (.drift, CGMutablePath()), (.leaf, CGMutablePath())
    ]
    for ray in rays() {
        let bucket = groups.first { $0.0 == ray.accent }!.1
        bucket.addPath(path(for: ray, center: center, radius: R, widthScale: widthScale))
    }

    for (accent, shape) in groups where !shape.isEmpty {
        context.saveGState()
        context.addPath(shape)
        context.clip()
        if let flat = monochrome {
            context.setFillColor(flat)
            context.fill(shape.boundingBox)
        } else {
            let box = shape.boundingBox
            context.drawLinearGradient(
                gradient(accent.gradient),
                start: CGPoint(x: box.minX, y: box.maxY),
                end: CGPoint(x: box.maxX, y: box.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()
    }
}

// MARK: - Canvas helpers

func makeContext(width: Int, height: Int) -> CGContext {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    return context
}

func write(_ context: CGContext, to url: URL) {
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("  \(url.lastPathComponent) (\(image.width)×\(image.height))")
}

/// The rounded rectangle macOS uses for application icons: the artwork sits in
/// an 824pt square inside a 1024pt canvas, with a 185.4pt corner radius.
func drawAppIcon(side: CGFloat) -> CGContext {
    let context = makeContext(width: Int(side), height: Int(side))
    // Below 128pt the rays thin out to nothing, so the mark is drawn heavier
    // and the decorative edge is dropped.
    let isSmall = side <= 64
    let inset = side * (100.0 / 1024.0)
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = side * (185.4 / 1024.0)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -side * 0.012),
        blur: side * 0.028,
        color: rgb(0x2A1F16, 0.24)
    )
    context.addPath(shape)
    context.setFillColor(Palette.paperTop)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        gradient([Palette.paperTop, Palette.paperBottom]),
        start: CGPoint(x: 0, y: side),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    context.restoreGState()

    drawMark(
        in: context,
        center: CGPoint(x: side / 2, y: side / 2),
        radius: side * (isSmall ? 0.275 : 0.255),
        widthScale: isSmall ? 1.45 : 1
    )

    if !isSmall {
        // Hairline so the icon keeps an edge on a white background.
        context.addPath(shape)
        context.setStrokeColor(rgb(0xB9A992, 0.45))
        context.setLineWidth(max(1, side * 0.0025))
        context.strokePath()
    }

    return context
}

func drawMarkOnly(side: CGFloat, widthScale: CGFloat = 1, monochrome: CGColor? = nil) -> CGContext {
    let context = makeContext(width: Int(side), height: Int(side))
    drawMark(
        in: context,
        center: CGPoint(x: side / 2, y: side / 2),
        radius: side * 0.40,
        widthScale: widthScale,
        monochrome: monochrome
    )
    return context
}

// MARK: - Text

func draw(
    _ string: String,
    at point: CGPoint,
    size: CGFloat,
    weight: NSFont.Weight,
    color: CGColor,
    tracking: CGFloat = 0,
    in context: CGContext
) {
    let text = NSAttributedString(
        string: string,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: color)!,
            .kern: tracking
        ]
    )
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text.draw(at: point)
    NSGraphicsContext.current = previous
}

func width(of string: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0) -> CGFloat {
    NSAttributedString(
        string: string,
        attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .kern: tracking]
    ).size().width
}

// MARK: - README artwork

func drawBanner(width W: CGFloat, height H: CGFloat) -> CGContext {
    let context = makeContext(width: Int(W), height: Int(H))

    context.drawLinearGradient(
        gradient([rgb(0xFFFDF9), rgb(0xF0E8DB)]),
        start: CGPoint(x: 0, y: H),
        end: CGPoint(x: W, y: 0),
        options: []
    )

    // Oversized, very faint mark bleeding off the right edge.
    context.saveGState()
    context.setAlpha(0.07)
    drawMark(in: context, center: CGPoint(x: W * 0.93, y: H * 0.52), radius: H * 0.62)
    context.restoreGState()

    let markRadius = H * 0.21
    let markCenter = CGPoint(x: W * 0.115, y: H * 0.545)
    drawMark(in: context, center: markCenter, radius: markRadius)

    let textLeft = markCenter.x + markRadius * 1.75
    draw(
        "Float Assist",
        at: CGPoint(x: textLeft, y: H * 0.52),
        size: H * 0.155,
        weight: .semibold,
        color: Palette.ink,
        tracking: -H * 0.004,
        in: context
    )
    draw(
        "Claude, Gemini and ChatGPT in a floating macOS panel.",
        at: CGPoint(x: textLeft, y: H * 0.375),
        size: H * 0.065,
        weight: .regular,
        color: Palette.inkSoft,
        in: context
    )

    let pillText = "\u{2325} Space"
    let pillFont = H * 0.055
    let pillHeight = H * 0.105
    let pillRect = CGRect(
        x: textLeft,
        y: H * 0.20,
        width: width(of: pillText, size: pillFont, weight: .medium) + H * 0.10,
        height: pillHeight
    )
    let pill = CGPath(
        roundedRect: pillRect,
        cornerWidth: pillHeight * 0.32,
        cornerHeight: pillHeight * 0.32,
        transform: nil
    )
    context.addPath(pill)
    context.setFillColor(rgb(0xFFFFFF, 0.85))
    context.fillPath()
    context.addPath(pill)
    context.setStrokeColor(rgb(0xC9BCA8))
    context.setLineWidth(max(1, H * 0.003))
    context.strokePath()
    draw(
        pillText,
        at: CGPoint(x: pillRect.minX + H * 0.05, y: pillRect.minY + pillHeight * 0.27),
        size: pillFont,
        weight: .medium,
        color: Palette.inkSoft,
        in: context
    )

    return context
}

/// Spells out, for the README, how the mark differs from the assistant logos
/// it deliberately echoes.
func drawMarkAnatomy(width W: CGFloat, height H: CGFloat) -> CGContext {
    let context = makeContext(width: Int(W), height: Int(H))
    context.setFillColor(rgb(0xFFFDF9))
    context.fill(CGRect(x: 0, y: 0, width: W, height: H))

    let R = H * 0.26
    let center = CGPoint(x: W * 0.5, y: H * 0.46)
    drawMark(in: context, center: center, radius: R)

    func callout(rayIndex: Int, toTheLeft: Bool, colour: CGColor, title: String, subtitle: String) {
        let ray = rays()[rayIndex]
        let tipAngle = (90 - ray.angle - ray.tilt) * .pi / 180
        let reach = (ray.outer + ray.drift) * R
        let tip = CGPoint(x: center.x + cos(tipAngle) * reach, y: center.y + sin(tipAngle) * reach)
        let direction: CGFloat = toTheLeft ? -1 : 1
        let elbow = CGPoint(x: tip.x + direction * W * 0.045, y: tip.y + H * 0.11)
        let railEnd = CGPoint(x: elbow.x + direction * W * 0.05, y: elbow.y)

        context.setStrokeColor(colour.copy(alpha: 0.7) ?? colour)
        context.setLineWidth(max(1, H * 0.006))
        context.setLineDash(phase: 0, lengths: [H * 0.022, H * 0.018])
        context.move(to: CGPoint(x: tip.x + direction * W * 0.006, y: tip.y + H * 0.012))
        context.addLine(to: elbow)
        context.addLine(to: railEnd)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        let titleSize = H * 0.055
        let subtitleSize = H * 0.042
        let titleX = toTheLeft
            ? railEnd.x - W * 0.02 - width(of: title, size: titleSize, weight: .semibold)
            : railEnd.x + W * 0.02
        let subtitleX = toTheLeft
            ? railEnd.x - W * 0.02 - width(of: subtitle, size: subtitleSize, weight: .regular)
            : railEnd.x + W * 0.02

        draw(title, at: CGPoint(x: titleX, y: railEnd.y - H * 0.020), size: titleSize, weight: .semibold, color: colour, in: context)
        draw(subtitle, at: CGPoint(x: subtitleX, y: railEnd.y - H * 0.088), size: subtitleSize, weight: .regular, color: Palette.inkSoft, in: context)
    }

    callout(
        rayIndex: 11,
        toTheLeft: true,
        colour: Accent.drift.flat,
        title: "Two rays float free",
        subtitle: "detached from the hub"
    )
    callout(
        rayIndex: 1,
        toTheLeft: false,
        colour: Accent.leaf.flat,
        title: "In blue and green",
        subtitle: "not any logo's colours"
    )

    let caption = "The Float Assist mark"
    draw(
        caption,
        at: CGPoint(x: center.x - width(of: caption, size: H * 0.05, weight: .medium) / 2, y: H * 0.055),
        size: H * 0.05,
        weight: .medium,
        color: Palette.inkSoft,
        in: context
    )

    return context
}

// MARK: - Asset catalog

struct IconEntry {
    let size: Int
    let scale: Int
    var pixels: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

let iconEntries: [IconEntry] = [
    IconEntry(size: 16, scale: 1), IconEntry(size: 16, scale: 2),
    IconEntry(size: 32, scale: 1), IconEntry(size: 32, scale: 2),
    IconEntry(size: 128, scale: 1), IconEntry(size: 128, scale: 2),
    IconEntry(size: 256, scale: 1), IconEntry(size: 256, scale: 2),
    IconEntry(size: 512, scale: 1), IconEntry(size: 512, scale: 2)
]

func imageSetContents(_ filenames: [String], template: Bool) -> String {
    let images = filenames.enumerated().map { index, name in
        """
            {
              "filename" : "\(name)",
              "idiom" : "universal",
              "scale" : "\(index + 1)x"
            }
        """
    }
    let properties = template
        ? ",\n  \"properties\" : {\n    \"template-rendering-intent\" : \"template\"\n  }"
        : ""
    return """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }\(properties)
    }

    """
}

// MARK: - Main

let root = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : FileManager.default.currentDirectoryPath
).standardizedFileURL

let catalog = root.appendingPathComponent("Resources/Assets.xcassets")
let appIconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let menuBarSet = catalog.appendingPathComponent("MenuBarMark.imageset")
let appMarkSet = catalog.appendingPathComponent("AppMark.imageset")
let assets = root.appendingPathComponent("docs/assets")

print("Application icon")
for entry in iconEntries {
    write(drawAppIcon(side: CGFloat(entry.pixels)), to: appIconSet.appendingPathComponent(entry.filename))
}
let iconImages = iconEntries.map { entry in
    """
        {
          "filename" : "\(entry.filename)",
          "idiom" : "mac",
          "scale" : "\(entry.scale)x",
          "size" : "\(entry.size)x\(entry.size)"
        }
    """
}
try! """
{
  "images" : [
\(iconImages.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

""".write(to: appIconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("Menu bar template")
var menuBarNames: [String] = []
for scale in 1...3 {
    let name = scale == 1 ? "menubar.png" : "menubar@\(scale)x.png"
    menuBarNames.append(name)
    // Menu bar glyphs need more weight than the full-colour mark: at 18pt the
    // hairline rays would all but disappear next to the system symbols.
    write(
        drawMarkOnly(side: CGFloat(18 * scale), widthScale: 1.35, monochrome: rgb(0x000000)),
        to: menuBarSet.appendingPathComponent(name)
    )
}
try! imageSetContents(menuBarNames, template: true)
    .write(to: menuBarSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("In-app mark")
var appMarkNames: [String] = []
for scale in 1...3 {
    let name = scale == 1 ? "mark.png" : "mark@\(scale)x.png"
    appMarkNames.append(name)
    write(drawMarkOnly(side: CGFloat(22 * scale)), to: appMarkSet.appendingPathComponent(name))
}
try! imageSetContents(appMarkNames, template: false)
    .write(to: appMarkSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("README artwork")
write(drawAppIcon(side: 1024), to: assets.appendingPathComponent("app-icon.png"))
write(drawMarkOnly(side: 640), to: assets.appendingPathComponent("mark.png"))
write(drawBanner(width: 1600, height: 460), to: assets.appendingPathComponent("banner.png"))
write(drawMarkAnatomy(width: 1320, height: 620), to: assets.appendingPathComponent("mark-anatomy.png"))

print("Done.")
