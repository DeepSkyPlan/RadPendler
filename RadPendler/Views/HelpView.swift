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
                        "Ein Doppeltipp auf die Box setzt die Pendelstrecke ein: dein Standort als Start, Zuhause oder Arbeit als Ziel. Welches von beidem, entscheidet der Ort — und wenn keiner passt, die Uhrzeit.",
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
                        "Lang drücken springt zurück auf die erste und damit beste Möglichkeit dieser Box.",
                        "Der gelbe Stern steht an dem, was die App empfiehlt.",
                        "Im Detail einer Radroute zeigt ein Balken, wie viele Kilometer auf Hauptstraße, Nebenstraße, Radweg, Weg und Fußweg liegen. Derselbe Balken steht bei jeder aufgezeichneten Fahrt — dort für die Strecke, die du wirklich gefahren bist.",
                        "Beim Rad gibt es „verkehrsarm“ zusätzlich zu „ruhigst“: „ruhigst“ zählt auch Ampeln und Querungen, „verkehrsarm“ fragt nur, wo die Autos sind.",
                    ])
                    section("Die Zeile darunter", "chevron.right.circle", [
                        "Sie zeigt die gewählte Fahrt: Abfahrt → Ankunft, die Abschnitte, Kilometer, Ampeln und wann es losgeht.",
                        "Antippen öffnet die Route im Detail — Zeitstrahl mit Bahnsteigen, Verspätungen und Radabschnitten.",
                    ])
                    section("Karte", "map", [
                        "Die gewählte Fahrt liegt farbig oben, die anderen blass darunter. Ein Tipp auf ein Schild in der Karte wählt diese Fahrt.",
                        "Langes Drücken irgendwo auf der Karte holt die ganze Strecke wieder ins Bild.",
                        "Gelbe Punkte sind vermutete Ampelkreuzungen der gewählten Radroute — aus OpenStreetMap und aus dem, was deine eigenen Fahrten gelernt haben.",
                        "Auf der Karte einer gefahrenen Fahrt sind die Ampeln gelb markiert und tragen ihre Wartezeit; andere Halte stehen klein und grau daneben.",
                    ])
                    section("Regenradar", "cloud.rain", [
                        "Der Schalter unten links auf der Karte zeigt das DWD-Radar. Rechts steht, welche Minute zu sehen ist — „jetzt 14:48“, „in 25 min 15:10“. Ein kleiner Kreisel daneben heißt: Bilder laden noch.",
                        "Play läuft die Bilder durch; der lila Punkt zeigt, wo man zu dieser Minute auf der Strecke wäre.",
                        "Ein Tipp auf die Zeit springt zurück auf jetzt.",
                    ])
                    section("Countdown", "alarm", [
                        "Der rote Kasten erscheint nur, wenn es eine feste Abfahrt gibt: bei Bahn und Bus, oder wenn eine Ankunftszeit gesetzt ist.",
                        "Er zählt bis zum Losgehen — Abfahrt minus Rüstzeit —, unter 10 Minuten sekundengenau.",
                        "Die Warnungen (Einstellungen → Countdown) kommen als Mitteilung aufs Sperrbild, auch wenn die App zu ist; bei offener App zusätzlich als Ton.",
                    ])
                    section("Fahrt aufzeichnen", "record.circle", [
                        "Der grüne Knopf rechts neben der gewählten Fahrt zeichnet auf, was du wirklich fährst: Strecke, Geschwindigkeit, Ampelhalts.",
                        "Oben im roten Band steht, was als Nächstes kommt und in wie vielen Metern. Die Kurven rechnet die App aus der geplanten Linie — es sind Hinweise, keine Navigation, und sie sagt nichts an.",
                        "Die große Zahl ist dein aktuelles Tempo, in der Farbe, in der die Linie gerade gezeichnet wird. Der Pfeil auf der Karte zeigt immer dahin, wo du hinfährst.",
                        "Nach Zoomen oder Schieben kommt die Karte 30 Sekunden später von selbst zu dir zurück. Der Knopf oben links schaltet das Folgen von Hand.",
                        "Der Knopf daneben hält die Ausrichtung fest — automatisch, hochkant, querformat. Am Lenker will man keine Karte, die sich in der Kurve dreht.",
                        "Die Karte geht auf ganze Seite und folgt dir; die gefahrene Linie färbt sich nach Tempo — rot unter 8, grün über 26 km/h. Ein Wisch über die Karte löst das Folgen, der Knopf oben links schaltet es wieder ein.",
                        "Ein Halt zählt ab fünf Sekunden Stillstand. Als Ampelhalt zählt er, wenn er an einer Ampelkreuzung der geplanten Route liegt — oder wenn er länger als 30 Sekunden dauert, denn so lange steht niemand ohne Grund. Die Schwelle steht in den Einstellungen.",
                        "Solche Stellen merkt sich die App. Ab der nächsten Fahrt erkennt sie den Halt dort wieder, und die Ampel zählt auch beim Planen mit — sie macht die Radzeit auf dieser Strecke ehrlicher.",
                        "Die Uhr zeigt dieselben Zahlen, solange das iPhone in Reichweite ist — sie rechnet nichts selbst.",
                        "Die Ortung läuft nur zwischen „Fahrt“ und „Fahrt beenden“, auch in der Tasche (iOS zeigt dabei die blaue Leiste). Danach hört sie auf.",
                    ])
                    section("Gefahrene Fahrten", "list.bullet.rectangle", [
                        "Menü → Fahrten: alle Aufzeichnungen, nach Jahren und Monaten. Die Überschrift eines Monats zeigt Kilometer, Schnitt und Ampelhalts dieses Monats.",
                        "Eine Fahrt antippen zeigt die gefahrene Linie, jede Zahl dazu und die längsten Halte.",
                        "Die Zahlen jeder Fahrt gehen über deine eigene iCloud auf deine anderen Geräte; die gefahrene Linie bleibt auf dem Gerät, auf dem sie aufgezeichnet wurde. Nach links wischen löscht eine Fahrt — auf diesem Gerät.",
                    ])
                    section("Aktualisieren", "arrow.down", [
                        "Seite nach unten ziehen und loslassen. Einen Knopf dafür gibt es nicht mehr.",
                        "Das plant alles neu — auch die Warnungen werden auf den neuen Fahrplan gesetzt. Findet die Suche nichts, bleiben die alten Warnungen scharf.",
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
