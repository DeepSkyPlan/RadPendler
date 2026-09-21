# RadPendler — Übergabe (Stand 21.09.2026, 0.10.0 / Build 16)

Multimodaler Pendel-Planer für iPhone, iPad und Apple Watch: Musterstraße 1 (Büro) ↔
Beispielweg 2 (Musterort) mit Fahrrad, Rad + Bahn, Auto und ÖPNV, inklusive Ampeln,
Regen und Countdown.
Verzeichnis `~/_claude.code/RadPendler`, git mit Remote `DeepSkyPlan/RadPendler` (privat).

## Bauen, testen, ausliefern

```bash
./dev test      # generiert das .xcodeproj bei Bedarf, dann 61 Tests im Simulator
./dev open      # Xcode mit demselben DerivedData wie die Kommandozeile
./dev generate  # nur neu generieren, nach jeder neuen Quelldatei
```

Das `.xcodeproj` ist generiert und nicht committet: Änderungen im Projektnavigator
überlebt kein `generate`. Struktur gehört in `project.yml`.

Die Watch-App hängt als Abhängigkeit am iPhone-Ziel und wird nach `Watch/` kopiert;
`./dev build` baut sie mit. Einzeln: `-scheme RadPendlerWatch` mit einem
`platform=watchOS Simulator`-Ziel.

TestFlight (nur auf Ansage des Nutzers, siehe Memory `testflight-only-on-request`):
Buildnummer in `project.yml` hochzählen → `xcodegen generate` → `clean archive` →
`-exportArchive` mit `ExportOptions.plist` (method `app-store-connect`, destination `upload`,
Team `5PX3V6L522`) und den ASC-Schlüsseln aus `~/.appstoreconnect/`.
`tools/asc_jwt.swift` druckt ein API-Token für Abfragen (z. B. Buildliste).
ASC-App **RadPendler**, ID `ASC_APP_ID`, Bundle/SKU `de.keese.radpendler`.
Apple erlaubt kein Anlegen von Apps per API — das muss der Nutzer im Browser tun.

Simulator mit Adressen füttern (zum Screenshotten ohne Tippen):

```bash
xcrun simctl spawn booted defaults write de.keese.radpendler origin -data <hex-json>
# JSON: {"name":…,"latitude":…,"longitude":…}
```

## Aufbau

- `Models/` — `Place` (mit `postalCode`/`locality`, `areaLine`, `withArea`) und `PlaceUse`
  (benutzte Adressen mit Zähler; `ranked`, `matching`, `recording` als reine Funktionen auf
  `[PlaceUse]`), `AppSettings` (+ `PlanSettings` als Wertkopie, `DeparturePreset`), `Trip`
  (`TripOption`, `Leg`, `TravelMode`, `BikeVariant`, `CarVariant`, `TransitProduct`).
- `Services/` — `CloudStore` (iCloud-Schlüssel-Wert-Abgleich der Einstellungen; hört auf
  `UserDefaults.didChangeNotification` statt auf zwanzig Setter, `placeHistory` wird
  zusammengeführt statt ersetzt), `WatchLink` (Plan an die Uhr), `Hafas` (VBB mgate + Parser), `BRouter` (+ `CompositeRouter`), `StreetRouter`
  (MapKit), `RoadData` (Overpass + `RouteAnalyzer` + `SegmentGrid`), `Rain` (Open-Meteo),
  `RadarOverlay` (DWD-WMS-Kacheln), `Waypoints`, `TripPlanner` (+ `BikeCandidate`,
  `BikeTransitComposer`), `Alarm`.
- `App/PlanModel.swift` — Zustand: `when` (departNow / departAt / arriveAt), Auswahl je Modus,
  `countdownOption`, `applyDefaultWhen`, `publishToWatch`.
- `Shared/` — in **beiden** Zielen: `Countdown` (Farbrampe und Text, damit Uhr und Telefon
  dieselbe Minute gleich färben) und `TripSnapshot` (der Plan, wie ihn die Uhr sieht:
  keine Koordinaten, keine Routen, Farben als Hex).
- `RadPendlerWatch/` — `WatchApp`, `WatchModel` (+ `PhoneLink`: WCSession-Empfang und
  Zwischenspeicher auf Platte), `WatchViews` (Countdown, Fahrt, Kategorien + Wege).
- `Views/` — `ContentView` (eine Seite **ohne ScrollView**, ab regulärer Breite zweispaltig: Kopfzeile, Karte, Boxenreihe,
  Fahrtzeile; alles außer der Karte hat feste Höhe, die Karte nimmt den Rest. `LastRunLine`
  in der Radarpille zeigt den Stand und ist der Knopf zum Neuberechnen), `ModeStrip`
  (+ `SelectedTripBar`), `HelpView` (Anleitung aus dem Burger-Menü),
  `RouteMapView` (MKMapView-Wrapper mit Radar, Schildern, Ampelpunkten, Long-Press),
  `TripDetailView` (Zeitstrahl), `SettingsView`, `Theme` (Design-Bausteine, `CountdownBox`,
  `TrafficLightIcon`, `AppMark`), `Style` (Farben, `LegChainView`, `Fmt`),
  `Mark` (die Geometrie des App-Zeichens in einem 100 × 100-Feld, y nach unten).
- App-Zeichen: Form und Farben stehen **nur** in `Views/Mark.swift`. Neu rendern mit
  `swiftc -O -parse-as-library tools/make_icon.swift RadPendler/Views/Mark.swift -o /tmp/mkicon`
  und `/tmp/mkicon RadPendler/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
  Die Entwürfe, aus denen gewählt wurde, liegen in `_reports/RadPendler_Logos*.html`.
- `design/Styleguide.html` + `.pdf` — Designkonzept; PDF wird mit Chrome headless erzeugt
  (Kopie für den Nutzer unter `_claude.code/_reports/RadPendler_Styleguide.pdf`).

## Datenquellen und ihre Fallen

- **VBB HAFAS** `https://fahrinfo.vbb.de/bin/mgate.exe`, aid `hafas-vbb-webapp`, ver 1.45, ext VBB.1 —
  inoffiziell. `v6.vbb.transport.rest` antwortete mit 503. Offizieller Zugang: Mail an api@vbb.de,
  erst Testserver, dann Produktivsystem.
- Fahrradmitnahme = Vermerk **`FK`** je Fahrt. Der Filter `{"type":"BC"…}` liefert nur zwischen
  Haltestellen Ergebnisse, mit Adressen kommt H890 → die App wählt die Bahnhöfe selbst (3 × 4
  bevorzugte S/RE-Paare plus 2 × 2 beliebige für die U-Bahn-Alternative).
- Ankunftssuche = `outFrwd: false`; mehrere `arrLocL` funktionieren **nicht**.
- **BRouter** (brouter.de): Profile trekking/fastbike/safety, `alternativeidx` 0–2.
- **Overpass**: eine bbox-Abfrage je Korridor (`convert` für schlanke Ausgabe, ~3,7 MB, ~7 s),
  30 Tage in `Caches/osm-roads` gecacht. Abfragen entlang der Polylinie dauerten 45 s — nicht tun.
  Bei Ausfall fehlen Ampeln und Hauptstraßen, die App zeigt das an.
- **Open-Meteo** `minutely_15` für Regen je Streckenpunkt, **DWD-WMS** `dwd:Niederschlagsradar`
  (−3 d … +2 h) für die Radarkacheln.

## Festlegungen des Nutzers (nicht ohne Rückfrage ändern)

- Die Hauptseite muss ohne Scrollen passen. Was dazukommt, kostet Kartenhöhe — Details
  gehören auf dem iPhone hinter den Pfeil in `TripDetailView`; auf dem iPad stehen sie
  in der linken Spalte (`TripNotes`, `TripFacts`, `TripTimeline` — dieselben Bausteine).
- Die Uhr plant nie selbst. MapKit-Routen, Overpass und die Radarkacheln gibt es auf
  watchOS nicht; sie zeigt, was das iPhone zuletzt geschickt hat, und sagt dazu, wie alt
  das ist. Was die Uhr wählt, gilt nur auf der Uhr — die Mitteilungen kommen weiter vom
  iPhone und folgen dessen Auswahl.
- Die **Vorlieben sind jetzt Einstellungen**, keine festen Regeln mehr: Reihenfolge der
  Verkehrsmittel, Reihenfolge der Rad- und Autorouten-Varianten, und ab welchem Regen das
  Rad in die Bahn gehört. Sein bisheriges Verhalten ist überall die Voreinstellung
  (`TravelMode.defaultOrder`, `BikeVariant.defaultOrder`, `CarVariant.defaultOrder`,
  `rainSwitchLevel = .light`) — Änderungen an der Logik müssen die Listen respektieren,
  nicht die alten festen Reihenfolgen.
- Radgeschwindigkeit ist die **rollende** Geschwindigkeit (29 km/h) plus 20 s je Ampelkreuzung;
  zusammen ergibt das seine gemessenen ~21 km/h.
- **S-Bahn und Regionalzug zuerst** (festes Radabteil), U-Bahn und Tram nur als markierte
  Alternative, nie empfohlen, solange es eine S/RE-Verbindung gibt.
- Rad + Bahn ist der Normalfall bei schlechtem Wetter; bei Trockenheit gewinnt das Rad.
- Umstiege zählen wie 10 min Fahrzeit (einstellbar), direkte Verbindungen gewinnen.
- Farben: Rad grün, Auto rot, Bus orange, alles auf Schienen blau (S hell, U dunkel, RE/Tram
  dazwischen), Fähre türkis, Rad + Bahn `#00ADA3`.
- **Keine Adressen im Programm** — die App startet leer. Adressen und Einstellungen liegen
  auf dem Gerät und in der **privaten iCloud des Nutzers** (Schlüssel-Wert-Speicher,
  Entitlement `com.apple.developer.ubiquity-kvstore-identifier`); sie gehen an keinen
  Server der App. Das gilt auch für den Verlauf der benutzten Adressen.
- `AppSettings.load()` ist zugleich das Neuladen nach einem iCloud-Zug: jede Eigenschaft
  behält ihren Wert, wenn der Schlüssel fehlt — ein halber Speicher darf nichts löschen.
- Adressen werden immer mit PLZ und Ort gezeigt; in der Kopfzeile klein hinter der Straße,
  sonst als zweite Zeile.
- Blockreihenfolge: Fahrrad, Rad + Bahn, Auto, Bahn & Bus.

## Offen / Ideen

- Mitteilungen laufen als `UNTimeIntervalNotificationTrigger` und werden bei jeder Planänderung
  neu gesetzt (`Alarm.schedule`, Schlüssel `ContentView.alarmKey`). Im Hintergrund plant die App
  nichts nach — fährt der Zug später ab, als beim letzten Öffnen bekannt war, warnt sie zu früh.
- Externe TestFlight-Tester bräuchten Beta-Prüfung und Datenschutz-URL.
- Radar visuell nur bei trockenem Wetter geprüft — Regenflächen nie auf der Karte gesehen.
- Kreuzungserkennung ist Heuristik (Brücken zählen als Querung, Tunnel nicht).
