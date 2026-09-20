import SwiftUI

/// The short manual, reachable from the burger menu. Written for the one person
/// who uses the app, in the order things are used.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    section("Start und Ziel", "mappin.and.ellipse", [
                        "Oben auf die beiden Zeilen tippen und die Adresse suchen. Beide bleiben nur auf diesem Gerät.",
                        "Der Pfeil daneben dreht die Richtung um.",
                        "Ist das Ziel die Arbeitsadresse (Einstellungen → Arbeitsweg), startet die Suche mit „Ankunft“, sonst mit „Abfahrt jetzt“.",
                    ])
                    section("Abfahrt oder Ankunft", "clock", [
                        "„Abfahrt“ sucht ab einer Startzeit — Jetzt oder eine der gespeicherten Startzeiten.",
                        "„Ankunft“ sucht rückwärts und bietet die zwei Zeiten an, die der Pendelweg wirklich hat: 9 Uhr hin, 19 Uhr zurück. Jede andere Zeit über das Uhr-Feld.",
                        "Die Rüstzeit ist die Zeit vom Blick auf die App bis zum Losgehen; sie steckt in „los …“.",
                    ])
                    section("Die vier Boxen", "square.grid.2x2", [
                        "Fahrrad, Rad + Bahn, Auto, Bus & Bahn — jede Box zeigt die Fahrzeit und worum es sich handelt: bei Radrouten schnellst, kürzest, optimal oder ruhigst, bei Verbindungen die Abfahrt.",
                        "Ein Tipp wählt die Box aus, der nächste Tipp schaltet zur nächsten Möglichkeit. Die Punkte unter der Zeit zeigen, wie viele es sind.",
                        "Der gelbe Stern steht an dem, was die App empfiehlt.",
                    ])
                    section("Die Zeile darunter", "chevron.right.circle", [
                        "Sie zeigt die gewählte Fahrt: Abfahrt → Ankunft, die Abschnitte, Kilometer, Ampeln und wann es losgeht.",
                        "Antippen öffnet die Route im Detail — Zeitstrahl mit Bahnsteigen, Verspätungen und Radabschnitten.",
                    ])
                    section("Karte", "map", [
                        "Die gewählte Fahrt liegt farbig oben, die anderen blass darunter. Ein Tipp auf ein Schild in der Karte wählt diese Fahrt.",
                        "Langes Drücken auf eine Radlinie schaltet zur nächsten Radroute.",
                        "Gelbe Punkte sind vermutete Ampelkreuzungen der gewählten Radroute.",
                    ])
                    section("Regenradar", "cloud.rain", [
                        "Der Schalter unten links auf der Karte zeigt das DWD-Radar. Rechts steht, welche Minute zu sehen ist — „jetzt 14:48“, „in 25 min 15:10“.",
                        "Play läuft die Bilder durch; der lila Punkt zeigt, wo man zu dieser Minute auf der Strecke wäre.",
                        "Ein Tipp auf die Zeit springt zurück auf jetzt.",
                    ])
                    section("Countdown", "alarm", [
                        "Der rote Kasten erscheint nur, wenn es eine feste Abfahrt gibt: bei Bahn und Bus, oder wenn eine Ankunftszeit gesetzt ist.",
                        "Er zählt bis zum Losgehen — Abfahrt minus Rüstzeit —, unter 10 Minuten sekundengenau.",
                        "Die Warnungen (Einstellungen → Countdown) kommen als Mitteilung aufs Sperrbild, auch wenn die App zu ist; bei offener App zusätzlich als Ton.",
                    ])
                    section("Aktualisieren", "arrow.down", [
                        "Seite nach unten ziehen und loslassen. Einen Knopf dafür gibt es nicht mehr.",
                        "Unten steht, von wann der Stand ist.",
                    ])
                    section("Was die App voraussetzt", "info.circle", [
                        "Fahrzeiten mit dem Rad rechnen sich aus der rollenden Geschwindigkeit plus Wartezeit je Ampelkreuzung — beides in den Einstellungen.",
                        "Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet; S-Bahn und Regionalzug zuerst, U-Bahn und Tram nur als markierte Alternative.",
                        "Fixpunkte (Einstellungen) sind Orte, über die die Strecke führen soll; Verbindungen ohne sie werden ausgegraut und nie empfohlen.",
                        "Alle Zeiten ohne Gewähr.",
                    ])
                }
                .padding(Theme.gutter)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .navigationTitle("Anleitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMark(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("RadPendler").display(.title3, weight: .bold)
                Text("Version \(ContentView.version)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ title: String, _ symbol: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.accent)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Circle().fill(Theme.accent.opacity(0.35)).frame(width: 4, height: 4).padding(.top, 7)
                    Text(line).font(.system(.subheadline, design: .rounded))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}
