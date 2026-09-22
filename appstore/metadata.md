# RadPendler — App-Store-Metadaten

Alles, was App Store Connect abfragt, in der Reihenfolge, in der es abgefragt
wird. Die Zeichengrenzen sind Apples und werden eingehalten; die Zahlen in
eckigen Klammern sind die aktuelle Länge.

Die Store-Sprache ist **Deutsch (Deutschland)** als primäre Lokalisierung — die
App ist deutschsprachig und ihre Fahrpläne sind deutsche. Eine englische
Fassung von Name, Untertitel, Keywords und Beschreibung steht am Ende und
gehört in die Lokalisierung **Englisch (USA)**, damit die Seite in Stores
außerhalb Deutschlands nicht leer aussieht.

## Einreichungs-Checkliste (1.0, Build 22)

Die erste Einreichung überhaupt: bisher lief RadPendler nur über TestFlight,
intern. In App Store Connect, auf der Versionsseite 0.12.1:

1. **App anlegen** — Apple erlaubt kein Anlegen per API, das muss von Hand im
   Browser passieren. Bundle-ID `de.keese.radpendler`, Team 5PX3V6L522,
   SKU z. B. `radpendler`, Primärsprache Deutsch
2. **Build** — 0.12.1 (19) hochladen und auswählen. Die Exportkonformität ist
   im Binary beantwortet (`ITSAppUsesNonExemptEncryption = NO`), es wird also
   nicht danach gefragt
3. **Screenshots** — `screenshots/iphone-6.5/` in den 6,5″-Schacht,
   `screenshots/ipad-13/` in den 13″-Schacht, in der Reihenfolge der
   Dateinummern. Die Bildtexte stehen weiter unten. **Hochkant**, weil die App
   hochkant ist
4. **Beschreibung, Werbetext, Keywords, Untertitel** — wie unten
5. **Support-URL** — https://deepskyplan.github.io/radpendler-app/#support
6. **Marketing-URL** — https://deepskyplan.github.io/radpendler-app/
7. **Datenschutz-URL** — https://deepskyplan.github.io/radpendler-privacy/
   (beide Seiten liegen fertig unter `appstore/pages/`; die Repositories dafür
   gibt es noch nicht — siehe Checkliste am Ende)
8. **App-Datenschutz** — „Nein“ auf jede Erhebungskategorie. Die Begründung
   steht im Abschnitt Datenschutz
9. **Alterseinstufung 4+**, Kategorie Navigation / Reisen, Copyright wie unten
10. **Preis: kostenlos**, Verfügbarkeit: alle Länder — die App funktioniert
    außerhalb Deutschlands nur eingeschränkt (Fahrpläne über Transitous gehen
    über Deutschland hinaus, das Regenradar des DWD nicht), das ist aber kein
    Grund, sie auszusperren. Wer sie anderswo lädt, bekommt Radrouten, Autowege
    und, wo Transitous Daten hat, Fahrpläne
11. **Beta-Prüfung** — nur nötig, wenn externe TestFlight-Tester dazukommen
    sollen. Für die Store-Einreichung selbst nicht

## Name (max 30)

RadPendler  [10]

## Untertitel (max 30)

Pendeln: Rad, Bahn oder Auto?  [29]

## Werbetext (max 170)

Vier Wege zur Arbeit nebeneinander: Rad, Rad + Bahn, Auto, Bus & Bahn. Mit
Ampeln auf der Strecke, Regen je Streckenpunkt und einem Countdown bis zum
Losgehen.  [159]

Der Werbetext lässt sich ohne neue Version ändern — hier gehört hin, was gerade
neu ist, nicht was immer gilt.

## Beschreibung (max 4000)

Länge: **3988** von 4000 Zeichen.

```
Wie kommst du heute zur Arbeit?

RadPendler rechnet dieselbe Strecke auf vier Arten und stellt sie
nebeneinander: mit dem Rad, mit Rad und Bahn, mit dem Auto und mit Bus & Bahn.
Vier Kästen, vier Fahrzeiten, ein Stern an dem, der heute gewinnt — auf einer
Seite, ohne Scrollen.

Gebaut für einen echten Arbeitsweg und danach allgemein geworden. Die App
kennt keine eingebauten Adressen, rechnet die Radzeit aus der rollenden
Geschwindigkeit plus Wartezeit je Ampel — und sagt, was sie nicht weiß, statt
zu raten.

DIE VIER WEGE
• Fahrrad in Varianten: schnellst, kürzest, optimal, ruhigst. Aus mehreren
  BRouter-Profilen und aus Apple Karten, bewertet nach Ampeln, gequerten
  Hauptstraßen und Metern neben Hauptstraßen
• Rad + Bahn: die App sucht sich die Bahnhöfe selbst, radelt hin, fährt mit und
  radelt weiter
• Auto: optimal, schnellst, kürzest oder wenig Ampeln — jede Linie, die
  Apple Karten anbietet, nicht nur die schnellste
• Bus & Bahn: die Fahrplanverbindung mit Umstiegen, Gleisen und Echtzeit

AMPELN, DIE MITZÄHLEN
Eine Radzeit ohne Ampeln ist eine Radzeit für ein leeres Land. RadPendler holt
Lichtsignalanlagen und Hauptstraßen entlang der Strecke aus OpenStreetMap,
zählt die Kreuzungen und zeichnet sie auf die Karte. Fahrzeit = Strecke ÷
Fahrgeschwindigkeit + Wartezeit je Ampel — beides von dir einstellbar.

REGEN, WO DU FÄHRST
Nicht „Regenwahrscheinlichkeit 40 %“, sondern Regen an den Punkten deiner
Strecke zu den Minuten, an denen du dort bist — aus dem Nowcast des Deutschen
Wetterdienstes und aus Open-Meteo. Die Radarbilder laufen über der Karte von
jetzt bis zwei Stunden voraus, die Positionsmarke wandert mit. Ab wieviel Regen
das Rad in die Bahn gehört, entscheidest du.

FAHRRADMITNAHME, VON DIR ENTSCHIEDEN
Kein Fahrplan weiß zuverlässig, ob dein Rad mitdarf. Was der VBB zusichert,
steht auf „Rad ja“. Alles andere ist „ungeklärt“ — und wird trotzdem
vorgeschlagen, mit dem Hinweis dazu, statt stillschweigend zu verschwinden. In
den Einstellungen setzt du jede Linie auf ja, nein oder offen; ein Nein nimmt
sie aus den Rad-+-Bahn-Vorschlägen heraus.

COUNTDOWN BIS ZUM LOSGEHEN
Oben rechts läuft die Zeit bis zum Losgehen — Abfahrt minus deiner Rüstzeit,
nicht bis zur Abfahrt. Die Pille färbt sich mit: grün, gelb ab 30 Minuten,
orange ab 10, rot ab 5, dunkelrot sobald die Bahn weg ist. Die Warnungen kommen
als Mitteilung, auch wenn die App zu ist. Ein Tipp auf die Pille stellt beides
ab, wenn du diese Bahn ohnehin nicht nimmst.

BUNDESWEIT
In Berlin und Brandenburg antwortet der VBB — dort ist er genauer und sagt als
Einziger je Zug, ob Räder mitdürfen. Alles darüber hinaus beantwortet
Transitous, die von Freiwilligen betriebene MOTIS-Instanz auf dem bundesweiten
DELFI-Datensatz, die Rad und Bahn in einem Zug plant.

iPAD UND APPLE WATCH
Auf dem iPad steht alles nebeneinander: links Adressen, Zeitwahl, die vier
Kästen, die Begründung der Empfehlung und der ganze Zeitstrahl — rechts die
Karte über die volle Höhe. Auf der Uhr: Countdown in derselben Ampelfarbe wie
auf dem iPhone, die Fahrt mit allen Abschnitten, die vier Kategorien zum
Umwählen — und was du dort wählst, übernimmt das iPhone. Die Uhr plant nie
selbst: sie zeigt, was das iPhone geschickt hat.

VORLIEBEN STATT REGELN
Reihenfolge der Verkehrsmittel, Routenvariante, was ein Umstieg wert ist, wie
lange du zum Fertigmachen brauchst, ab wieviel Regen das Rad in die Bahn
gehört — alles einstellbar, jedes mit einer bewährten Voreinstellung.

DEINE ADRESSEN BLEIBEN DEINE
Die App wird ohne Adressen ausgeliefert und enthält keine. Was du eingibst,
bleibt auf deinen Geräten und in deiner eigenen iCloud; es geht an keinen
Server dieses Projekts, weil es keinen gibt. Kein Konto, keine Anmeldung, keine
Analytik, keine Werbung. Quelloffen (MIT).

Datenquellen: VBB, Transitous/MOTIS auf dem DELFI-Datensatz, Apple Karten,
BRouter und Overpass auf OpenStreetMap-Daten (© OpenStreetMap-Mitwirkende,
ODbL), Deutscher Wetterdienst und Open-Meteo.

Alle Zeiten ohne Gewähr.
```

## Was ist neu (erste Version 1.0 — Feld bleibt leer)

Bei der ersten Store-Version fragt App Store Connect nicht nach „Was ist neu“.
Für die erste Aktualisierung danach steht der Text im `CHANGELOG.md` bereit;
in Kundensprache zusammengefasst wäre es für 0.12.x:

```
• Bundesweite Fahrpläne über Transitous, neben dem VBB. Rad + Bahn geht jetzt
  auch über weite Strecken: Rad zum Bahnhof, Zug, Rad weiter — in einer
  Anfrage.
• Fahrradmitnahme wird nie stillschweigend als Nein gelesen. Was der Fahrplan
  nicht zusichert, heißt „ungeklärt“ und steht zur Wahl.
• Gleisangaben auch dort, wo der Datensatz kein eigenes Feld dafür hat.
```

## Keywords (max 100, kommagetrennt, ohne Leerzeichen)

Pendeln,Arbeitsweg,Fahrrad,Radroute,Fahrradmitnahme,Bahn,VBB,ÖPNV,Regenradar,Ampeln,Countdown,Route  [99]

Der App-Name selbst wird von Apple mitindiziert und gehört nicht in die
Keywords; „RadPendler“, „Pendler“ und „Rad“ stehen deshalb nicht drin.

## Kategorie

Primär: **Navigation** — Sekundär: **Reisen**

Navigation, weil das Ergebnis eine Route ist, die auf einer Karte liegt; Reisen
als zweite, weil Fahrpläne und Verbindungen den zweiten Teil ausmachen. Nicht
„Gesundheit und Fitness“: die App misst nichts an dir.

## Alterseinstufung

**4+** — keine anstößigen Inhalte, keine Werbung, keine In-App-Käufe, keine
Nutzerinhalte, kein Chat, kein Glücksspiel, kein uneingeschränkter Webzugriff.

Im Fragebogen ist nur zu beachten: **„Häufigkeit/Intensität unbeschränkten
Webzugriffs: keiner“** — die zwei Links im Menü (transitous.org/sources und
openstreetmap.org/copyright) öffnen Safari und sind damit kein eingebauter
Browser.

## Copyright

© 2026 AK

So steht es auch im Menü der App. Kein Klarname, das ist Absicht — siehe
Datenschutz.

## Support-URL

https://deepskyplan.github.io/radpendler-app/#support

Das App-Repository ist zwar öffentlich, aber ein Issue-Tracker ist keine
Support-Seite; die Marketingseite trägt den Abschnitt „Support“ mit der
Adresse, an die geschrieben wird, und was in die Mail gehört.

## Marketing-URL

https://deepskyplan.github.io/radpendler-app/

Quelle: `appstore/pages/radpendler-app/index.html` in diesem Repository,
gedacht für ein eigenes öffentliches Repository `DeepSkyPlan/radpendler-app`
mit GitHub Pages aus `main` — so wie `vorsim-app` und `vorsim-privacy`.

## Datenschutz-URL

https://deepskyplan.github.io/radpendler-privacy/

Quelle: `appstore/pages/radpendler-privacy/index.html`, gedacht für
`DeepSkyPlan/radpendler-privacy`.

## App-Datenschutz — die Antworten auf den Fragebogen

**Erhobene Daten: keine.** Auf jede Kategorie „Nein“.

Der Fragebogen fragt nach Daten, die **der Entwickler oder seine Partner**
erheben. Es gibt keinen Server dieses Projekts und keine Analytik, kein SDK
eines Dritten, kein Konto und keine Werbung — also ist die Antwort überall
„Nein“. Das ist keine Auslegungsfrage, sondern der Aufbau der App.

Was trotzdem gesagt gehört, und was die Datenschutzseite ausdrücklich sagt:

• **Adressen und Einstellungen** liegen in `UserDefaults` auf dem Gerät und,
  wenn ein iCloud-Konto angemeldet ist, im **iCloud-Schlüssel-Wert-Speicher des
  Nutzers** (Entitlement `com.apple.developer.ubiquity-kvstore-identifier`).
  Das ist seine eigene iCloud, nicht die des Entwicklers: Apple speichert es,
  niemand sonst liest es. Betroffen sind Start, Ziel, Zuhause, Arbeit,
  Fixpunkte, die Liste der benutzten Adressen und alle Einstellungen
• **Start- und Zielkoordinaten gehen zwangsläufig an die Routing-Dienste** —
  anders ist keine Route zu berechnen. Wer eine Route will, verrät, wo sie
  anfängt. Die Dienste sind:
  – **VBB** (`fahrinfo.vbb.de`) — Fahrplan und Echtzeit in Berlin/Brandenburg
  – **Transitous / MOTIS** (`api.transitous.org`) — Fahrpläne darüber hinaus.
    Jede Anfrage trägt einen `User-Agent` mit Name, Version und einer
    Kontaktadresse, wie deren Nutzungsbedingungen es verlangen
  – **Apple MapKit** — Kartenkacheln, Adresssuche, Auto- und Fußwege
  – **BRouter** (`brouter.de`) — Radrouten
  – **OpenStreetMap über Overpass** — Ampeln und Straßen im Korridor der Route
    (eine Umgebungsabfrage, nicht die Route selbst; 30 Tage zwischengespeichert)
  – **Deutscher Wetterdienst** (GeoServer-WMS) — Radarkacheln für den
    Kartenausschnitt
  – **Open-Meteo** — Regen an den Punkten der Strecke
  Jede dieser Anfragen trägt, wie jede Netzanfrage, die IP-Adresse des Geräts
  zum jeweiligen Dienst. Der Entwickler sieht sie nie
• **Standort**: die App fragt nach „Beim Verwenden der App“, um den Start auf
  deine Position zu legen. Wird das abgelehnt, funktioniert alles weiter, nur
  müssen beide Adressen von Hand gewählt werden
• **Mitteilungen**: lokale Mitteilungen für die Warnung vor dem Losgehen, auf
  dem Gerät erzeugt. Kein Push-Server, kein Token, das irgendwohin ginge
• **Uhr**: der Plan geht per WatchConnectivity direkt aufs eigene Handgelenk —
  `TripSnapshot` enthält bewusst keine Koordinaten und keine Routen, nur Zeiten,
  Linien und Farben

## Datenschutzmanifest (`PrivacyInfo.xcprivacy`)

**Fehlt noch** und gehört vor der Einreichung dazu. Apple weist Uploads ohne
Manifest nicht zurück, verlangt aber für die „required reason APIs“ eine
Begründung; RadPendler benutzt davon:

| Kategorie | Grund | Warum |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Adressen und Einstellungen, nur für die App selbst |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | nur falls der Overpass-Cache je nach freiem Platz schreibt — sonst weglassen |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | Alter des Overpass-Caches und des Plans auf der Uhr |

`NSPrivacyTracking` auf `false`, `NSPrivacyTrackingDomains` und
`NSPrivacyCollectedDataTypes` leer. Vor dem Eintragen jede Zeile gegen den Code
prüfen: ein Eintrag für eine API, die die App nicht aufruft, ist genauso falsch
wie ein fehlender.

## Screenshots

Hochkant, weil die App hochkant ist. Die Größen, die App Store Connect für die
beiden Schächte annimmt, sind kurz; alles andere wird beim Hochladen abgelehnt:

| Geräteklasse | Simulator | Größe | Ordner |
|---|---|---|---|
| iPhone 6,5″ | DF-iphone65 (iPhone 13 Pro Max) | 1284 × 2778 | `screenshots/iphone-6.5/` |
| iPad 13″ | iPad Pro 13-inch (M5) | 2064 × 2752 | `screenshots/ipad-13/` |

Ein 6,9″-Telefon (iPhone 17 Pro Max) nimmt mit 1320 × 2868 auf, und das steht
**nicht** auf der Liste — der 6,5″-Satz muss aus einem 6,5″-Simulator kommen.

Reihenfolge und der Bildtext, den jedes Bild tragen soll:

**iPhone**

1. `1-hauptseite` — „Vier Wege, eine Seite. Der Stern sitzt auf dem, der heute gewinnt.“
2. `2-rad` — „Die Radroute mit ihren Ampeln — gezählt, nicht geschätzt.“
3. `3-fahrt` — „Jede Fahrt im Zeitstrahl: Ampeln, Querungen, Hauptstraßen, Regen.“
4. `4-radbahn` — „Rad + Bahn: hinradeln, mitfahren, weiterradeln.“
5. `5-vorlieben` — „Deine Vorlieben, nicht meine Regeln.“
6. `6-fahrradmitnahme` — „Ob dein Rad mitdarf, entscheidest du — je Linie.“

**iPad**

1. `1-hauptseite` — „Auf dem iPad steht alles nebeneinander: Plan links, Karte rechts.“
2. `2-vorlieben` — „Reihenfolge, Routenvariante, Regenschwelle — alles einstellbar.“
3. `3-fahrradmitnahme` — „Rad ja, Rad nein, offen: die Linienliste.“

### Neu aufnehmen

Die Aufnahmen macht `RadPendlerUITests/ScreenshotTests` — ein eigenes Schema
`RadPendlerShots`, damit `./dev test` schnell bleibt. Es tippt sich durch die
App und hängt jedes Bild ans Testergebnis.

```sh
# Adressen setzen, ohne je eine echte zu benutzen (die App startet leer):
hex() { python3 -c "import sys,json;print(json.dumps(json.loads(sys.argv[1]),ensure_ascii=False).encode().hex())" "$1"; }
UDID=…   # 6,5″-Telefon oder iPad Pro 13″
xcrun simctl spawn $UDID defaults write de.keese.radpendler origin -data \
  "$(hex '{"name":"Alexanderplatz, 10178 Berlin","latitude":52.5210,"longitude":13.4130,"postalCode":"10178","locality":"Berlin"}')"
xcrun simctl spawn $UDID defaults write de.keese.radpendler destination -data \
  "$(hex '{"name":"Potsdam Hauptbahnhof, 14473 Potsdam","latitude":52.3914,"longitude":13.0672,"postalCode":"14473","locality":"Potsdam"}')"
xcrun simctl spawn $UDID defaults write de.keese.radpendler alertsOn -bool NO

xcodebuild test -project RadPendler.xcodeproj -scheme RadPendlerShots \
  -destination "platform=iOS Simulator,id=$UDID" -resultBundlePath /tmp/shots.xcresult
xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
# /tmp/shots/manifest.json ordnet jedem UUID-Dateinamen den Szenennamen zu.
```

**Hochkant heißt: nicht drehen.** Anders als bei VOR Sim (quer) kommen die
Bilder schon richtig herum aus dem Bildpuffer; es ist kein `sips -r` und kein
EXIF-Aufräumen nötig.

**Vor dem Hochladen jedes Bild ansehen.** Die Einstellungen der App gleichen
sich über iCloud ab; ein im Simulator angemeldetes Konto kann echte Adressen
zurückspielen. Steht eine drauf, App deinstallieren, Adressen neu setzen, neu
aufnehmen. Die Bilder in diesem Ordner zeigen Alexanderplatz → Potsdam Hbf und
sonst nichts.

**Offen:** Der iPad-Satz hat keine Radrouten-Aufnahme. Der Versuch fiel in eine
Overpass-Sperre und trug den Hinweis „Ampeln und Hauptstraßen unbekannt
(OpenStreetMap nicht erreichbar)“ — mit einer Fehlermeldung geht kein Bild in
den Store. Beim nächsten Lauf, wenn Overpass wieder antwortet, nachholen und
als `2-rad` einsortieren.

### Apple Watch (46 mm) — 4 Bilder, 416 × 496

App Store Connect hat für watchOS einen eigenen Satz. Die vier Aufnahmen aus
`screenshots/watch-46/` in den Slot „Apple Watch Series 10 (46 mm)“:

| Datei | Was darauf ist | Bildtext |
|---|---|---|
| `1-countdown.png` | Der Countdown in Gelb, Linie und Abfahrt → Ankunft | Wann losgehen — am Handgelenk |
| `2-fahrt.png` | Die Fahrt mit allen Abschnitten, Zeiten und Kilometern | Jeder Abschnitt, jede Zeit |
| `3-kategorien.png` | Die vier Kategorien mit bester Zeit und Zahl der Wege | Rad, Rad + Bahn, Auto, Bahn |
| `4-wege.png` | Die Wege einer Kategorie zum Auswählen | Einen anderen Weg wählen |

Die Uhr plant nichts selbst; sie zeigt den Plan des iPhones und zählt darauf
herunter. Das gehört in den Bildtext, damit niemand eine eigenständige
Uhren-App erwartet.

## Englische Fassung (Lokalisierung „Englisch (USA)“)

### Name (max 30)

RadPendler  [10]

### Subtitle (max 30)

Bike, train or car to work  [26]

### Promotional text (max 170)

Four ways to work side by side: bike, bike + train, car, bus & train. With the
traffic lights on the route, rain point by point, and a countdown to leaving.
[156]

### Keywords (max 100)

commute,bike,cycling,route,train,transit,bike on train,rain radar,traffic
lights,countdown  [90]

### Description

Length: **3561** of 4000 characters.

```
How are you getting to work today?

RadPendler works out the same journey four ways and puts them side by side: by
bike, by bike and train, by car, and by bus and train. Four boxes, four
journey times, a star on the one that wins today. All on one page, no
scrolling.

The app was built for one real commute and then made general. It ships with no
addresses, works the cycling time out from your rolling speed plus a wait per
signalised junction — and says what it does not know instead of guessing.

THE FOUR WAYS
• Bike, in variants: fastest, shortest, best, quietest. From several BRouter
  profiles and from Apple Maps, scored on traffic lights, main roads crossed
  and metres spent alongside main roads
• Bike + train: the app finds the stations itself, rides there, takes the
  train, rides on
• Car: best, fastest, shortest or fewest lights — every line Apple Maps
  offers, not only the quickest
• Bus and train: the plain timetable connection, with changes, platforms and
  real-time data as far as the service gives it

TRAFFIC LIGHTS THAT COUNT
A cycling time without traffic lights is a cycling time for an empty country.
RadPendler pulls the signals and main roads along the corridor from
OpenStreetMap, counts the junctions on your route and draws them on the map.
Journey time is distance ÷ speed plus the wait per light — both adjustable,
because both depend on you.

RAIN WHERE YOU RIDE
Not "40% chance of rain", but rain at the points of your route at the minutes
you are there, from the German Weather Service nowcast and from Open-Meteo.
The radar frames run over the map from now to two hours ahead with your
position marker moving along. How much rain puts the bike on the train is your
setting.

BIKES ON TRAINS, DECIDED BY YOU
No timetable reliably knows whether your bike may come. What the operator
guarantees reads "bike yes". Everything else is "unclear" — and is still
offered, with the caveat, rather than quietly disappearing. A list in the
settings lets you set every line to yes, no or open.

COUNTDOWN TO LEAVING
Top right, the clock runs down to leaving — departure minus your getting-ready
time, not to the departure itself. It changes colour as it goes and warns you
by notification even when the app is closed. One tap switches it off when you
are not taking that train.

ACROSS GERMANY AND BEYOND
In Berlin and Brandenburg the VBB answers — it is more accurate there and is
the only source that says, train by train, whether bikes may come. Everything
beyond is answered by Transitous, the volunteer-run MOTIS instance on the
nationwide DELFI dataset, which plans bike and train in one go.

ON iPAD AND APPLE WATCH
At regular width everything stands side by side: the plan on the left, the map
full height on the right. On the watch: the countdown in the same colour as on
the phone, the journey with all its legs, and the four categories to switch
between — and what you pick there, the phone takes over. The watch never plans
by itself: it shows what the phone last sent, and how old that is.

YOUR ADDRESSES STAY YOURS
The app ships with no addresses and contains none. What you type stays on your
devices and in your own iCloud; it goes to no server of this project, because
there is none. No account, no sign-in, no analytics, no advertising.

RadPendler is open source (MIT).

Data sources: VBB, Transitous and MOTIS on the DELFI dataset, Apple Maps,
BRouter on OpenStreetMap data, OpenStreetMap via Overpass (© OpenStreetMap
contributors, ODbL), Deutscher Wetterdienst and Open-Meteo.

All times without guarantee.
```

## Was der Nutzer selbst tun muss

Alles, was nicht aus diesem Repository heraus geht:

**Seiten ins Netz bringen**

1. Repository `DeepSkyPlan/radpendler-app` anlegen, öffentlich, und
   `appstore/pages/radpendler-app/index.html` als `index.html` hineinlegen.
   Settings → Pages → Source „Deploy from a branch“, Branch `main`, Ordner `/`
2. Dasselbe für `DeepSkyPlan/radpendler-privacy` mit
   `appstore/pages/radpendler-privacy/index.html`
3. Beide Adressen im Browser aufrufen und prüfen, dass sie da sind, bevor sie
   in App Store Connect eingetragen werden — Apple ruft sie während der Prüfung
   ab, und eine 404 an der Datenschutz-URL ist ein Ablehnungsgrund
4. Optional: die Bilder aus `appstore/screenshots/iphone-6.5/` verkleinert nach
   `shots/` im Seiten-Repository legen und die `<img src="shots/…">` in
   `radpendler-app/index.html` einkommentieren — die Seite steht auch ohne sie,
   sieht mit ihnen aber nach etwas aus

**In App Store Connect**

5. App anlegen (geht nicht per API): Bundle-ID `de.keese.radpendler`,
   Primärsprache Deutsch, SKU frei wählbar
6. Build 1.0 (22) hochladen, auswählen
7. Die Felder von oben eintragen, in der Reihenfolge dieser Datei
8. Screenshots hochladen — 6,5″ und 13″, hochkant
9. Den App-Datenschutz-Fragebogen ausfüllen: überall „Nein“
10. Alterseinstufung 4+, Kategorie Navigation / Reisen
11. Preis auf „kostenlos“ und die Verfügbarkeit wählen
12. Prüfhinweise („App Review Information“): Kontakt-Mail, keine Anmeldedaten
    nötig — **dazuschreiben**, dass die App ohne Adressen startet und der
    Prüfer erst Start und Ziel wählen muss, sonst sieht er eine leere Seite.
    Ein Vorschlag als Prüfhinweis: „Bitte in der Kopfzeile Start und Ziel
    wählen, z. B. Alexanderplatz, Berlin → Potsdam Hauptbahnhof.“

**Vor dem Einreichen noch im Code**

13. `PrivacyInfo.xcprivacy` anlegen und in `project.yml` als Ressource
    aufnehmen (Abschnitt Datenschutzmanifest oben)
14. Die Kontaktadresse in `MotisClient.userAgent` gegen die Adresse prüfen, die
    auf den Seiten steht — Transitous verlangt eine erreichbare
15. ~~Versionsnummer entscheiden~~ — erledigt: die erste Store-Fassung ist
    **1.0**. Die Buildnummer steigt davon unabhängig weiter

**Nur wenn externe Tester dazukommen sollen**

16. Beta-Prüfung beantragen (TestFlight → externe Gruppe). Dafür braucht es die
    Datenschutz-URL und eine Beschreibung, was getestet werden soll — beides
    liegt mit dieser Datei vor
