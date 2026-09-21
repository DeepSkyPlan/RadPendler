import CoreGraphics

/// The app mark, drawn in a 100 × 100 box with y running **down** — the same
/// numbers the design page `_reports/RadPendler_Logos_2.html` uses (Entwurf N2,
/// Palette „Wald"): a green map pin with a bicycle in its head and an amber bus
/// badge hanging off its lower right, the badge freed from the pin by a notch.
///
/// Everything that draws the mark reads from here: `AppMark` in `Theme.swift`
/// for the title bar and `tools/make_icon.swift` for the 1024 px icon.
///
///     swiftc tools/make_icon.swift RadPendler/Views/Mark.swift -o /tmp/mkicon
///     /tmp/mkicon RadPendler/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
enum Mark {
    // MARK: Colours (sRGB)

    /// Background gradient, top-left to bottom-right.
    static let backgroundTop: (CGFloat, CGFloat, CGFloat) = (0.122, 0.659, 0.278)     // #1FA847
    static let backgroundBottom: (CGFloat, CGFloat, CGFloat) = (0.000, 0.380, 0.435)  // #00616F
    /// The pin: a deeper green than the ground it stands on.
    static let pinTint: (CGFloat, CGFloat, CGFloat) = (0.059, 0.549, 0.243)           // #0F8C3E
    /// The bus badge.
    static let badgeTint: (CGFloat, CGFloat, CGFloat) = (0.851, 0.510, 0.000)         // #D98200

    // MARK: Weights

    /// Hairline around pin and badge — what keeps the green pin off the green ground.
    static let outlineWidth: CGFloat = 2.5
    static let bikeStroke: CGFloat = 9 * bikeScale
    static let busStroke: CGFloat = 10 * busScale

    // MARK: Geometry

    static let badgeCenter = CGPoint(x: 74, y: 73)
    static let badgeRadius: CGFloat = 19
    /// The hole punched out of the pin so the badge reads as its own form.
    static let notchRadius: CGFloat = 26

    private static let bikeScale: CGFloat = 0.34
    private static let busScale: CGFloat = 0.29
    /// Glyph boxes are 100 wide; these put their middles where they belong.
    private static var bikePlacement: CGAffineTransform {
        CGAffineTransform(translationX: 26, y: 27.12).scaledBy(x: bikeScale, y: bikeScale)
    }
    private static var busPlacement: CGAffineTransform {
        CGAffineTransform(translationX: 59.5, y: 58.5).scaledBy(x: busScale, y: busScale)
    }

    /// Full square minus the notch, filled even-odd: the clip everything under
    /// the badge is drawn through.
    static var pinClip: CGPath {
        let p = CGMutablePath()
        p.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        p.addEllipse(in: CGRect(x: badgeCenter.x - notchRadius, y: badgeCenter.y - notchRadius,
                                width: notchRadius * 2, height: notchRadius * 2))
        return p
    }

    /// Teardrop: a half circle of radius 26 over two curves running to the tip.
    static var pin: CGPath {
        let cx: CGFloat = 43, cy: CGFloat = 38, r: CGFloat = 26, tip: CGFloat = 88
        let shoulder = cy + r * 0.65
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx, y: tip))
        p.addCurve(to: CGPoint(x: cx - r, y: cy),
                   control1: CGPoint(x: cx, y: tip), control2: CGPoint(x: cx - r, y: shoulder))
        // y points down here, so rising angles carry the arc over the top.
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        p.addCurve(to: CGPoint(x: cx, y: tip),
                   control1: CGPoint(x: cx + r, y: shoulder), control2: CGPoint(x: cx, y: tip))
        p.closeSubpath()
        return p
    }

    static var badge: CGPath {
        CGPath(ellipseIn: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                                 width: badgeRadius * 2, height: badgeRadius * 2), transform: nil)
    }

    /// Bicycle from the side, stroked: two wheels, diamond frame, saddle, bar.
    static var bike: CGPath {
        let t = bikePlacement
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: 2, y: 30, width: 30, height: 30), transform: t)
        p.addEllipse(in: CGRect(x: 68, y: 30, width: 30, height: 30), transform: t)
        p.addLines(between: [CGPoint(x: 17, y: 45), CGPoint(x: 43, y: 45), CGPoint(x: 40, y: 20),
                             CGPoint(x: 65, y: 20), CGPoint(x: 43, y: 45)], transform: t)
        p.addLines(between: [CGPoint(x: 65, y: 20), CGPoint(x: 83, y: 45)], transform: t)
        p.addLines(between: [CGPoint(x: 33, y: 16), CGPoint(x: 47, y: 16)], transform: t)
        p.addLines(between: [CGPoint(x: 65, y: 20), CGPoint(x: 74, y: 13)], transform: t)
        return p
    }

    /// Bus head on — from the side it went flat next to the bicycle.
    static var busBody: CGPath {
        let t = busPlacement
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 21, y: 5, width: 58, height: 82),
                         cornerWidth: 15, cornerHeight: 15, transform: t)
        p.addLines(between: [CGPoint(x: 28, y: 41), CGPoint(x: 72, y: 41)], transform: t)
        p.addLines(between: [CGPoint(x: 32, y: 87), CGPoint(x: 32, y: 95)], transform: t)
        p.addLines(between: [CGPoint(x: 68, y: 87), CGPoint(x: 68, y: 95)], transform: t)
        return p
    }

    /// The two headlights, filled.
    static var busLights: CGPath {
        let t = busPlacement
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: 29, y: 57, width: 10, height: 10), transform: t)
        p.addEllipse(in: CGRect(x: 61, y: 57, width: 10, height: 10), transform: t)
        return p
    }
}
