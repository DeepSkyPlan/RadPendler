# RadPendler — Übergabe (Stand 20.09.2026, 0.6.1 / Build 12)

Multimodaler Pendel-Planer für iOS: Musterstraße 1 (Büro) ↔ Beispielweg 2 (Musterort)
mit Fahrrad, Rad + Bahn, Auto und ÖPNV, inklusive Ampeln, Regen und Countdown.
Verzeichnis `~/_claude.code/Pendel`, git mit Remote `DeepSkyPlan/RadPendler` (privat).

## Bauen, testen, ausliefern

```bash
xcodegen generate                                # .xcodeproj ist nicht committet
xcodebuild -project Pendel.xcodeproj -scheme Pendel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test   # 41 Tests
```

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

- `Models/` — `Place`, `AppSettings` (+ `PlanSettings` als Wertkopie, `DeparturePreset`), `Trip`
  (`TripOption`, `Leg`, `TravelMode`, `BikeVariant`, `TransitProduct`).
- `Services/` — `Hafas` (VBB mgate + Parser), `BRouter` (+ `CompositeRouter`), `StreetRouter`
  (MapKit), `RoadData` (Overpass + `RouteAnalyzer` + `SegmentGrid`), `Rain` (Open-Meteo),
  `RadarOverlay` (DWD-WMS-Kacheln), `Waypoints`, `TripPlanner` (+ `BikeCandidate`,
  `BikeTransitComposer`), `Alarm`.
- `App/PlanModel.swift` — Zustand: `when` (departNow / departAt / arriveAt), Auswahl je Modus,
  `countdownOption`, `applyDefaultWhen`.
- `Views/` — `ContentView` (eine Seite: Kopfzeile, Karte, Boxenreihe, Fahrtzeile), `ModeStrip`
  (+ `SelectedTripBar`), `HelpView` (Anleitung aus dem Burger-Menü),
  `RouteMapView` (MKMapView-Wrapper mit Radar, Schildern, Ampelpunkten, Long-Press),
  `TripDetailView` (Zeitstrahl), `SettingsView`, `Theme` (Design-Bausteine, `CountdownBox`,
  `TrafficLightIcon`), `Style` (Farben, `LegChainView`, `Fmt`).
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

- Radgeschwindigkeit ist die **rollende** Geschwindigkeit (29 km/h) plus 20 s je Ampelkreuzung;
  zusammen ergibt das seine gemessenen ~21 km/h.
- **S-Bahn und Regionalzug zuerst** (festes Radabteil), U-Bahn und Tram nur als markierte
  Alternative, nie empfohlen, solange es eine S/RE-Verbindung gibt.
- Rad + Bahn ist der Normalfall bei schlechtem Wetter; bei Trockenheit gewinnt das Rad.
- Umstiege zählen wie 10 min Fahrzeit (einstellbar), direkte Verbindungen gewinnen.
- Farben: Rad grün, Auto rot, Bus orange, alles auf Schienen blau (S hell, U dunkel, RE/Tram
  dazwischen), Fähre türkis, Rad + Bahn `#00ADA3`.
- **Keine Adressen im Programm** — die App startet leer, Adressen bleiben auf dem Gerät.
- Blockreihenfolge: Fahrrad, Rad + Bahn, Auto, Bahn & Bus.

## Offen / Ideen

- Mitteilungen laufen als `UNTimeIntervalNotificationTrigger` und werden bei jeder Planänderung
  neu gesetzt (`Alarm.schedule`, Schlüssel `ContentView.alarmKey`). Im Hintergrund plant die App
  nichts nach — fährt der Zug später ab, als beim letzten Öffnen bekannt war, warnt sie zu früh.
- Externe TestFlight-Tester bräuchten Beta-Prüfung und Datenschutz-URL.
- Radar visuell nur bei trockenem Wetter geprüft — Regenflächen nie auf der Karte gesehen.
- Kreuzungserkennung ist Heuristik (Brücken zählen als Querung, Tunnel nicht).
