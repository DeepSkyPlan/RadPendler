// Renders the 1024 px app icon from `RadPendler/Views/Mark.swift`, so the icon
// and the mark in the title bar cannot drift apart:
//
//   swiftc tools/make_icon.swift RadPendler/Views/Mark.swift -o /tmp/mkicon
//   /tmp/mkicon RadPendler/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Full bleed and without alpha — iOS rounds the corners itself, and the App
// Store rejects an icon that carries transparency.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeIcon {
    static func main() {
    let S = 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

    func color(_ c: (CGFloat, CGFloat, CGFloat)) -> CGColor {
        CGColor(colorSpace: space, components: [c.0, c.1, c.2, 1])!
    }

    // `Mark` draws in a 100 × 100 box with y running down; the bitmap runs up.
    ctx.translateBy(x: 0, y: CGFloat(S))
    ctx.scaleBy(x: CGFloat(S) / 100, y: -CGFloat(S) / 100)

    let gradient = CGGradient(colorsSpace: space,
                              colors: [color(Mark.backgroundTop), color(Mark.backgroundBottom)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 100, y: 100), options: [])

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Pin and bicycle, cut off where the badge sits.
    ctx.saveGState()
    ctx.addPath(Mark.pinClip)
    ctx.clip(using: .evenOdd)
    ctx.addPath(Mark.pin)
    ctx.setFillColor(color(Mark.pinTint))
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.addPath(Mark.pin)
    ctx.setLineWidth(Mark.outlineWidth)
    ctx.strokePath()
    ctx.addPath(Mark.bike)
    ctx.setLineWidth(Mark.bikeStroke)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.addPath(Mark.badge)
    ctx.setFillColor(color(Mark.badgeTint))
    ctx.fillPath()
    ctx.addPath(Mark.badge)
    ctx.setLineWidth(Mark.outlineWidth)
    ctx.strokePath()
    ctx.addPath(Mark.busBody)
    ctx.setLineWidth(Mark.busStroke)
    ctx.strokePath()
    ctx.addPath(Mark.busLights)
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.fillPath()

    guard CommandLine.arguments.count > 1 else {
        FileHandle.standardError.write(Data("usage: mkicon <out.png>\n".utf8))
        exit(2)
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    }
}
