// Renders the app icon: bike above a train and a bus, on a green-to-teal gradient.
// The title bar draws the same mark as `AppMark` in Views/Theme.swift — keep both in step.
//   swift tools/make_icon.swift Pendel/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let colors = [CGColor(red: 0.12, green: 0.66, blue: 0.28, alpha: 1),
              CGColor(red: 0.00, green: 0.38, blue: 0.45, alpha: 1)]
let grad = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
func glyph(_ name: String, in rect: CGRect) {
    let cfg = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { fatalError("no symbol \(name)") }
    let s = img.size, k = min(rect.width / s.width, rect.height / s.height)
    let w = s.width * k, h = s.height * k
    img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
}
glyph("bicycle", in: CGRect(x: 182, y: 470, width: 660, height: 390))
glyph("train.side.front.car", in: CGRect(x: 120, y: 150, width: 400, height: 240))
glyph("bus.fill", in: CGRect(x: 570, y: 150, width: 330, height: 240))

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
