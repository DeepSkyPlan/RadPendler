import MapKit
import SwiftUI

/// The screen while a ride is being recorded: the map, large, with the way
/// taken drawn on it in the colours of the speed it was taken at — and the
/// four numbers that are worth looking at on a bike.
///
/// It takes the whole screen on purpose. Everything the planning screen offers
/// is about a trip that has not started yet; this one has.
struct RideTrackingView: View {
    @Environment(RideTracker.self) private var tracker
    @Environment(\.verticalSizeClass) private var heightClass
    var options: [TripOption]
    var selectedID: TripOption.ID?
    /// Ends the ride and hands back its summary.
    var onStop: () -> Void

    @State private var following = true
    @State private var confirmStop = false

    private var isLandscape: Bool { heightClass == .compact }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .topLeading) {
                map
                if isLandscape {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)
                        panel(now: context.date)
                            .frame(width: 260)
                            .padding(10)
                    }
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        panel(now: context.date).padding(10)
                    }
                }
                HStack(spacing: 8) {
                    followButton
                    SpeedLegend()
                }
                .padding(10)
            }
        }
        .confirmationDialog("Fahrt beenden?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Fahrt beenden", role: .destructive, action: onStop)
            Button("Weiterfahren", role: .cancel) {}
        } message: {
            Text("Die Aufzeichnung wird gespeichert und die Ortung hört auf.")
        }
    }

    private var map: some View {
        RouteMapView(options: options, selectedID: selectedID, radarFrames: [], radarTime: nil,
                     track: tracker.meter.points, trackStops: tracker.meter.stops,
                     rider: tracker.here, course: tracker.course, following: following,
                     onPan: { following = false })
            .ignoresSafeArea()
    }

    /// Following gives way to a hand on the map; this is the way back.
    private var followButton: some View {
        Button { following.toggle() } label: {
            Image(systemName: following ? "location.fill" : "location")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(following ? .white : Theme.accent)
                .frame(width: 36, height: 36)
                .background(following ? AnyShapeStyle(Theme.gradient(Theme.accent))
                                      : AnyShapeStyle(.regularMaterial), in: Circle())
        }
        .accessibilityLabel(following ? "Karte folgt dir" : "Karte folgt dir nicht")
    }

    private func panel(now: Date) -> some View {
        VStack(spacing: 8) {
            header
            clock(now: now)
            numbers(now: now)
            signalRow
            stopButton
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let mode = tracker.subject.flatMap({ TravelMode(rawValue: $0.mode) }) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(mode.color)
            }
            Text("\(tracker.subject?.origin ?? "") → \(tracker.subject?.destination ?? "")")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if tracker.meter.isStanding {
                Label("steht", systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func clock(now: Date) -> some View {
        Text(Fmt.clock(tracker.seconds(at: now)))
            .font(.system(size: 46, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Fahrzeit \(Fmt.clock(tracker.seconds(at: now)))")
    }

    private func numbers(now: Date) -> some View {
        HStack(spacing: 8) {
            tile("Ø", Fmt.kmh(tracker.averageKmh(at: now)), tint: Theme.accent)
            tile("jetzt", Fmt.kmh(tracker.meter.currentSpeed * 3.6),
                 tint: RideColors.color(tracker.meter.currentSpeed * 3.6))
            tile("Strecke", Fmt.km(tracker.meter.meters), tint: .primary)
        }
    }

    /// The count the whole recording is for.
    private var signalRow: some View {
        let stops = tracker.meter.signalStops
        let total = tracker.meter.signalWaitTotal
        return HStack(spacing: 8) {
            TrafficLightIcon()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(stops) Ampelhalt\(stops == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(stops == 0 ? "noch keine Wartezeit"
                     : "\(Fmt.clock(total)) gewartet · Ø \(Fmt.clock(total / Double(stops)))")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if tracker.meter.otherStops > 0 {
                Text("\(tracker.meter.otherStops) Halt\(tracker.meter.otherStops == 1 ? "" : "e")")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
    }

    private var stopButton: some View {
        Button { confirmStop = true } label: {
            Label("Fahrt beenden", systemImage: "stop.circle.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.gradient(.red), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: -1) {
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
    }
}

/// What the ride was, right after it ended — the one moment one actually wants
/// to read the numbers.
struct RideSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    var ride: Ride

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RideFacts(ride: ride)
                    RideMapCard(ride: ride)
                        .frame(height: 260)
                }
                .padding(Theme.gutter)
            }
            .background(Theme.background)
            .navigationTitle("Angekommen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
