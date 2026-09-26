import MapKit
import SwiftUI

/// Play/pause and scrubber for the radar frames — and, on the main screen, the
/// line underneath that says how old the plan above it is.
struct RadarControls: View {
    var frames: [Date]
    @Binding var index: Int
    @Binding var visible: Bool
    /// Lifted out of this view so the map knows whether to hold the
    /// neighbouring frames ready.
    @Binding var playing: Bool
    /// When the plan on screen was computed; nil leaves the second line away.
    var lastRun: Date? = nil
    var loading = false
    var onRefresh: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 5) {
            controls
            if let onRefresh { LastRunLine(lastRun: lastRun, loading: loading, action: onRefresh) }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $visible) { Image(systemName: "cloud.rain") }
                .toggleStyle(.button)
                .accessibilityLabel(L("Regenradar"))
            // Tiles still coming in: say so, an empty sky and a missing sky
            // look exactly alike.
            if visible, RadarLoads.shared.isLoading {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel(L("Radarbilder werden geladen"))
            }
            if visible, !frames.isEmpty {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(playing ? L("Anhalten") : L("Abspielen"))
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                       in: 0...Double(max(frames.count - 1, 1)), step: 1)
                // Which minute is on the map — "jetzt 14:48", "in 25 min 15:10".
                // Tapping jumps back to the current frame.
                Button {
                    playing = false
                    index = Self.nearest(.now, in: frames)
                } label: {
                    VStack(alignment: .trailing, spacing: -1) {
                        Text(Self.relative(shown))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(Fmt.time(shown))
                            .font(.callout.monospacedDigit().weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 74, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Regenradar %@, %@. Tippen für jetzt.", Self.relative(shown), Fmt.time(shown)))
            } else {
                Text(L("Regenradar (DWD)")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .task(id: playing) {
            while playing, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard playing else { break }
                index = index + 1 < frames.count ? index + 1 : 0
            }
        }
    }

    private var shown: Date { frames[min(index, frames.count - 1)] }

    /// A radar frame in words: measured minutes ago, now, or a forecast ahead.
    static func relative(_ frame: Date, now: Date = .now) -> String {
        let m = Int((frame.timeIntervalSince(now) / 60).rounded())
        if m <= -60 { return L("vor %d h", -m / 60) }
        if m < -2 { return L("vor %d min", -m) }
        if m <= 2 { return L("jetzt") }
        if m < 60 { return L("in %d min", m) }
        return m % 60 == 0 ? L("in %d h", m / 60) : "in \(m / 60):\(String(format: "%02d", m % 60)) h"
    }

    /// Index of the frame closest to a moment.
    static func nearest(_ target: Date, in frames: [Date]) -> Int {
        frames.enumerated()
            .min { abs($0.element.timeIntervalSince(target)) < abs($1.element.timeIntervalSince(target)) }?.offset ?? 0
    }
}

/// When the plan above was computed and how long ago that was, on the same
/// axis as the radar minutes. Tapping it plans again — the main screen does not
/// scroll any more, so there is no pull.
struct LastRunLine: View {
    var lastRun: Date?
    var loading: Bool
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(text(now: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lastRun == nil ? L("Neu berechnen") : L("Berechnet %@. Tippen für neu berechnen.", text(now: context.date)))
        }
    }

    private func text(now: Date) -> String {
        guard let lastRun else { return loading ? L("wird berechnet …") : L("neu berechnen") }
        return L("Stand %@ · %@", Fmt.time(lastRun), Fmt.age(now.timeIntervalSince(lastRun)))
    }

}

/// Map plus radar controls, shared by the map tab and the detail screen.
struct TripMapPanel: View {
    var options: [TripOption]
    var selectedID: TripOption.ID?
    var waypoints: [Place] = []
    /// Start und Ziel, für die Zeit vor der ersten Route.
    var ends: [CLLocationCoordinate2D] = []
    var onSelect: ((TripOption.ID) -> Void)? = nil
    /// The stamp on the time axis: when the plan was computed, and the way back
    /// to a fresh one. Left away on the detail screen, which plans nothing.
    var lastRun: Date? = nil
    var loading = false
    var onRefresh: (() -> Void)? = nil
    @State private var frames = RadarTileOverlay.frameTimes()
    @State private var index = 0
    @State private var radarOn = true
    @State private var playing = false

    private var trip: TripOption? { options.first { $0.id == selectedID } }

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteMapView(options: options, selectedID: selectedID, radarFrames: radarOn ? frames : [],
                         radarTime: radarOn && frames.indices.contains(index) ? frames[index] : nil,
                         radarPreload: playing,
                         waypoints: waypoints, ends: ends, onSelect: onSelect)
            RadarControls(frames: frames, index: $index, visible: $radarOn, playing: $playing,
                          lastRun: lastRun, loading: loading, onRefresh: onRefresh)
                .padding(8)
        }
        .onAppear { resetFrames() }
        // An der **Reise**, nicht an der Auswahl: eine Planung meldet vier
        // Zwischenstände, und jeder davon hat eine andere Kennung, aber
        // dieselben Zeiten. Die Bildliste neu zu legen hieß jedes Mal, die
        // sichtbaren DWD-Kacheln noch einmal zu holen.
        .onChange(of: tripWindow) { resetFrames() }
    }

    /// Von wann bis wann die Reise geht, auf zehn Minuten gerundet — feiner
    /// unterscheidet die Bildliste ohnehin nicht.
    private var tripWindow: String {
        guard let trip else { return "-" }
        let step = 600.0
        return "\(Int(trip.leave.timeIntervalSince1970 / step))|\(Int(trip.arrival.timeIntervalSince1970 / step))"
    }

    /// Frames around the selected trip, so pressing play runs the ride and the
    /// rain forward together — but the map opens on the current minute, because
    /// that is the one thing you always want to see first.
    private func resetFrames() {
        guard let trip else {
            frames = RadarTileOverlay.frameTimes()
            index = RadarControls.nearest(.now, in: frames)
            return
        }
        frames = RadarTileOverlay.frameTimes(forTripFrom: trip.leave, to: trip.arrival)
        index = RadarControls.nearest(.now, in: frames)
    }
}
