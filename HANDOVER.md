# RadPendler — Übergabe (Stand 24.09.2026, abends · 1.3 / Build 35)

Multimodaler Pendel-Planer für iPhone, iPad und Apple Watch: Büro ↔ Zuhause mit Fahrrad, Rad + Bahn, Auto und ÖPNV, inklusive Ampeln,
Regen und Countdown.
Das Projekt ist quelloffen (MIT); Adressen und Schlüssel gehören nicht hinein.

## Bauen, testen, ausliefern

```bash
./dev test      # generiert das .xcodeproj bei Bedarf, dann 154 Tests im Simulator
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
2. ~~Datenschutz-Fragebogen~~ — **erledigt am 24.09.2026** (Angabe des Nutzers; über die
   API nicht nachprüfbar, alle Endpunkte antworten 404). Stand jetzt: Standort → Genauer
   Standort, Zweck App-Funktionalität, nicht mit der Identität verknüpft, kein Tracking.
   Nachsehen unter
   <https://appstoreconnect.apple.com/apps/6813997635/distribution/privacy>.
   Der Grund, falls er je wieder infrage steht: auch ohne Aufzeichnung gehen Start- und
   Zielkoordinaten an `brouter.de`, `overpass-api.de`, `fahrinfo.vbb.de`,
   `api.transitous.org`, `api.open-meteo.com` und `maps.dwd.de`. Tracking-SDKs, IDFA oder
   eine Kennung in einer Anfrage gibt es dagegen nicht — geprüft im Quelltext.
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
  `OffRoute` (wo die geplante Linie liegt, wenn man nicht auf ihr ist — reine
  Geometrie mit Hysterese, plus `shouldReplan`: Entfernung **oder** Zeit),
  `BackgroundReplan` (`BGAppRefreshTask`; stellt die Warnungen auf den aktuellen
  Fahrplan nach, während die App zu ist — dieselbe Frage, die auf dem Bildschirm
  stand, liegt als `countdownQuestion` in den UserDefaults),
  `TrackCloud` (die **Linien** der Fahrten über CloudKit; ohne Container ein
  stiller Nichtstuer, und ein abgewiesener Upload steht in der Fahrtenliste),
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

## Zweisprachig: Deutsch und Englisch

Umgeschaltet wird im Burger-Menü (Fähnchen 🇩🇪 / 🇬🇧 / „A" für „wie das Telefon"), und die
Umstellung wirkt **sofort**, ohne Neustart.

Das geht nicht über die Sprachwahl des Systems: die steht fest, wenn der Prozess startet,
und vier Wege, sie von innen umzustellen, sind nachgewiesen gescheitert — die Klasse von
`Bundle.main` tauschen (greift für eigene Abfragen, **nicht** für `Text(…)`), `\.locale` in
der Umgebung setzen (nur Formatierung), `AppleLanguages` schreiben und neu starten, und
`CFBundleLocalizations` nachtragen. Der Weg, der funktioniert, fragt die Systemsprache gar
nicht erst:

- `Shared/Language.swift` — `AppLanguage` (system/de/en) und `L(…)`. `L` liest unmittelbar
  aus `<sprache>.lproj` im Paket; `Text(String)` schlägt danach nichts mehr nach, also
  bleibt stehen, was `L` liefert. Fehlt eine Übersetzung, kommt der deutsche Schlüssel.
- Die Wurzelansicht trägt die Sprache als Kennung (`.id(settings.language)`) — deshalb
  wirkt ein Wechsel sofort: SwiftUI baut den Baum neu und schlägt jeden Text neu nach.
- **Zahlen und Uhrzeiten folgen mit**: `Fmt` formatiert über `AppLanguage.locale`, sonst
  stünde „1,5 km" in der englischen Fassung.
- Die Uhr hat keine eigene Wahl: die Sprache reist im `TripSnapshot` mit (`language`), und
  `WatchModel` stellt sie beim Empfang ein. Der Katalog liegt in beiden Zielen.

Ein neuer Text braucht zwei Handgriffe — `L("…")` schreiben und die englische Fassung in
`tools/i18n/de_en.py` eintragen, dann `python3 tools/i18n/sync.py`. Das Verfahren steht in
`tools/i18n/README.md`; geprüft wird es von `RadPendlerTests/LanguageTests.swift`.

**Nicht übersetzt** werden die Vergleichsmuster fremder Dienste (die
Fahrradmitnahme-Texte der VBB-Auskunft!), der User-Agent, JSON-Schlüssel und alles, was in
`UserDefaults` landet.

## Datenquellen und ihre Fallen

- **VBB HAFAS** `https://fahrinfo.vbb.de/bin/mgate.exe`, aid `hafas-vbb-webapp`, ver 1.45, ext VBB.1 —
  inoffiziell. `v6.vbb.transport.rest` antwortete mit 503. Offizieller Zugang: Mail an api@vbb.de,
  erst Testserver, dann Produktivsystem.
- Fahrradmitnahme = Vermerk **`FK`** je Fahrt. Der Filter `{"type":"BC"…}` liefert nur zwischen
  Haltestellen Ergebnisse, mit Adressen kommt H890 → die App wählt die Bahnhöfe selbst (3 × 4
  bevorzugte S/RE-Paare plus 2 × 2 beliebige für die U-Bahn-Alternative).
- Ankunftssuche = `outFrwd: false`; mehrere `arrLocL` funktionieren **nicht**.
- **BRouter** (brouter.de): Profile trekking/fastbike/safety/shortest/fastbike-lowtraffic.
  **Höchstens drei Anfragen gleichzeitig** — auf acht auf einmal antwortet der öffentliche
  Server mit `403 Please, retry later!`, und zwar dauerhaft für diese IP (nachgemessen,
  auch einzeln nach zwanzig Minuten Pause). Gefragt wird nur, was die eingestellten Rollen
  brauchen: voreingestellt vier Anfragen statt neun. Antwortet er gar nicht, steht das
  unter der Route.
- **Overpass**: **entlang der Route**, nicht im umschließenden Kasten. Gemessen an 20 km
  quer durch Berlin, beide Abfragen gegen overpass-api.de:

  | | Kasten | Schlauch (`around:300`) |
  |---|---|---|
  | Antwort | 3 623 902 B | **287 349 B** |
  | Elemente | 18 238 | **1 410** |

  Eine ältere Fassung dieser Übergabe behauptete das Gegenteil („Abfragen entlang der
  Polylinie dauerten 45 s — nicht tun"). Das stimmt nicht; der Unterschied war
  vermutlich, dass damals jeder Routenpunkt einzeln in `around` stand statt eines auf
  150 m ausgedünnten Schlauchs. 30 Tage in `Caches/osm-roads` gecacht, mit
  Deckungsprüfung (`Corridor.covers`) — ein alter, schmalerer Schlauch darf nicht
  stillschweigend Ampeln verschlucken. Scheitert die Abfrage (`504` kommt unter Last
  vor), läuft ein geduldigerer zweiter Versuch im Hintergrund und füllt den Cache.
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
- **Die App misst sich selbst nach.** `AppSettings.calibrate(from:)` läuft nach jeder
  beendeten Fahrt und schreibt aus dem Median der letzten acht Radfahrten (ab drei)
  `bikeSpeedKmh` und, aus den gelernten Ampeln, `signalWaitSeconds`. Daneben steht
  `measuredOverallKmh` — der Tür-zu-Tür-Schnitt. **Gibt es ihn, ist er die angezeigte
  Radfahrzeit** (`PlanSettings.realistic`), in beide Richtungen: auch wenn er schneller
  ist als die Rechnung. Die Rechnung bleibt trotzdem nötig — sie vergibt die **Rollen**
  (`BikeCandidate.computedTime` in `pick` und `balancedScore`), denn nur sie kennt den
  Unterschied zwischen zwei und dreißig Ampeln. Wer hier `time` statt `computedTime`
  einsetzt, macht „schnellst" zur Zwillingsschwester von „kürzest".
- Radgeschwindigkeit ist die **rollende** Geschwindigkeit (29 km/h) plus die Wartezeit je
  Ampelkreuzung plus 5 s je Höhenmeter; zusammen ergibt das seine gemessenen ~21 km/h.
  Die Wartezeit sind 20 s je Kreuzung, die nur die Karte kennt — und an jeder Kreuzung,
  an der eigene Fahrten schon gemessen haben, das Gemessene (`PlanSettings.signalWait`,
  `LearnedSignal.expectedWait`). Wer hier etwas ändert, ändert die angezeigte Fahrzeit
  jeder Radroute: die Detailseite schreibt die Ampelzeit deshalb neben die Ampelzahl.
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
- **Im Fahrtmodus bleibt der Bildschirm an, bis die Fahrt beendet ist** — ohne Schalter
  (Nutzer, 24.09.2026). Es gab einen; ein Blick auf die Karte an der Kreuzung nützt nichts,
  wenn man vorher entsperren muss. **`isIdleTimerDisabled` einmal zu setzen reicht nicht:**
  das Flag gilt nur, solange die App vorn ist, und auf einer Fahrt kommt sie dauernd aus
  dem Hintergrund zurück. Es wird bei jeder Rückkehr und jeder Ortung neu behauptet.
- **Alles, was die Fahrt führt, friert beim Start der Fahrt ein** — mit **einer** Ausnahme: `RideTracker.start`
  bekommt die Kreuzungen *und die Route* der geplanten Fahrt mit. Eine Neuplanung
  unterwegs darf weder nachträglich entscheiden, ob ein Halt vor drei Kilometern eine
  Ampel war, noch den Abbiegepfeil auf eine Straße zeigen lassen, auf der man nicht ist —
  und ein Plan, der still leer zurückkommt, darf die Führung nicht mitnehmen. Genau das
  ist am 23.09. im Simulator passiert, bevor die Route mit einfror.
  Die Ausnahme ist die **Neuplanung beim Verlassen der Route** (einstellbar, voreingestellt
  ab 200 m und fünfzehn Sekunden am Stück daneben, oder nach einer eingestellten Zahl
  Minuten — was zuerst eintritt). Sie ändert nur den Weg nach vorn; gemessen bleibt, was
  gemessen wurde.
- **Eine Zeile der BRouter-Tabelle ist eine Strecke, kein Punkt.** Bis zu zwei Kilometer
  lang. `BRouterClient.roads` legt sie deshalb entlang der Linie aus und setzt alle
  `RoadPoint.spacing` (40 m) einen Stützpunkt. Vorher lag ein Stützpunkt je Zeile da, und
  38,5 % der Meter der Testroute waren weiter als `RoadPoint.matchRadius` von jedem
  entfernt — die Aufzeichnung schrieb sie als „sonstiges" gut, obwohl die Straße bekannt
  war. Das war der Grund für die 30 % „sonstiges" der Testfahrt vom 25.09.
- **Höhen kommen aus dem Empfänger, nicht aus dem Router**: `RidePoint.h`, nur wenn
  `verticalAccuracy` ≤ 20 m. `ElevationProfile` glättet über neun Punkte **und** zählt
  Anstieg erst ab `ascentThreshold` (5 m) — Glätten allein macht aus ±8 m Rauschen auf
  einer Ebene ein dreistelliges Höhenmeterkonto.
- **Was geplant war, steht in der Fahrt**: `Ride.plannedMeters`, `plannedSignals`,
  `plannedSeconds` und `RideTrack.planned` (die ausgedünnte Linie). Alles optional, alles
  aus der Zeit der Planung — die Planung von morgen ist eine andere.
- **Ein Halt ab `signalStopSeconds` (30 s) ist eine Ampel**, auch ohne Kartendaten, und
  wird als `LearnedSignal` behalten. Gelernte Ampeln wirken in zwei Richtungen zurück:
  in `RideMeter.signals` der nächsten Fahrt und über `TripPlanner.withLearned` in
  `RoadData.learned`, also in die Ampelzahl **und** in die Wartezeit jeder Route.
  `RouteAnalyzer` fasst Signalknoten innerhalb von 60 m zusammen — eine gelernte Ampel
  auf einer gemappten zählt deshalb nicht doppelt, und von beiden gewinnt die gemessene.
- **Jede Aufzeichnung zählt auch die Vorbeifahrten ohne Halt** (`AppSettings.learn`
  bekommt Linie und Kreuzungen, nicht nur die Halte). Ohne sie wäre der Mittelwert einer
  gelernten Ampel der Mittelwert der Male, an denen man gewartet hat — eine Ampel, die
  jede zweite Fahrt grün ist, kostete das Doppelte. `LearnedSignal.prior` (3 Vorbeifahrten
  mit dem eingestellten Mittelwert) hält die erste Beobachtung davon ab, alles zu
  entscheiden. Einträge aus der Zeit davor haben `passes == nil`; für sie war jede
  Vorbeifahrt ein Halt, und sie werden mit jeder neuen Fahrt ehrlicher.
- **Der erste und der letzte Stillstand einer Fahrt sind keine Ampel.** Das ist die eigene
  Haustür: man steht in der Einfahrt, oder man ist angekommen und tippt eine halbe Minute
  später auf „Fahrt beenden". Über die 30-Sekunden-Regel wurde daraus eine gelernte Ampel,
  die jede spätere Planung verlängerte. Kennt die Karte am Ende der Fahrt dort eine Ampel,
  bleibt es eine (`RideMeter.close(since:until:ending:)`).
- **Die Karte zeigt im Fahrtmodus `tracker.plannedRoute`, nicht die Linie der
  Möglichkeit** (`RouteMapView.guidedLine`, gezeichnet von `updateGuideLines`). Eine
  Neuplanung unterwegs ändert keine `TripOption` — vorher zeigte die Karte deshalb weiter
  die alte Linie, während Pfeil und Abweichung schon gegen die neue rechneten. Die
  ursprüngliche Linie liegt ab der ersten Neuplanung dünn und grau daneben
  (`plannedLine`), und solange `guidedLine` gesetzt ist, zeichnet `drawRoutes` weder
  Streckenlinien noch Planampeln — sonst läge alles doppelt übereinander.
- **Abbiegepfeil grün, Abweichung rot, und der Pfeil erst 250 m vorher**
  (`RideTrackingView.announceMeters`). Rot ist auf diesem Bildschirm reserviert für „du
  bist falsch"; ein Pfeil, der die halbe Strecke lang dasteht, wird zu Tapete und nimmt
  der Karte die obersten hundert Punkte.
- **Die Fahrtansicht zeigt, was noch kommt**: `RideTracker.progress` (Reststrecke,
  Ampeln davor/danach) wird je Ortung aus `routeIndex`, `routeLengths` und
  `signalStations` gerechnet, `RideRemaining` macht daraus Zeit und Ankunft — mit
  demselben Modell wie die Planung, einschließlich der Gegenprobe gegen den gemessenen
  Schnitt. Dieselbe Zahl steht während einer Fahrt in der Werkzeugleiste statt des
  Countdowns (`RideArrivalPill`).
- **Die Ausrichtung im Fahrtmodus ist `rideOrientation`, nicht `orientation`.** Sie wird
  beim Start der Fahrt angewendet und bleibt für die nächste stehen; am Ende geht
  `orientation` auf `.auto`. Vorher blieb die ganze App hochkant, nur weil sie es am
  Lenker einmal sein sollte.
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
- **Die Kennzahlen reisen über den Schlüssel-Wert-Speicher, die Linien über CloudKit.**
  Beides über denselben Weg ginge nicht: der Schlüssel-Wert-Speicher fasst 1 MB für die
  ganze App, eine Linie ist rund 80 kB. Die Zusammenfassungen liegen deshalb unter
  `CloudStore.ridesKey` (komprimiert,
  gedeckelt auf `RideStore.maxRides`), die Linien als Dateien unter `Rides/tracks/` **und**
  als `CKAsset` in der privaten CloudKit-Datenbank (`TrackCloud`, Container
  `iCloud.org.afjk.radpendler`).
  `rides` ist wie `placeHistory` ein **zusammengeführter** Schlüssel — deshalb wirkt ein
  Löschen nur auf dem Gerät, auf dem gelöscht wurde, und die App sagt das auch.
  `CloudStore.settingsKeys` ist die Liste, gegen die
  `testEverySettingTheAppSavesAlsoTravelsThroughICloud` prüft; `keys` ist sie plus `rides`.
- **Wie viele Möglichkeiten je Verkehrsmittel, entscheidet der Nutzer** (1–3,
  voreingestellt 3). Die Zahl begrenzt nicht nur die Anzeige, sondern das **Rechnen**:
  geholt wird nur, was die obersten Rollen der eigenen Reihenfolge brauchen. Gewinnt eine
  Linie mehrere Rollen, steht sie einmal da und trägt alle ihre Namen — dann sind es eben
  weniger Kästen. Eine namenlose „Alternative" danebenzustellen war ein Versuch in 1.3 und
  ist wieder draußen: dreimal „Alternative" untereinander sagt nichts.
- **Die Namen der Radvarianten sagen, was sie messen.** „wenig Autos" (die wenigsten Meter
  neben fahrenden Autos) und „wenig Halts" (am seltensten ihretwegen anhalten) — vorher
  hießen sie „ruhigst" und „verkehrsarm" und waren am Wort nicht auseinanderzuhalten.
  Voreingestellte Reihenfolge: **optimal › schnellst › kürzest**, die beiden anderen
  dahinter.
- **Die Einstellungen stehen auf vier Seiten**, vier Einträgen im Menü: Adressen,
  Navigation, Verkehrsmittel, Einstellungen. Es war eine Seite mit sechzehn Abschnitten.
  `Page` in `SettingsView.swift` ist die gemeinsame Klammer.
- **Keine Adressen im Programm** — die App startet leer. Adressen und Einstellungen liegen
  auf dem Gerät und in der **privaten iCloud des Nutzers** (Schlüssel-Wert-Speicher,
  Entitlement `com.apple.developer.ubiquity-kvstore-identifier`); sie gehen an keinen
  Server der App. Das gilt auch für den Verlauf der benutzten Adressen.
- `AppSettings.load()` ist zugleich das Neuladen nach einem iCloud-Zug: jede Eigenschaft
  behält ihren Wert, wenn der Schlüssel fehlt — ein halber Speicher darf nichts löschen.
- Adressen werden immer mit PLZ und Ort gezeigt; in der Kopfzeile klein hinter der Straße,
  sonst als zweite Zeile.
- Blockreihenfolge: Fahrrad, Rad + Bahn, Auto, Bahn & Bus.

## Was seit 1.2 dazugekommen ist (Builds 28–35)

Ein Tag, acht Builds; die Reihenfolge steht im `CHANGELOG.md`, hier nur, was man wissen
muss, um sich zurechtzufinden.

- **Der Hänger ist weg** — ein `TimelineView` in einer `ToolbarItem`. Siehe unten.
- **Die Kästen füllen sich der Reihe nach** (Reihenfolge aus den Einstellungen), und
  aktiv ist die erste Kategorie dieser Reihenfolge, die etwas gefunden hat — nicht die
  empfohlene.
- **Höhenmeter zählen in die Fahrzeit**, fünf Sekunden je Meter, aus BRouters
  `filtered ascend`. Eine Linie ohne Höhen (Apple Karten) bekommt für die Bewertung den
  Durchschnitt der bekannten, damit sie weder gewinnt noch verliert.
- **Neben der Route**: Pfeil zurück, Karte geht heraus und bleibt in Fahrtrichtung, und
  eine Neuplanung nach Entfernung oder Zeit.
- **Warnungen stimmen auch, während die App zu ist** (`BackgroundReplan`).
- **Das Regenradar wird geglättet** — über den Kachelrand hinaus, sonst Nähte.
- **Der Straßenbalken** steht auch auf der Hauptseite, dünn und ohne Legende.
- **Die Fahrtansicht zeigt die Gesamtstandzeit** neben der Zeit an den Ampeln.

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

- **Englische Fassung: Mechanismus steht, Übersetzung liegt beiseite.** Ein Umschalter
  im Burger-Menü war gebaut und bewiesen — ohne Neustart, mit zwei Fähnchen. Übersetzt
  sind 14 von rund 260 Texten, deshalb wieder ausgebaut. Alles, was man dafür wissen
  muss, steht in `_claude.code/RadPendler-Englisch.md`: der funktionierende Weg (`L(…)`
  liest unmittelbar aus `en.lproj`, weil SwiftUI sich von innen nicht umstellen lässt),
  **vier nachgemessene Sackgassen**, die man nicht nochmal gehen muss, und wo der
  erhaltene Stand liegt. Dort anfangen.

- **Die Linien reisen** (seit Build 29, Schema seit 24.09.2026 in Production).
  `TrackCloud` hängt an `RideStore.add` / `delete` / `track(for:)`.
  **Die Falle, die einen Abend gekostet hat:** ein TestFlight-Build schreibt in die
  **Production**-Umgebung, nur ein Bau direkt aus Xcode in Development — und in Production
  legt CloudKit **keine Datensatztypen von selbst an**. Die erste Fahrt wurde deshalb
  abgewiesen, folgenlos und unsichtbar. Wer den Typ neu braucht: in Development anlegen
  (`RideTrack` mit Feld `track`, Typ Asset) und *Deploy Schema Changes*. Seit Build 35
  steht ein abgewiesener Upload mit Grund in der Fahrtenliste.
- **Signieren geht wieder von der Kommandozeile**, seit Build 35 auch nachgewiesen
  (Archiv und Upload mit `CODE_SIGN_STYLE: Automatic`). Die
  Xcode-Team-Profile waren älter als der iCloud-Container und kannten ihn nicht;
  automatisches Signieren nimmt **nur** Xcode-eigene Profile und kann sie ohne
  angemeldetes Konto nicht auffrischen — `-allowProvisioningUpdates` scheitert mit
  „Authentication failed", der Schlüssel `PAGC3W2GBL` darf lesen, aber keine Profile
  anlegen. Die Builds 29–33 wurden deshalb von Hand signiert.

  Gelöst, und die Reihenfolge ist der Punkt: **ein Apple-Konto in Xcodes Einstellungen,
  dann einmal für ein Gerät bauen** (erneuert das Entwicklungsprofil) **und einmal
  archivieren und verteilen** (erneuert das Store-Profil). Nur zu bauen reicht nicht —
  Xcode holt je Profil nur das nach, was der jeweilige Schritt braucht.
  Nachgewiesen mit einem Trockenlauf: `clean archive` plus `-exportArchive` mit
  `signingStyle: automatic` und ohne Upload läuft durch.

  Die beiden von Hand erzeugten Profile (`RadPendler AppStore CK`,
  `RadPendlerWatch AppStore CK`) liegen noch im Portal und dürfen weg.
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
