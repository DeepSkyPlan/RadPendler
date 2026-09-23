import MapKit
import SwiftUI

/// The rides that were actually ridden, newest first, in the months and years
/// they happened in. The heading of a month carries its sums — that is what
/// one comes here for after the first week: not a single ride, but whether
/// this month was faster than the last.
struct RidesView: View {
    @Environment(RideStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: Ride?

    private var years: [Ride.Year] { Ride.grouped(store.rides) }

    var body: some View {
        NavigationStack {
            Group {
                if store.rides.isEmpty {
                    ContentUnavailableView("Noch keine Fahrt",
                                           systemImage: "figure.outdoor.cycle",
                                           description: Text("Auf der Hauptseite eine Verbindung wählen und „Fahrt aufzeichnen“ antippen. Was aufgezeichnet wurde, steht danach hier."))
                } else {
                    list
                }
            }
            .navigationTitle("Fahrten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                if store.syncing {
                    ToolbarItem(placement: .topBarLeading) { ProgressView().controlSize(.mini) }
                }
            }
            .task { await store.syncFromCloud() }
        }
    }

    private var list: some View {
        List {
            ForEach(years) { year in
                Section {
                    ForEach(year.months) { month in
                        MonthHeader(month: month)
                        ForEach(month.rides) { ride in
                            NavigationLink { RideDetailView(ride: ride) } label: { RideRow(ride: ride) }
                                .swipeActions {
                                    Button("Löschen", systemImage: "trash", role: .destructive) {
                                        pendingDelete = ride
                                    }
                                }
                        }
                    }
                } header: {
                    YearHeader(year: year)
                }
            }
        }
        .listStyle(.plain)
        .confirmationDialog("Fahrt löschen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                  set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let ride = pendingDelete { store.delete(ride) }
                pendingDelete = nil
            }
            Button("Behalten", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Auch aus deiner iCloud — auf allen Geräten.")
        }
    }
}

private struct YearHeader: View {
    var year: Ride.Year

    var body: some View {
        HStack(spacing: 6) {
            Text(String(year.id))
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text("\(Fmt.km(year.meters)) · \(year.rides.count) \(year.rides.count == 1 ? "Fahrt" : "Fahrten") · Ø \(Fmt.kmh(year.averageKmh))")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private struct MonthHeader: View {
    var month: Ride.Month

    var body: some View {
        HStack(spacing: 6) {
            Text(month.title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text("\(month.rides.count)× · \(Fmt.km(month.meters)) · Ø \(Fmt.kmh(month.averageKmh)) · \(month.signalStops) Ampeln")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .listRowBackground(Theme.accent.opacity(0.07))
        .padding(.vertical, 1)
    }
}

/// One ride in one line and a half: when, how long, how fast, how many lights.
struct RideRow: View {
    var ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: ride.travelMode?.symbol ?? "bicycle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ride.travelMode?.color ?? Theme.accent)
                Text(ride.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(Fmt.time(ride.started))
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Fmt.clock(ride.seconds))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                Chip(text: Fmt.km(ride.meters), symbol: "ruler")
                Chip(text: Fmt.kmh(ride.averageKmh), symbol: "speedometer")
                Chip(text: "\(ride.signalStops)", icon: AnyView(TrafficLightIcon()))
                if ride.signalStops > 0 {
                    Chip(text: Fmt.clock(ride.signalWaitTotal), symbol: "hourglass")
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One ride: the map of the way taken, and every number that was measured.
struct RideDetailView: View {
    var ride: Ride

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RideMapCard(ride: ride).frame(height: 300)
                RideFacts(ride: ride)
                StopList(ride: ride)
            }
            .padding(Theme.gutter)
        }
        .background(Theme.background)
        .navigationTitle(ride.started.formatted(.dateTime.day().month().year().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The map of a finished ride. The track is fetched when the view appears —
/// from the device, or from iCloud when the ride was recorded on another one.
struct RideMapCard: View {
    @Environment(RideStore.self) private var store
    var ride: Ride
    @State private var track: RideTrack?
    @State private var searched = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let track, track.points.count > 1 {
                RouteMapView(options: [], selectedID: nil, radarFrames: [], radarTime: nil,
                             track: track.points, trackStops: track.stops)
                SpeedLegend().padding(8)
            } else if searched {
                ContentUnavailableView("Keine Linie",
                                       systemImage: "map",
                                       description: Text("Die Aufzeichnung liegt auf dem Gerät, auf dem sie entstanden ist — sie kommt, sobald iCloud sie herübergereicht hat."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .task {
            track = await store.track(for: ride)
            searched = true
        }
    }
}

/// Every number of one ride, in the order they matter.
struct RideFacts: View {
    var ride: Ride

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: ride.travelMode?.symbol ?? "bicycle")
                    .foregroundStyle(ride.travelMode?.color ?? Theme.accent)
                Text("\(ride.origin) → \(ride.destination)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("\(Fmt.time(ride.started)) → \(Fmt.time(ride.ended))")
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                fact("Fahrzeit", Fmt.clock(ride.seconds), .primary)
                fact("Strecke", Fmt.km(ride.meters), .primary)
                fact("Ø gesamt", Fmt.kmh(ride.averageKmh), Theme.accent)
                fact("Ø rollend", Fmt.kmh(ride.movingKmh), RideColors.color(ride.movingKmh))
                fact("Spitze", Fmt.kmh(ride.maxKmh), RideColors.color(ride.maxKmh))
                fact("gestanden", Fmt.clock(ride.standingSeconds), .orange)
                fact("Ampelhalts", "\(ride.signalStops)", .yellow)
                fact("Ampelwartezeit", Fmt.clock(ride.signalWaitTotal), .yellow)
                fact("Ø je Ampel", ride.signalStops == 0 ? "–" : Fmt.clock(ride.signalWaitAverage), .yellow)
            }
            if let off = ride.deviationSeconds {
                // The one comparison that judges the app rather than the rider.
                Label(off <= 0 ? "\(Fmt.clock(-off)) schneller als geplant"
                               : "\(Fmt.clock(off)) länger als geplant",
                      systemImage: off <= 0 ? "checkmark.circle" : "clock.badge.exclamationmark")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(off <= 0 ? .green : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .card()
    }

    private func fact(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
        .accessibilityElement(children: .combine)
    }
}

/// Where the ride stood and for how long — the longest waits first, because
/// those are the junctions one might want to ride around next time.
private struct StopList: View {
    @Environment(RideStore.self) private var store
    var ride: Ride
    @State private var stops: [RideStop] = []

    var body: some View {
        Group {
            if !stops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Halte")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    ForEach(stops.sorted { $0.seconds > $1.seconds }.prefix(12)) { stop in
                        HStack(spacing: 8) {
                            if stop.atSignal {
                                TrafficLightIcon()
                            } else {
                                Image(systemName: "pause.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Text(stop.atSignal ? "Ampel" : "Halt")
                                .font(.system(size: 13, design: .rounded))
                            Text(Fmt.time(stop.start))
                                .font(.system(size: 11, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(Fmt.clock(stop.seconds))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
        .task { stops = await store.track(for: ride)?.stops ?? [] }
    }
}
