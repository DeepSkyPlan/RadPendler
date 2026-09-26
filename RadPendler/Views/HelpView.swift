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
                    section(L("Start und Ziel"), "mappin.and.ellipse", [
                        L("Oben auf die beiden Zeilen tippen und die Adresse suchen. Beide bleiben nur auf diesem Gerät."),
                        L("Ein Doppeltipp auf die Box setzt die Pendelstrecke ein: dein Standort als Start, Zuhause oder Arbeit als Ziel. Welches von beidem, entscheidet der Ort — und wenn keiner passt, die Uhrzeit."),
                        L("Der Pfeil daneben dreht die Richtung um."),
                        L("Ist das Ziel die Arbeitsadresse (Einstellungen → Arbeitsweg), startet die Suche mit „Ankunft“, sonst mit „Abfahrt jetzt“."),
                    ])
                    section(L("Sprache"), "globe", [
                        L("Im Menü stehen drei Fähnchen: wie das Telefon, Deutsch, English. Die Umstellung wirkt sofort, ohne Neustart — auch Zahlen und Uhrzeiten folgen mit."),
                        L("Die Uhr spricht, was das Telefon spricht: sie zeigt dessen Plan, also auch in dessen Sprache."),
                    ])
                    section(L("Abfahrt oder Ankunft"), "clock", [
                        L("„Abfahrt“ sucht ab einer Startzeit — Jetzt oder eine der gespeicherten Startzeiten."),
                        L("„Ankunft“ sucht rückwärts und bietet die zwei Zeiten an, die der Pendelweg wirklich hat: 9 Uhr hin, 19 Uhr zurück. Jede andere Zeit über das Uhr-Feld."),
                        L("Die Rüstzeit ist die Zeit vom Blick auf die App bis zum Losgehen; sie steckt in „los …“."),
                    ])
                    section(L("Die vier Boxen"), "square.grid.2x2", [
                        L("Fahrrad, Rad + Bahn, Auto, Bus & Bahn — jede Box zeigt die Fahrzeit und worum es sich handelt: bei Radrouten schnellst, kürzest, optimal oder ruhigst, bei Verbindungen die Abfahrt."),
                        L("Ein Tipp wählt die Box aus, der nächste Tipp schaltet zur nächsten Möglichkeit. Die Punkte unter der Zeit zeigen, wie viele es sind."),
                        L("Lang drücken springt zurück auf die erste und damit beste Möglichkeit dieser Box."),
                        L("Der gelbe Stern steht an dem, was die App empfiehlt."),
                        L("Im Detail einer Radroute zeigt ein Balken, wie viele Kilometer auf Hauptstraße, Nebenstraße, Radweg, Weg und Fußweg liegen. Derselbe Balken steht bei jeder aufgezeichneten Fahrt — dort für die Strecke, die du wirklich gefahren bist."),
                        L("Beim Rad gibt es „verkehrsarm“ zusätzlich zu „ruhigst“: „ruhigst“ zählt auch Ampeln und Querungen, „verkehrsarm“ fragt nur, wo die Autos sind."),
                    ])
                    section(L("Die Zeile darunter"), "chevron.right.circle", [
                        L("Sie zeigt die gewählte Fahrt: Abfahrt → Ankunft, die Abschnitte, Kilometer, Ampeln und wann es losgeht."),
                        L("Antippen öffnet die Route im Detail — Zeitstrahl mit Bahnsteigen, Verspätungen und Radabschnitten."),
                    ])
                    section(L("Karte"), "map", [
                        L("Die gewählte Fahrt liegt farbig oben, die anderen blass darunter. Ein Tipp auf ein Schild in der Karte wählt diese Fahrt."),
                        L("Langes Drücken irgendwo auf der Karte holt die ganze Strecke wieder ins Bild."),
                        L("Gelbe Punkte sind vermutete Ampelkreuzungen der gewählten Radroute — aus OpenStreetMap und aus dem, was deine eigenen Fahrten gelernt haben."),
                        L("Auf der Karte einer gefahrenen Fahrt sind die Ampeln gelb markiert und tragen ihre Wartezeit; andere Halte stehen klein und grau daneben."),
                    ])
                    section(L("Regenradar"), "cloud.rain", [
                        L("Der Schalter unten links auf der Karte zeigt das DWD-Radar. Rechts steht, welche Minute zu sehen ist — „jetzt 14:48“, „in 25 min 15:10“. Ein kleiner Kreisel daneben heißt: Bilder laden noch."),
                        L("Play läuft die Bilder durch; der lila Punkt zeigt, wo man zu dieser Minute auf der Strecke wäre."),
                        L("Ein Tipp auf die Zeit springt zurück auf jetzt."),
                    ])
                    section(L("Countdown"), "alarm", [
                        L("Der rote Kasten erscheint nur, wenn es eine feste Abfahrt gibt: bei Bahn und Bus, oder wenn eine Ankunftszeit gesetzt ist."),
                        L("Er zählt bis zum Losgehen — Abfahrt minus Rüstzeit —, unter 10 Minuten sekundengenau."),
                        L("Die Warnungen (Einstellungen → Countdown) kommen als Mitteilung aufs Sperrbild, auch wenn die App zu ist; bei offener App zusätzlich als Ton."),
                    ])
                    section(L("Fahrt aufzeichnen"), "record.circle", [
                        L("Der grüne Knopf rechts neben der gewählten Fahrt zeichnet auf, was du wirklich fährst: Strecke, Geschwindigkeit, Ampelhalts."),
                        L("Oben im roten Band steht, was als Nächstes kommt und in wie vielen Metern. Die Kurven rechnet die App aus der geplanten Linie — es sind Hinweise, keine Navigation, und sie sagt nichts an."),
                        L("Die große Zahl ist dein aktuelles Tempo, in der Farbe, in der die Linie gerade gezeichnet wird. Der Pfeil auf der Karte zeigt immer dahin, wo du hinfährst."),
                        L("Der Abbiegepfeil ist grün und kommt erst 250 m vor der Abbiegung — ein Pfeil, der zwei Kilometer lang „rechts“ sagt, sieht man nicht mehr an, wenn es so weit ist. Rot ist nur eines: dass du neben der Route bist."),
                        L("Unten steht, was noch kommt: Reststrecke, Restzeit und die Uhrzeit der Ankunft. Oben in der Leiste stehen dieselben zwei Zahlen statt des Countdowns — losgehen musst du nicht mehr."),
                        L("Die Ampelzeile zählt „gehalten von geplant“ und läuft sekündlich mit, solange du stehst; die gelben Punkte auf der Karte sind die Ampeln, die die Planung kennt."),
                        L("Die Ausrichtung, die du im Fahrtmodus wählst, gilt ab dann für jede Fahrt. Nach „Fahrt beenden“ dreht sich die App wieder wie jede andere."),
                        L("Nach Zoomen oder Schieben kommt die Karte 30 Sekunden später von selbst zu dir zurück. Der Knopf oben links schaltet das Folgen von Hand."),
                        L("Der Knopf daneben hält die Ausrichtung fest — automatisch, hochkant, querformat. Am Lenker will man keine Karte, die sich in der Kurve dreht."),
                        L("Die Karte geht auf ganze Seite und folgt dir; die gefahrene Linie färbt sich nach Tempo — rot unter 8, grün über 26 km/h. Ein Wisch über die Karte löst das Folgen, der Knopf oben links schaltet es wieder ein."),
                        L("Ein Halt zählt ab fünf Sekunden Stillstand. Als Ampelhalt zählt er, wenn er an einer Ampelkreuzung der geplanten Route liegt — oder wenn er länger als 30 Sekunden dauert, denn so lange steht niemand ohne Grund. Die Schwelle steht in den Einstellungen. Das Stehen vor der ersten Kurbelumdrehung und das Stehen nach der Ankunft zählen nie als Ampel: das ist die eigene Haustür, keine Kreuzung."),
                        L("Solche Stellen merkt sich die App. Ab der nächsten Fahrt erkennt sie den Halt dort wieder, und die Ampel zählt auch beim Planen mit."),
                        L("Dabei zählt jede Aufzeichnung auch, wo sie ohne Halt durchgekommen ist. Eine gelernte Kreuzung kostet beim Planen deshalb nicht den eingestellten Mittelwert, sondern das, was sie dich im Schnitt wirklich gekostet hat — über alle Vorbeifahrten, nicht nur über die Male mit Rot."),
                        L("Die Uhr zeigt dieselben Zahlen, solange das iPhone in Reichweite ist — sie rechnet nichts selbst."),
                        L("„Pause“ hält die Fahrt an: die Uhr steht, die Ortung ist so lange aus, und die Pause zählt weder zur Fahrzeit noch als Halt. „Weiter“ nimmt sie wieder auf. Das ist auch der Knopf, der während einer Fahrt am meisten Strom spart."),
                        L("Von selbst hält sie nach drei Minuten Stillstand an, wenn dort keine Ampel ist — und läuft weiter, sobald du wieder rollst. Die Ortung bleibt dabei an, aber sparsam. Der Halt selbst zählt als Halt: an der Schranke hast du gestanden."),
                        L("Steht sie zwanzig Minuten, bist du angekommen und hast das Beenden vergessen: dann endet die Aufzeichnung und zählt bis zum Anfang des Stillstands. Beide Zeiten stehen in den Einstellungen, „aus“ schaltet sie ab."),
                        L("Der dritte Knopf oben links schaltet beides für diese eine Fahrt ab — für den echten Stau, von dem du weißt, dass es gleich weitergeht. Beim nächsten Start ist die Automatik wieder an."),
                        L("Der Bildschirm wird dunkel, solange du ihn nicht anfasst, und beim ersten Antippen wieder hell — ebenso, wenn eine Abbiegung ansteht oder du neben der Route bist. Er ist während einer Fahrt der größte Posten auf der Stromrechnung, größer als die Ortung."),
                        L("Eine Fahrt beginnt quer. Stellst du es während der Fahrt um, gilt das ab dann für jede."),
                        L("Die Ortung läuft nur zwischen „Fahrt“ und „Fahrt beenden“, auch in der Tasche (iOS zeigt dabei die blaue Leiste). Danach hört sie auf."),
                    ])
                    section(L("Gefahrene Fahrten"), "list.bullet.rectangle", [
                        L("Menü → Fahrten: alle Aufzeichnungen, nach Jahren und Monaten. Die Überschrift eines Monats zeigt Kilometer, Schnitt und Ampelhalts dieses Monats."),
                        L("Eine Fahrt antippen zeigt die gefahrene Linie, jede Zahl dazu und die längsten Halte. Die geplante Route liegt dünn und grau daneben — der Unterschied ist die eigentliche Auskunft."),
                        L("Darunter: das Höhenprofil der Fahrt, und was angekündigt war — Ampeln und Schnitt gegen das, was daraus wurde."),
                        L("Die Zahlen jeder Fahrt gehen über deine eigene iCloud auf deine anderen Geräte, die gefahrene Linie seit 1.3 ebenfalls — in deine private CloudKit-Datenbank, die außer dir niemand lesen kann. Nach links wischen löscht eine Fahrt, seit 1.4 auf allen deinen Geräten: was du löschst, bleibt gelöscht."),
                    ])
                    section(L("Aktualisieren"), "arrow.clockwise", [
                        L("Unter der Karte steht, von wann der Stand ist — „Stand 14:48 · gerade eben“. Ein Tipp darauf plant neu."),
                        L("Das plant alles neu — auch die Warnungen werden auf den neuen Fahrplan gesetzt. Findet die Suche nichts, bleiben die alten Warnungen scharf."),
                        L("Von selbst wird nicht neu geplant, solange sich nichts geändert hat: dieselbe Frage bekommt fünf Minuten lang dieselbe Antwort. Zwischen den Boxen zu springen kostet also keine einzige Anfrage."),
                    ])
                    section(L("Was die App voraussetzt"), "info.circle", [
                        L("Fahrzeiten mit dem Rad rechnen sich aus der rollenden Geschwindigkeit plus Wartezeit je Ampelkreuzung plus fünf Sekunden je Höhenmeter — Tempo und Wartezeit stehen in den Einstellungen. Wo eigene Fahrten eine Kreuzung schon kennen, gilt deren gemessene Zeit statt der eingestellten."),
                        L("Beide Werte schreibt die App nach jeder Fahrt selbst fort, aus dem Median der letzten Fahrten. Und sobald es genug Fahrten gibt, gilt für die angezeigte Radzeit dein gemessener Tür-zu-Tür-Schnitt — ob er langsamer oder schneller ist als die Rechnung. Welche der Linien die schnellste ist, entscheidet weiter die Rechnung: nur sie kennt den Unterschied zwischen zwei und dreißig Ampeln."),
                        L("Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet; S-Bahn und Regionalzug zuerst, U-Bahn und Tram nur als markierte Alternative."),
                        L("Fixpunkte (Einstellungen) sind Orte, über die die Strecke führen soll; Verbindungen ohne sie werden ausgegraut und nie empfohlen."),
                        L("Alle Zeiten ohne Gewähr."),
                    ])
                }
                .padding(Theme.gutter)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .navigationTitle(L("Anleitung"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { dismiss() } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMark(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("RadPendler").display(.title3, weight: .bold)
                Text(L("Version %@", ContentView.version))
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
