import SwiftUI

/// One place for the look of the app: rounded type, soft cards on a tinted
/// background, one accent gradient per travel mode. Everything derives from
/// system colours, so light and dark both work without a second palette.
enum Theme {
    static let corner: CGFloat = 22
    static let innerCorner: CGFloat = 14
    static let gutter: CGFloat = 16

    static let accent = Color(red: 0.00, green: 0.62, blue: 0.51)

    /// Page background: a very quiet wash of the accent over the grouped grey.
    static var background: some View {
        LinearGradient(colors: [Color(.systemGroupedBackground),
                                accent.opacity(0.10),
                                Color(.systemGroupedBackground)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Card used for every block on the screen.
struct CardBackground: ViewModifier {
    var highlighted = false
    var tint: Color = Theme.accent

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(highlighted ? AnyShapeStyle(Theme.gradient(tint)) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                  lineWidth: highlighted ? 2 : 1)
            }
            .shadow(color: .black.opacity(highlighted ? 0.10 : 0.05), radius: highlighted ? 14 : 6, y: 4)
    }
}

extension View {
    func card(highlighted: Bool = false, tint: Color = Theme.accent) -> some View {
        modifier(CardBackground(highlighted: highlighted, tint: tint))
    }

    /// Rounded system font in one call: `.display(.title2)`.
    func display(_ font: Font.TextStyle, weight: Font.Weight = .semibold) -> some View {
        self.font(.system(font, design: .rounded, weight: weight))
    }
}

/// Small capsule for one fact: "19,5 km", "43 Ampeln", "direkt".
struct Chip: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = .secondary
    var strong = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text).font(.system(.caption, design: .rounded, weight: strong ? .semibold : .regular))
        }
        .foregroundStyle(strong ? tint : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(strong ? tint.opacity(0.14) : Color.primary.opacity(0.05),
                    in: Capsule(style: .continuous))
    }
}

/// Icon in a filled circle, the app's recurring mark for a mode or a leg.
struct ModeBubble: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.gradient(color), in: Circle())
            .shadow(color: color.opacity(0.35), radius: 6, y: 3)
    }
}

/// Animated pill switch, used for Liste/Karte.
struct PillPicker<T: Hashable>: View {
    var items: [(value: T, title: String, symbol: String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                let active = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item.value }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(active ? Color.white : .secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if active {
                                Capsule(style: .continuous).fill(Theme.gradient(Theme.accent))
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
    }
}

/// "Los in 12:30" — how long until one has to leave to catch the train.
/// Counts every second below ten minutes, then in whole minutes.
struct CountdownView: View {
    var option: TripOption

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = option.leave.timeIntervalSince(context.date)
            VStack(alignment: .trailing, spacing: 1) {
                Text(left < 0 ? "ABGEFAHREN" : "LOS IN")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(Self.text(left))
                    .font(.system(size: left < 600 ? 26 : 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.tint(left))
                    .contentTransition(.numericText(countsDown: true))
                HStack(spacing: 3) {
                    if let leg = option.transitLegs.first { LineBadge(leg: leg) }
                    Text("ab \(Fmt.time(option.leave))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("Losgehen in \(Self.text(left))")
        }
    }

    static func text(_ left: TimeInterval) -> String {
        let s = Int(left.rounded())
        guard s >= 0 else { return "jetzt" }
        if s < 600 { return String(format: "%d:%02d", s / 60, s % 60) }
        let m = s / 60
        return m < 60 ? "\(m) min" : String(format: "%d:%02d h", m / 60, m % 60)
    }

    static func tint(_ left: TimeInterval) -> Color {
        switch left {
        case ..<0: .red
        case ..<300: .orange
        default: Theme.accent
        }
    }
}
