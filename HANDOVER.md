# RadPendler — Übergabe (Stand 24.09.2026, 1.2 / nach Build 26)

Multimodaler Pendel-Planer für iPhone, iPad und Apple Watch: Büro ↔ Zuhause mit Fahrrad, Rad + Bahn, Auto und ÖPNV, inklusive Ampeln,
Regen und Countdown.
Das Projekt ist quelloffen (MIT); Adressen und Schlüssel gehören nicht hinein.

## Bauen, testen, ausliefern

```bash
./dev test      # generiert das .xcodeproj bei Bedarf, dann 139 Tests im Simulator
#               MOTIS_LIVE=1 schaltet zusätzlich den echten Transitous-Aufruf frei
#               (aus Xcode heraus; xcodebuild reicht die Variable nicht durch)
./dev open      # Xcode mit demselben DerivedData wie die Kommandozeile
./dev generate  # nur neu generieren, nach jeder neuen Quelldatei
```

Das `.xcodeproj` ist generiert und nicht committet: Änderungen im Projektnavigator
überlebt kein `generate`. Struktur gehört in `project.yml`.

Die Watch-App hängt als Abhängigkeit am iPhone-Ziel und wird nach `Watch/` kopiert;
`./dev build` baut sie mit. Einzeln: `-scheme RadPendlerWatch` mit einem
`platform=watchOS Simulator`-Ziel.

TestFlight (nur auf Ansage des Nutzers): Buildnummer in `project.yml` hochzählen →
`xcodegen generate` → `clean archive` → `-exportArchive` mit einer `ExportOptions.plist`
(method `app-store-connect`, destination `upload`) und den App-Store-Connect-Schlüsseln
aus `~/.appstoreconnect/`. `tools/asc_jwt.swift` druckt ein API-Token für Abfragen; es
liest `ASC_KEY_ID` und `ASC_ISSUER_ID` aus der Umgebung. Schlüssel und App-IDs stehen **nicht** in diesem Repository;
die Team-ID steht in `project.yml`, weil ohne sie niemand bauen kann — sie steckt
ohnehin in jedem signierten Binary.
Apple erlaubt kein Anlegen von Apps per API — das muss von Hand im Browser passieren.

### Beim Veröffentlichen (nicht vorher)

Drei Dinge, die zur *öffentlichen* Fassung gehören und deshalb bis dahin liegen bleiben —
die Seite im Netz muss beschreiben, was die App im Store tut, nicht was TestFlight kann:

1. **Datenschutzseite nachziehen.** `appstore/pages/radpendler-privacy/index.html` (10,3 kB,
   beschreibt die Fahrtaufzeichnung) nach `deepskyplan.github.io/radpendler-privacy`. Online
   steht Stand 24.09.2026 noch die alte Fassung (8,0 kB, ein „Standort", kein Wort zur
   Aufzeichnung) — richtig für 1.0, falsch für alles ab 1.1.
   Entscheidung des Nutzers: erst mit der Veröffentlichung der neuen Version.
2. **Datenschutz-Fragebogen** unter
   <https://appstoreconnect.apple.com/apps/6813997635/distribution/privacy> —
   über die API **nicht** lesbar oder änderbar, alle Endpunkte antworten 404.
   Einzutragen: Standort → Genauer Standort, Zweck App-Funktionalität, **nicht** mit der
   Identität verknüpft, **kein** Tracking. Sonst nichts: keine Tracking-SDKs, kein IDFA,
   keine Kennung in irgendeiner Anfrage.
   *Achtung, gilt schon für 1.0:* auch ohne Aufzeichnung gehen Start- und Zielkoordinaten
   an `brouter.de`, `overpass-api.de`, `fahrinfo.vbb.de`, `api.transitous.org`,
   `api.open-meteo.com` und `maps.dwd.de`. „Nein auf alles" ist deshalb auch für die
   Fassung falsch, die gerade in der Prüfung steht.
3. **CloudKit-Schema übernehmen**, falls die Linien bis dahin reisen:
   <https://icloud.developer.apple.com/dashboard/> → Schema → Deploy, Development → Production.

Simulator mit Adressen füttern (zum Screenshotten ohne Tippen):

```bash
xcrun simctl spawn booted defaults write <bundle-id> origin -data <hex-json>
# JSON: {"name":…,"latitude":…,"longitude":…}
```

## Aufbau

- `Models/` — `Ride` (eine gefahrene Fahrt: nur Gemessenes gespeichert, alles Ableitbare
  gerechnet; `RideTrack` mit Linie und Halten **getrennt** davon, damit eine Liste von
  dreihundert Fahrten nicht dreihundert Linien in den Speicher zieht; `Ride.grouped`
  macht Jahre und Monate daraus), `Place` (mit `postalCode`/`locality`, `areaLine`, `withArea`) und `PlaceUse`
  (benutzte Adressen mit Zähler; `ranked`, `matching`, `recording` als reine Funktionen auf
  `[PlaceUse]`), `AppSettings` (+ `PlanSettings` als Wertkopie, `DeparturePreset`), `Trip`
  (`TripOption`, `Leg`, `TravelMode`, `BikeVariant`, `CarVariant`, `TransitProduct`).
- `Services/` — `RideMeter` (die ganze Messlogik als **reine Struktur** ohne
  `CLLocationManager`: Strecke, Halte, Ampelzuordnung, Linie — ein Test füttert sie mit
  erfundenen Fixes, siehe `RideTests`), `RideTracker` (der Manager drumherum; schaltet
  `allowsBackgroundLocationUpdates` **nur** zwischen Start und Ende einer Fahrt ein und
  danach wieder aus, schickt die Zahlen im Sekundentakt an die Uhr und sichert alle 30 s
  einen Zwischenstand), `RideStore` (Zusammenfassungen im
  Schlüssel-Wert-Speicher und damit in iCloud, Linien je eine Datei und damit nur lokal),
  `TurnGuide` (Abbiegehinweise **aus der gezeichneten Linie**, rein und testbar:
  kein Router sagt sie an, und keiner muss es),
  `Location` (ein einzelner Fix auf Tippen, danach nichts mehr;
  `place(from:at:)` ist absichtlich `nonisolated`, damit es ohne Gerät testbar ist),
  `Motis` (Transitous/MOTIS 2: `MotisClient` + `MotisParser`, inkl.
  Polylinien-Dekoder), `CloudStore` (iCloud-Schlüssel-Wert-Abgleich der Einstellungen **und** der
  Fahrt-Kennzahlen; hört auf `UserDefaults.didChangeNotification` statt auf zwanzig
  Setter, `placeHistory` und `rides` werden zusammengeführt statt ersetzt), `WatchLink` (Plan an die Uhr), `Hafas` (VBB mgate + Parser), `BRouter` (+ `CompositeRouter`), `StreetRouter`
  (MapKit), `RoadData` (Overpass + `RouteAnalyzer` + `SegmentGrid`), `Rain` (Open-Meteo),
  `RadarOverlay` (DWD-WMS-Kacheln), `Waypoints`, `TripPlanner` (+ `BikeCandidate`,
  `BikeTransitComposer`), `Alarm`.
- `App/PlanModel.swift` — Zustand: `when` (departNow / departAt / arriveAt), Auswahl je Modus,
  `countdownOption`, `applyDefaultWhen`, `publishToWatch`.
- `Shared/` — in **beiden** Zielen: `Countdown` (Farbrampe und Text, damit Uhr und Telefon
  dieselbe Minute gleich färben), `TripSnapshot` (der Plan, wie ihn die Uhr sieht:
  keine Koordinaten, keine Routen, Farben als Hex) und `RideLive` (die laufende Fahrt,
  ebenso klein: nur Zahlen, klein genug für eine Nachricht je Sekunde).
- `RadPendlerWatch/` — `WatchApp`, `WatchModel` (+ `PhoneLink`: WCSession-Empfang und
  Zwischenspeicher auf Platte), `WatchViews` (Countdown, Fahrt, Kategorien + Wege).
- `Views/` — `ContentView` (eine Seite **ohne ScrollView**, ab regulärer Breite zweispaltig: Kopfzeile, Karte, Boxenreihe,
  Fahrtzeile; alles außer der Karte hat feste Höhe, die Karte nimmt den Rest. `LastRunLine`
  in der Radarpille zeigt den Stand und ist der Knopf zum Neuberechnen), `ModeStrip`
  (+ `SelectedTripBar`), `HelpView` (Anleitung aus dem Burger-Menü),
  `RouteMapView` (MKMapView-Wrapper mit Radar, Schildern, Ampelpunkten, Long-Press),
  `TripDetailView` (Zeitstrahl), `SettingsView`, `Theme` (Design-Bausteine, `CountdownBox`,
  `TrafficLightIcon`, `AppMark`), `Style` (Farben, `LegChainView`, `Fmt`),
  `Mark` (die Geometrie des App-Zeichens in einem 100 × 100-Feld, y nach unten),
  `RideTrackingView` (+ `RideSummarySheet`) und `RidesView` (Liste, Detail, `RideFacts`,
  `RideMapCard`), `RideStyle` (`RideColors` — die fünf Tempostufen der gefahrenen Linie,
  `Orientation` (`AppDelegate` — nur damit UIKit jemanden hat, den es nach der
  erlaubten Lage fragen kann),
  und `SpeedLegend`, die Skala dazu).
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
- **Transitous / MOTIS 2** `https://api.transitous.org/api/v1/plan` — bundesweit und darüber
  hinaus, intermodal (`preTransitModes`/`postTransitModes=BIKE` liefert Rad–Bahn–Rad in einer
  Antwort). Bedingungen: quelloffen, nicht kommerziell, `User-Agent` mit Name, Version und
  Kontakt bei **jeder** Anfrage, sichtbarer Link auf <https://transitous.org/sources/>. Alles
  drei ist umgesetzt — `MotisClient.userAgent`, Menü und Einstellungen. Bei Zweifeln über die
  Last: deren Matrix-Kanal. `routeType` (GTFS-erweitert) sagt mehr als `mode`, das eine S-Bahn
  „METRO" nennt. `bikesAllowed: false` heißt **nicht** nein, sondern „nicht gesetzt".

## Festlegungen des Nutzers (nicht ohne Rückfrage ändern)

- Die Hauptseite muss ohne Scrollen passen. Was dazukommt, kostet Kartenhöhe — Details
  gehören auf dem iPhone hinter den Pfeil in `TripDetailView`; auf dem iPad stehen sie
  in der linken Spalte (`TripNotes`, `TripFacts`, `TripTimeline` — dieselben Bausteine).
- Fahrradmitnahme ist dreiwertig (`BikeCarriage`): `yes`, `no`, `unknown`. Der Fahrplan
  sagt nur ja oder nichts; das Nein kommt immer vom Nutzer, über die Linienliste in den
  Einstellungen. `unknown` wird **gezeigt und gewarnt**, nicht versteckt — sonst gäbe es
  mit Datenquellen ohne `FK`-Vermerk gar keine Rad + Bahn-Vorschläge mehr.
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
  dazwischen), Fähre türkis, Rad + Bahn `#00A8BA`.
- **Das Repo ist öffentlich** (MIT). Keine Adresse, keine echte Koordinate des Nutzers und
  kein Schlüssel darf hineingeraten — auch nicht in Testdaten, Changelog oder Übergabe.
  Die Fixtures tragen neutrale Adressen und eine versetzte Geometrie.
- **Ortung: ein Fix auf Tippen, laufend nur während einer Aufzeichnung** (Nutzer,
  23.09.2026 — vorher galt „nie im Hintergrund"). `LocationService` ist unverändert ein
  einzelner `requestLocation()` für „Mein Standort". Die Aufzeichnung läuft in
  `RideTracker` und **nur** dort: `startUpdatingLocation` und
  `allowsBackgroundLocationUpdates` gehen in `begin` an und in `stop` wieder aus,
  `UIBackgroundModes: location` steht deshalb in `RadPendlerInfo.plist`. Wer daran etwas
  ändert, ändert auch den App-Datenschutz-Fragebogen und die Datenschutzerklärung —
  **beide sind für diesen Stand noch nicht nachgezogen.**
- **Alles, was die Fahrt führt, friert beim Start der Fahrt ein.** `RideTracker.start`
  bekommt die Kreuzungen *und die Route* der geplanten Fahrt mit. Eine Neuplanung
  unterwegs darf weder nachträglich entscheiden, ob ein Halt vor drei Kilometern eine
  Ampel war, noch den Abbiegepfeil auf eine Straße zeigen lassen, auf der man nicht ist —
  und ein Plan, der still leer zurückkommt, darf die Führung nicht mitnehmen. Genau das
  ist am 23.09. im Simulator passiert, bevor die Route mit einfror.
- **Ein Halt ab `signalStopSeconds` (30 s) ist eine Ampel**, auch ohne Kartendaten, und
  wird als `LearnedSignal` behalten. Gelernte Ampeln wirken in zwei Richtungen zurück:
  in `RideMeter.signals` der nächsten Fahrt und über `TripPlanner.withLearned` in
  `RoadData.signals`, also in die Ampelzahl und damit in die Radzeit jeder Route.
  `RouteAnalyzer` fasst Signalknoten innerhalb von 60 m zusammen — eine gelernte Ampel
  auf einer gemappten zählt deshalb nicht doppelt.
- **Der Pfeil der Fahrtansicht dreht sich um `Kurs − Blickrichtung der Karte`.** Beim
  Folgen dreht sich die Karte selbst in den Kurs; wer den Pfeil zusätzlich um den Kurs
  dreht, zeigt doppelt daneben. Erster Befund der ersten Testfahrt.
- **Das Regenradar darf nur noch anhängen, was fehlt.** `Coordinator.radarPlan` ist die
  ganze Buchhaltung, und sie muss zur Ruhe kommen: zweimal hintereinander mit gleichem
  Stand gefragt, kommen zwei leere Mengen zurück. Bis 1.2 hängte die Schleife nach dem
  Abräumen **alle** Bilder wieder an — hunderte Kachelanfragen je Sekunde. Das war die
  Ursache für Ruckeln *und* Stromverbrauch, und es sah an keiner Stelle falsch aus.
  `RideTests.testTheRadarSettlesInsteadOfChurning` hält es fest.
- **Nichts Teures je Bild, alles Teure je Ereignis.** Der Abbiegehinweis wird in
  `RideTracker.accept` berechnet und gespeichert, nicht in der View; die Längentabelle der
  Route entsteht einmal beim Einfrieren; die Kamera bewegt sich nur, wenn sich etwas um
  mehr als 3 m oder 4° geändert hat; die Fahrtansicht lässt nur Uhr und Tempo im
  Sekundentakt laufen, nicht die Karte. Wer hier etwas hinzufügt, prüfe zuerst, wie oft
  es läuft.
- **Wegtypen kommen aus BRouters `messages`**, nicht aus einer zusätzlichen
  Overpass-Abfrage: je Segment Länge und `WayTags`. Gelesen wird über die **Spaltennamen**
  der Kopfzeile, weil BRouter deren Reihenfolge schon geändert hat. `RoadClass`,
  `RoadMix` und `RoadPoint` stehen in `Models/RoadMix.swift`; Apples Linien tragen keine
  Tags, dort bleibt die Mischung leer — und eine leere Mischung heißt „nicht bekannt",
  nicht „alles Hauptstraße".
- **`OrientationLock.apply()` fordert in `auto` bewusst *keine* Geometrieänderung an.**
  Ein `requestGeometryUpdate` mit „alle Richtungen" nagelt die App auf die Lage fest, in
  der sie gerade ist — das Gegenteil von automatisch.
- **Von den Fahrten reisen nur die Kennzahlen, nie die Linien.** Beides zusammen passt
  nicht: der Schlüssel-Wert-Speicher fasst 1 MB für die ganze App, eine Linie ist rund
  80 kB. Die Zusammenfassungen liegen deshalb unter `CloudStore.ridesKey` (komprimiert,
  gedeckelt auf `RideStore.maxRides`), die Linien als Dateien unter `Rides/tracks/`.
  `rides` ist wie `placeHistory` ein **zusammengeführter** Schlüssel — deshalb wirkt ein
  Löschen nur auf dem Gerät, auf dem gelöscht wurde, und die App sagt das auch.
  `CloudStore.settingsKeys` ist die Liste, gegen die
  `testEverySettingTheAppSavesAlsoTravelsThroughICloud` prüft; `keys` ist sie plus `rides`.
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

- **Die Hänger sind gefunden und behoben** (24.09.2026, Branch
  `fix/haenger-cloudstore`). Ein `TimelineView` in einer `ToolbarItem` legt unter
  iOS 26 bei jedem Takt die Navigationsleiste neu aus, und dieses Auslegen macht
  den Ansichtsgraphen erneut schmutzig — die App lief dauerhaft mit voller
  Bildrate durch. Leerlauf-CPU im Simulator, Release: 70–85 % vorher, 0 %
  nachher. Der Fehler steckte in 1.0, 1.1 und 1.2 gleichermaßen; Build 23 war nie
  heil, und keine Neuinstallation konnte je helfen. Das Protokoll — auch die
  Messungen, die sich als falsch erwiesen haben — steht in
  `_claude.code/RadPendler-Haenger.md`.

  **Die Lehre daraus, bevor wieder jemand rät:** zuerst die CPU messen. Drei
  Runden Hypothesen aus dem Quelltext sind an den Daten gestorben; ein `ps`
  auf den Simulator-Prozess hätte es am ersten Tag gezeigt.

  ```bash
  PID=$(pgrep -f "Devices/$SIM.*RadPendler.app/RadPendler")   # nie ohne $SIM filtern
  sample $PID 5 -file /tmp/rp.txt                             # „Version:" im Kopf prüfen
  ```

- **Die Linien reisen** (seit Build 29). `TrackCloud` hängt an `RideStore.add` /
  `delete` / `track(for:)`; Container `iCloud.org.afjk.radpendler` steht im Portal und
  ist dem App-Identifier zugewiesen, die Berechtigung in `project.yml` ist an. Offen:
  das Schema im CloudKit-Dashboard einmal von Development nach Production übernehmen —
  erst dann reisen die Linien auch für die veröffentlichte App.
- **Signieren auf diesem Mac, seit es den Container gibt.** Die Xcode-Team-Profile hier
  sind älter als der Container und kennen ihn nicht. Automatisches Signieren nimmt
  **nur** Xcode-eigene Profile und kann sie ohne angemeldetes Konto nicht auffrischen —
  `-allowProvisioningUpdates` scheitert mit „Authentication failed", der Schlüssel
  `PAGC3W2GBL` darf lesen, aber keine Profile anlegen. **Einmal aus Xcode.app bauen**
  zieht sie nach, danach geht alles wieder von der Kommandozeile.
  Build 29 wurde ersatzweise von Hand signiert: zwei über die API erzeugte Profile
  (`RadPendler AppStore CK`, `RadPendlerWatch AppStore CK`), `CODE_SIGN_STYLE: Manual`
  nur für den einen Lauf, danach wieder `Automatic`. Die beiden Profile dürfen weg,
  sobald Xcode die eigenen erneuert hat.
- **`xcodebuild` auf diesem Mac hat kein Entwicklerkonto** („No Accounts: Add a new
  account in Accounts settings"). Automatisches Signieren aus der Kommandozeile geht
  deshalb nur mit einem API-Schlüssel, der im Portal Rechte hat; `PAGC3W2GBL` hat sie
  für App Store Connect (Upload), aber nicht fürs Provisioning. Profile kommen bis auf
  Weiteres aus Xcode.app.
- `UIBackgroundModes` gibt es **nicht** als `INFOPLIST_KEY_*`. Deshalb die Teil-Datei
  `RadPendlerInfo.plist` neben `GENERATE_INFOPLIST_FILE: YES`; Xcode mischt beides. Sie
  enthält genau diesen einen Schlüssel und darf nicht in einen Quell- oder
  Ressourcenpfad wandern.

- Mitteilungen laufen als `UNTimeIntervalNotificationTrigger` und werden bei jeder Planänderung
  neu gesetzt (`Alarm.schedule`, Schlüssel `ContentView.alarmKey`). Im Hintergrund plant die App
  nichts nach — fährt der Zug später ab, als beim letzten Öffnen bekannt war, warnt sie zu früh.
- Externe TestFlight-Tester bräuchten Beta-Prüfung und Datenschutz-URL.
- Radar visuell nur bei trockenem Wetter geprüft — Regenflächen nie auf der Karte gesehen.
- Kreuzungserkennung ist Heuristik (Brücken zählen als Querung, Tunnel nicht).
