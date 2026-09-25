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

/// The app icon as a view, so the title bar carries the same mark as the home
/// screen: a green pin with a bicycle, an amber bus badge on its shoulder.
/// The geometry lives in `Mark`, which `tools/make_icon.swift` draws the
/// 1024 px version from — the two cannot drift apart.
struct AppMark: View {
    var size: CGFloat = 24

    var body: some View {
        Canvas { context, box in
            var scale = CGAffineTransform(scaleX: box.width / 100, y: box.height / 100)
            let k = box.width / 100
            func path(_ cg: CGPath) -> Path { Path(cg.copy(using: &scale) ?? cg) }
            let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)

            // The pin is drawn through a square with the badge's hole in it, so
            // the badge sits in open ground instead of on top of the pin.
            context.drawLayer { under in
                under.clip(to: path(Mark.pinClip), style: FillStyle(eoFill: true))
                under.fill(path(Mark.pin), with: .color(Mark.color(Mark.pinTint)))
                under.stroke(path(Mark.pin), with: .color(.white), lineWidth: Mark.outlineWidth * k)
                under.stroke(path(Mark.bike), with: .color(.white),
                             style: round.width(Mark.bikeStroke * k))
            }
            context.fill(path(Mark.badge), with: .color(Mark.color(Mark.badgeTint)))
            context.stroke(path(Mark.badge), with: .color(.white), lineWidth: Mark.outlineWidth * k)
            context.stroke(path(Mark.busBody), with: .color(.white),
                           style: round.width(Mark.busStroke * k))
            context.fill(path(Mark.busLights), with: .color(.white))
        }
        .frame(width: size, height: size)
        .background(LinearGradient(colors: [Mark.color(Mark.backgroundTop),
                                            Mark.color(Mark.backgroundBottom)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .accessibilityHidden(true)
    }
}

private extension StrokeStyle {
    func width(_ w: CGFloat) -> StrokeStyle {
        var copy = self
        copy.lineWidth = w
        return copy
    }
}

extension Mark {
    static func color(_ c: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(.sRGB, red: c.0, green: c.1, blue: c.2)
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
    var icon: AnyView? = nil
    var tint: Color = .secondary
    var strong = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { icon }
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

/// Three dots in a housing: the app's traffic-light mark.
struct TrafficLightIcon: View {
    var size: CGFloat = 11

    var body: some View {
        VStack(spacing: size * 0.08) {
            Circle().fill(.red)
            Circle().fill(.yellow)
            Circle().fill(.green)
        }
        .padding(size * 0.12)
        .frame(width: size * 0.52, height: size * 1.35)
        .background(Color.primary.opacity(0.55), in: RoundedRectangle(cornerRadius: size * 0.18))
    }
}

/// The countdown to leaving: white on red while it is the thing to watch,
/// grey when no departure is fixed. Beeps at the configured minutes.
///
/// It counts to **getting ready**, not to the departure — the same moment the
/// "los …" chip names, because that is the one you can still act on.
struct CountdownBox: View {
    var option: TripOption?
    /// Minutes before leaving that get a beep; empty turns the alarm off.
    var alerts: [Int] = []
    /// Toolbar version: one small pill instead of the three-line block.
    var compact = false
    /// Switched off by the user: the pill stays, greyed, with a struck-through
    /// bell — so it is clear that nothing will ring, and where to switch it on.
    var stopped = false

    @State private var fired: Set<Int> = []
    @State private var watched: TripOption.ID?

    /// Die Uhr, die den Kasten treibt. **Kein `TimelineView`** — und das ist
    /// keine Geschmacksfrage: dieser Kasten sitzt als `ToolbarItem` in der
    /// Navigationsleiste, und ein `TimelineView` in einer Werkzeugleiste legt
    /// unter iOS 26 die Leiste bei jedem Takt neu aus. Dieses Auslegen macht
    /// den Ansichtsgraphen erneut schmutzig, der daraufhin sofort den nächsten
    /// Durchlauf anfordert — eine Rückkopplung, die nie zur Ruhe kommt: der
    /// Hauptthread läuft mit voller Bildrate durch, ohne dass sich etwas
    /// ändert. Gemessen im Simulator, Release, Leerlauf: 70–85 % CPU mit,
    /// 0 % ohne. Auf dem Gerät ist das der Stromfresser, das Ruckeln bei jeder
    /// Berührung und am Ende der `scene-update`-Watchdog.
    ///
    /// Eine eigene Uhr tickt genauso einmal die Sekunde, aber sie schreibt nur
    /// einen Wert — das Auslegen der Leiste löst sie nicht aus.
    @State private var now = Date.now

    var body: some View {
        let left = option.map { $0.getReady.timeIntervalSince(now) }
        let gone = option.map { now > $0.leave } ?? false
        Group {
            if compact { pill(left, gone: gone) } else { content(left, gone: gone) }
        }
        .onChange(of: Int((left ?? 0) / 60)) { _, _ in beep(left) }
        // `id`: ohne etwas zu zählen tickt hier nichts. Die Uhr lief bisher
        // auch dann sekündlich, wenn gar keine Verbindung ausgewählt war —
        // sechzig folgenlose Neuauswertungen je Minute im Leerlauf.
        .task(id: option?.id) {
            guard option != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }

    /// In the title bar there is room for one line: what it is and how long.
    /// The line and its time stay in the trip bar below.
    @ViewBuilder private func pill(_ left: TimeInterval?, gone: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: stopped ? "alarm.waves.left.and.right.fill" : (gone ? "figure.walk.departure" : "alarm.fill"))
                .font(.system(size: 9, weight: .bold))
                .symbolVariant(stopped ? .slash : .none)
            Text(stopped ? L("aus") : (left.map(Self.text) ?? "–"))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            if let option, let leg = option.transitLegs.first, let line = leg.lineName {
                Text(line)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3).padding(.vertical, 0.5)
                    .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .foregroundStyle(left == nil || stopped ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(stopped ? AnyShapeStyle(Color.primary.opacity(0.06)) : Self.box(left, gone: gone), in: Capsule())
        .accessibilityLabel(accessibility(left))
        .accessibilityHint(left == nil && !stopped ? "" : "Tippen, um den Countdown \(stopped ? "einzuschalten" : "auszuschalten")")
    }

    @ViewBuilder private func content(_ left: TimeInterval?, gone: Bool) -> some View {
        VStack(spacing: 1) {
            Text(Countdown.urgency(left, gone: gone).caption(overdue: (left ?? 0) < 0))
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .opacity(0.85)
            Text(left.map(Self.text) ?? "–")
                .font(.system(size: (left ?? 0) < 600 ? 25 : 21, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            if let option, let leg = option.transitLegs.first {
                HStack(spacing: 3) {
                    Text(leg.lineName ?? "")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 3).padding(.vertical, 0.5)
                        .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                    Text(Fmt.time(option.leave)).font(.system(size: 9.5, design: .rounded))
                }
            } else if let option {
                Text(L("ab %@", Fmt.time(option.leave))).font(.system(size: 9.5, design: .rounded))
            }
        }
        .foregroundStyle(left == nil ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
        .padding(.vertical, 7).padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Self.box(left, gone: gone), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(left.map { L("Losgehen in %@", Self.text($0)) } ?? L("Keine feste Abfahrt"))
    }

    /// Green, amber, orange, red, dark red. The steps live in `Countdown`,
    /// so the watch colours the same minute the same way.
    private func accessibility(_ left: TimeInterval?) -> String {
        if stopped { return L("Countdown ausgeschaltet") }
        return left.map { L("Losgehen in %@", Self.text($0)) } ?? L("Keine feste Abfahrt")
    }

    static func box(_ left: TimeInterval?, gone: Bool = false) -> AnyShapeStyle {
        let step = Countdown.urgency(left, gone: gone)
        guard step != .idle else { return AnyShapeStyle(Color.primary.opacity(0.06)) }
        return AnyShapeStyle(LinearGradient(colors: step.colors.map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2) },
                                            startPoint: .top, endPoint: .bottom))
    }

    static func text(_ left: TimeInterval) -> String { Countdown.text(left) }

    /// One beep per threshold per trip; a new trip clears what was fired.
    private func beep(_ left: TimeInterval?) {
        guard let option, let left, !alerts.isEmpty else { return }
        if watched != option.id {
            watched = option.id
            fired = []
        }
        let minutes = Int((left / 60).rounded(.up))
        guard left > 0, alerts.contains(minutes), fired.insert(minutes).inserted else { return }
        Alarm.beep()
    }
}


