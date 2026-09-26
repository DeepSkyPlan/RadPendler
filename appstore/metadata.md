# RadPendler — App-Store-Metadaten

Alles, was App Store Connect abfragt, in der Reihenfolge, in der es abgefragt
wird. Die Zeichengrenzen sind Apples und werden eingehalten; die Zahlen in
eckigen Klammern sind die aktuelle Länge.

Die Store-Sprache ist **Deutsch (Deutschland)** als primäre Lokalisierung — die
App ist deutschsprachig und ihre Fahrpläne sind deutsche. Eine englische
Fassung von Name, Untertitel, Keywords und Beschreibung steht am Ende und
gehört in die Lokalisierung **Englisch (USA)**, damit die Seite in Stores
außerhalb Deutschlands nicht leer aussieht.

## Einreichungs-Checkliste (1.5, Build 40 — die einzureichende Fassung)

Der Stand, der in den Store soll. Was seit 1.4 dazugekommen ist, steht in
**fett**; alles andere gilt unverändert und ist unten ausgeführt.

1. **Build 1.5 (40)** auswählen — liegt seit dem 26.09.2026 in TestFlight
2. **Screenshots**: `screenshots/iphone-6.5/` (**8 Bilder**) in den 6,5″-Schacht,
   `screenshots/ipad-13/` (**7 Bilder**) in den 13″-Schacht, in der Reihenfolge
   der Dateinummern. **Neu aufgenommen am 26.09.2026 mit Build 40**, darunter
   erstmals eine echte Aufnahme des Fahrtmodus
3. **Was ist neu** — Text unten, **für 1.5**
4. **App-Datenschutz**: Standort → Genauer Standort → App-Funktionalität, nicht
   mit der Identität verknüpft, kein Tracking. Das Datenschutzmanifest
   (`PrivacyInfo.xcprivacy`) liegt im Paket und sagt dasselbe; die Angaben im
   Formular müssen dazu passen
5. **Englische Lokalisierung** (Englisch, USA): Name, Untertitel, Keywords,
   Beschreibung stehen am Ende dieser Datei. Die App selbst spricht seit 1.4
   Englisch — eine leere englische Store-Seite wäre ein Widerspruch
6. **CloudKit-Schema** — **erledigt am 26.09.2026**: `RideTrack` liegt in
   Production, geprüft mit einer Fahrt vom iPhone, die auf dem iPad mit Linie
   ankam. Vor jedem weiteren Feld gilt der Schritt erneut, siehe `HANDOVER.md`
7. Support-, Marketing- und Datenschutz-URL wie unten; **die drei Seiten sind
   seit dem 26.09.2026 als GitHub Pages veröffentlicht**
8. Alterseinstufung 4+, Kategorie Navigation / Reisen, Preis kostenlos

## Einreichungs-Checkliste (1.4, Build 38)

Der Stand, der in den Store soll. Was seit der 1.0-Liste dazugekommen ist,
steht in **fett**; alles andere gilt unverändert und ist unten ausgeführt.

1. **Build 1.4 (38)** auswählen — liegt seit dem 26.09.2026 in TestFlight
2. **Screenshots**: `screenshots/iphone-6.5/` (7 Bilder) in den 6,5″-Schacht,
   `screenshots/ipad-13/` (6 Bilder) in den 13″-Schacht, in der Reihenfolge der
   Dateinummern. **Neu aufgenommen am 26.09.2026 mit Build 38**, Alexanderplatz
   → Potsdam Hbf, sonst nichts
3. **Was ist neu** — Text unten, für 1.4
4. **App-Datenschutz**: Standort → Genauer Standort → App-Funktionalität, nicht
   mit der Identität verknüpft, kein Tracking. **Das Datenschutzmanifest
   (`PrivacyInfo.xcprivacy`) liegt seit Build 38 im Paket** und sagt dasselbe;
   die Angaben im Formular müssen dazu passen
5. **Englische Lokalisierung anlegen** (Englisch, USA): Name, Untertitel,
   Keywords, Beschreibung stehen am Ende dieser Datei. **Seit 1.4 spricht die
   App selbst Englisch** — eine leere englische Store-Seite wäre jetzt ein
   Widerspruch
6. **CloudKit-Schema übernehmen**, falls noch nicht geschehen: Dashboard →
   Schema → Deploy, Development → Production. Ohne das reisen die Linien der
   aufgezeichneten Fahrten in der Store-Fassung **nicht**
7. Support-, Marketing- und Datenschutz-URL wie unten; die Seiten liegen unter
   `appstore/pages/` und müssen als GitHub-Pages-Repositories veröffentlicht
   sein, bevor die URLs gültig sind
8. Alterseinstufung 4+, Kategorie Navigation / Reisen, Preis kostenlos

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
8. **App-Datenschutz** — bis 1.0 „Nein“ auf jede Erhebungskategorie. **Seit 1.1
   stimmt das nicht mehr ungeprüft**: die App zeichnet auf Wunsch eine Fahrt auf
   und ortet dabei auch im Hintergrund. Die Aufzeichnung verlässt zwar das Gerät
   nicht (die Kennzahlen gehen nur in die eigene iCloud des Nutzers, die Linien
   gar nicht), aber Start- und Zielkoordinaten gehen seit jeher an die Routing-
   und Fahrplandienste. Vor der Store-Einreichung ist deshalb **Standort →
   Genauer Standort → App-Funktionalität, nicht mit der Identität verknüpft,
   kein Tracking** zu setzen. Die Begründung steht im Abschnitt Datenschutz, die
   ausführliche Fassung auf der Datenschutzseite
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

Länge: **3994** von 4000 Zeichen. Stand 1.5.

```
Wie kommst du heute zur Arbeit?

RadPendler rechnet dieselbe Strecke auf vier Arten und stellt sie
nebeneinander: Rad, Rad und Bahn, Auto, Bus & Bahn. Vier Kästen, vier
Fahrzeiten, ein Stern an dem, der heute gewinnt — auf einer Seite.

Gebaut für einen echten Arbeitsweg — und sie sagt, was sie nicht weiß, statt
zu raten.

DIE VIER WEGE
• Fahrrad in Varianten: schnellst, kürzest, optimal, ruhigst, verkehrsarm. Aus
  mehreren BRouter-Profilen und aus Apple Karten, bewertet nach Ampeln und
  Hauptstraßen
• Rad + Bahn: die App sucht sich die Bahnhöfe selbst, radelt hin, fährt mit und
  radelt weiter
• Auto: optimal, schnellst, kürzest oder wenig Ampeln — jede Linie, die
  Apple Karten anbietet, nicht nur die schnellste
• Bus & Bahn: die Fahrplanverbindung mit Umstiegen, Gleisen und Echtzeit

AMPELN, DIE MITZÄHLEN
Eine Radzeit ohne Ampeln ist eine Radzeit für ein leeres Land. RadPendler holt
Lichtsignalanlagen und Hauptstraßen entlang der Strecke aus OpenStreetMap und
zeichnet sie auf die Karte. Fahrzeit = Strecke ÷
Rolltempo + Wartezeit je Ampel — beides von dir einstellbar.

FAHRTEN AUFZEICHNEN, UND DIE APP LERNT DARAUS
Ein Knopf neben der gewählten Fahrt zeichnet auf, was du wirklich fährst:
Strecke, Tempo, jeden Halt, das Höhenprofil und den Untergrund.

Dann rechnet die App mit deinen Zahlen weiter: dein gemessener Schnitt ersetzt
die Schätzung, und jede Kreuzung, an der du wirklich standest, kostet beim
nächsten Planen, was sie dich gekostet hat.

WAS DER FAHRTMODUS DAFÜR ZEIGT
Eine Seite, die vom Lenker aus zu lesen ist: das Tempo jetzt, der gefahrene
Schnitt neben dem geplanten, die Restzeit mit Ankunftszeit und die Ampeln als
„3/18“ samt der Zeit, die du an ihnen gestanden hast. Wer vom Weg abkommt,
sieht, wie weit — und bekommt eine neue Route in Fahrtrichtung. „Pause“ für
die gewollte Unterbrechung; von selbst hält die Aufzeichnung an, wenn du lange
stehst, und läuft weiter, sobald es weitergeht. Der Bildschirm dunkelt ab,
solange niemand ihn anfasst, und bleibt am Ladekabel hell.

REGEN, WO DU FÄHRST
Nicht „Regenwahrscheinlichkeit 40 %“, sondern Regen an den Punkten deiner
Strecke zu den Minuten, an denen du dort bist. Die Radarbilder laufen über der
Karte von jetzt bis zwei Stunden voraus, die Positionsmarke wandert mit.

FAHRRADMITNAHME, VON DIR ENTSCHIEDEN
Kein Fahrplan weiß zuverlässig, ob dein Rad mitdarf. Was der VBB zusichert,
steht auf „Rad ja“. Alles andere ist „ungeklärt“ — und wird
trotzdem vorgeschlagen, mit dem Hinweis dazu. In den Einstellungen setzt du
jede Linie auf ja, nein oder offen.

COUNTDOWN BIS ZUM LOSGEHEN
Oben rechts läuft die Zeit bis zum Losgehen — Abfahrt minus deiner Rüstzeit,
nicht bis zur Abfahrt. Die Warnungen kommen als Mitteilung, auch wenn die App
zu ist.

BUNDESWEIT, DEUTSCH UND ENGLISCH
In Berlin und Brandenburg antwortet der VBB — genauer, und als Einziger sagt
er je Zug, ob Räder mitdürfen. Alles darüber hinaus beantwortet
Transitous, die MOTIS-Instanz auf dem bundesweiten DELFI-Datensatz. Die Sprache stellst du im Menü um, ohne Neustart.

iPAD UND APPLE WATCH
Auf dem iPad steht alles nebeneinander: links Adressen, Zeitwahl, die vier
Kästen und der Zeitstrahl, rechts die Karte. Auf der Uhr: derselbe Countdown,
die Fahrt mit allen Abschnitten, die vier Kategorien zum Umwählen — und was du
dort wählst, übernimmt das iPhone.

VORLIEBEN STATT REGELN
Reihenfolge der Verkehrsmittel, Routenvariante, was ein Umstieg wert ist, ab
wieviel Regen das Rad in die Bahn gehört — alles einstellbar, jedes mit
bewährter Voreinstellung.

DEINE ADRESSEN BLEIBEN DEINE
Was du eingibst, bleibt auf deinen Geräten und in deiner eigenen iCloud; es
geht an keinen Server dieses Projekts, weil es keinen gibt. Kein Konto, keine Anmeldung, keine
Analytik, keine Werbung. Quelloffen (MIT).

Datenquellen: VBB, Transitous/MOTIS auf dem DELFI-Datensatz, Apple Karten,
BRouter und Overpass auf OpenStreetMap-Daten (© OpenStreetMap-Mitwirkende,
ODbL), Deutscher Wetterdienst und Open-Meteo.

Alle Zeiten ohne Gewähr.
```

## Was ist neu (1.5)

Für das Feld „Neue Funktionen“ der Version 1.5 (max 4000, hier 1257):

```
Diese Fassung kommt aus dem Auto: die Aufzeichnung kann jetzt mehr als Rad.

UNTERWEGS
• Wer von der Route abkommt, bekommt eine neue — und zwar in Fahrtrichtung.
  Bisher schickte die Neuberechnung einen auf der Autobahn schon mal zurück
  zur letzten Ausfahrt, weil sie nur den Punkt kannte und nicht die Richtung.
• Die Restzeit rechnet im Tempo des Verkehrsmittels, in dem du sitzt. Dreißig
  Kilometer Landstraße sind keine anderthalb Stunden mehr.
• Die Farbskala folgt mit: 8 bis 26 km/h auf dem Rad, 20 bis 100 im Auto und
  in der Bahn. Vorher war im Auto alles grün.
• Die Automatik läuft im Kreis: Pause, Selbstanhalten aus, weiter — ein Knopf,
  drei Zustände, für den Fall, dass der Stau echt ist.
• Am Ladekabel bleibt der Bildschirm hell. Wer am Lenker lädt, will sehen.

HINTERHER
• Jede aufgezeichnete Fahrt merkt sich, mit welcher Fassung sie entstand.
• Wie oft unterwegs neu geplant wurde, steht jetzt da.
• Die Legende erscheint in der Auswertung statt während der Fahrt, skaliert
  auf das, was diese Fahrt wirklich an Tempo hatte.
• Die ursprüngliche Route liegt blau gestrichelt unter der neuen.

AUSSERDEM
Das Menü im Querformat zeigt wieder alle Einträge, und die Anzeigen auf der
Fahrtseite gehen einander nicht mehr über den Weg.
```

## Was ist neu (1.4)

Für das Feld „Neue Funktionen“ der Version 1.4 (max 4000, hier 1063):

```
Diese Fassung kommt von der Straße: sie zeichnet Fahrten auf und rechnet
danach mit deinen Zahlen weiter.

AUFZEICHNEN
• Die Aufzeichnung hält von selbst an, wenn du länger als drei Minuten stehst
  und dort keine Ampel ist — und läuft weiter, sobald du wieder rollst. Nach
  zwanzig Minuten beendet sie sich; das ist der Fall „angekommen und vergessen,
  auf beenden zu tippen“. Ein Knopf schaltet beides für eine Fahrt ab.
• „Pause“ für die gewollte Unterbrechung: die Uhr steht, die Ortung ist aus.
• Der Bildschirm wird dunkel, solange du ihn nicht anfasst, und beim ersten
  Antippen wieder hell — während einer Fahrt der größte Posten auf der
  Stromrechnung.
• Der gefahrene Schnitt steht neben dem geplanten, die Ampeln als „18/20“.

ENGLISCH
Die App spricht Deutsch und Englisch. Umgeschaltet wird im Menü, und die
Umstellung wirkt sofort — auch Zahlen und Uhrzeiten folgen mit.

AUSSERDEM
• Was du löschst, bleibt gelöscht — auch mit zwei Geräten.
• Fehler stehen im Klartext da statt als „Fehler“.
• Weniger Anfragen, weniger Strom: dieselbe Frage bekommt fünf Minuten lang
  dieselbe Antwort, und zwischen den Boxen zu springen kostet gar nichts.
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

**Ein einziger Datentyp: Genauer Standort.** Verwendungszweck
*App-Funktionalität*, **nicht** mit der Identität verknüpft, **kein** Tracking.
Alles andere im Fragebogen: „Nein“.

So steht es seit 1.4 auch im Datenschutzmanifest im Paket (unten), und beide
müssen dasselbe sagen — Apple vergleicht sie. Bis 1.0 stand hier „keine Daten“;
das war die schärfere Lesart (es gibt keinen Server dieses Projekts, keine
Analytik, kein fremdes SDK, kein Konto, keine Werbung), aber der Standort
verlässt das Gerät nun einmal als Koordinate an die Routing-Dienste, und die
konservative Angabe ist die, die zum Manifest passt.

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

**Liegt seit Build 38 bei** (`RadPendler/Resources/PrivacyInfo.xcprivacy`) und
wandert als Datei ins Paket — nachgeprüft am Archiv. Was drinsteht:

| Kategorie | Grund | Warum |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Adressen, Einstellungen und die Zahlen der Fahrten, nur für die App selbst |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | Alter des Overpass-Zwischenspeichers und der abgelegten Linien |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | der Kartenzwischenspeicher wird nur angelegt, wenn Platz ist |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | Zeitstempel einer laufenden Aufzeichnung, damit eine abgebrochene Fahrt ihre Dauer behält |

`NSPrivacyTracking` ist `false`, `NSPrivacyTrackingDomains` leer. **Nicht leer
ist `NSPrivacyCollectedDataTypes`**: der genaue Standort wird erhoben, für die
Funktion der App, ohne Verknüpfung mit einer Person und ohne Tracking. Das muss
mit den Antworten im Formular übereinstimmen — steht dort „wird nicht erhoben“
und im Manifest das Gegenteil, ist das ein Widerspruch in der eigenen
Einreichung.

## Screenshots

Hochkant, weil die App hochkant ist. Die Größen, die App Store Connect für die
beiden Schächte annimmt, sind kurz; alles andere wird beim Hochladen abgelehnt:

| Geräteklasse | Simulator | Größe | Ordner |
|---|---|---|---|
| iPhone 6,5″ | DF-iphone65 (iPhone 13 Pro Max) | 1284 × 2778 | `screenshots/iphone-6.5/` |
| iPad 13″ | iPad Pro 13-inch (M5) | 2064 × 2752 | `screenshots/ipad-13/` |

Ein 6,9″-Telefon (iPhone 17 Pro Max) nimmt mit 1320 × 2868 auf, und das steht
**nicht** auf der Liste — der 6,5″-Satz muss aus einem 6,5″-Simulator kommen.

Reihenfolge und der Bildtext, den jedes Bild tragen soll (Stand 26.09.2026,
aufgenommen mit Build 40):

**iPhone** — acht Bilder

1. `1-hauptseite` — „Vier Wege, eine Seite. Der Stern sitzt auf dem, der heute gewinnt.“
2. `2-rad` — „Die Radroute mit ihren Ampeln — gezählt, nicht geschätzt.“
3. `3-fahrt` — „Jede Fahrt im Zeitstrahl: Ampeln, Querungen, Hauptstraßen, Regen.“
4. `4-radbahn` — „Rad + Bahn: hinradeln, mitfahren, weiterradeln.“
5. `5-menue` — „Alles eine Ebene tief — und die Sprache gleich mit dabei.“
6. `6-vorlieben` — „Deine Vorlieben, nicht meine Regeln.“
7. `7-einstellungen` — „Was die App während der Fahrt tut — und wann sie sich selbst anhält.“
8. `8-fahrtmodus` — „Unterwegs: Tempo jetzt, Schnitt gegen Plan, Restzeit, Ampeln.“

**iPad** — sieben Bilder

1. `1-hauptseite` — „Auf dem iPad steht alles nebeneinander: Plan links, Karte rechts.“
2. `2-rad` — „Die Radroute mit Straßenarten, Ampeln und Höhenmetern.“
3. `3-radbahn` — „Rad + Bahn, mit Bahnhöfen, die die App selbst sucht.“
4. `4-menue` — „Alles eine Ebene tief — und die Sprache gleich mit dabei.“
5. `5-vorlieben` — „Reihenfolge, Routenvariante, Regenschwelle — alles einstellbar.“
6. `6-einstellungen` — „Was die App während der Fahrt tut — und wann sie sich selbst anhält.“
7. `7-fahrtmodus` — „Unterwegs: Tempo jetzt, Schnitt gegen Plan, Restzeit, Ampeln.“

**Wozu der Fahrtmodus da ist** — für den Bildtext und für jede Frage danach:
Er ist die Seite, die während des Fahrens läuft. Sie zeigt das Tempo jetzt,
den gefahrenen Schnitt neben dem geplanten, die Restzeit mit Ankunftszeit, die
Ampeln als „3/18“ und die an ihnen verlorene Zeit; sie warnt, wenn man neben
der Route ist, und plant von dort aus neu. Zugleich ist sie die Messung, aus
der die App lernt: der gemessene Schnitt und die wirklich kostenden Kreuzungen
gehen in die nächste Planung ein. Deshalb gehört sie in die Bilder — ohne sie
sieht die App wie ein reiner Planer aus.

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
# Der Fahrtmodus startet sonst im Querformat — im Store-Schacht gilt hochkant.
xcrun simctl spawn $UDID defaults write de.keese.radpendler rideOrientationLock -string portrait
xcrun simctl privacy $UDID grant location-always de.keese.radpendler

# Die Aufnahme des Fahrtmodus braucht **Bewegung**, sonst stehen dort Nullen.
# Die Punkte sind die ersten Meter der Radroute ab Alexanderplatz (BRouter);
# 6 m/s sind 21,6 km/h. In zsh als Array, sonst wird daraus ein Argument.
WP=(52.521027,13.412965 52.521011,13.412359 52.520720,13.412771 52.520675,13.412163
    52.520097,13.411077 52.519663,13.410140 52.519404,13.409581 52.519052,13.408822
    52.518829,13.408110 52.518590,13.407613 52.518364,13.407084 52.518039,13.406290)
xcrun simctl location $UDID start --speed=6 --interval=1 $WP &

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

**Erledigt (26.09.2026):** Der iPad-Satz hat seine Radrouten-Aufnahme, und
beide Sätze haben eine echte Aufnahme des Fahrtmodus — vorher zeigte das Bild
mit diesem Namen die Einstellungsseite.

**Dritte Falle, am 26.09.2026 bezahlt:** Läuft die simulierte Fahrt neben der
geplanten Route, steht ein rotes „151 m neben der Route“ quer über dem Bild.
Der Test fährt deshalb 80 Sekunden statt 45: dann hat die App von selbst neu
geplant, das Band ist weg, und im Kopf steht stattdessen der Zähler „1×“.

**Zwei Fallen, beide am 26.09.2026 bezahlt:**

- **Der Simulator spielt Adressen zurück.** Auf dem iPad stand im Kopf
  plötzlich eine Adresse aus einem früheren Lauf, während die Route schon die
  neue war — der iCloud-Abgleich hatte sie nach dem Start überschrieben. Hilft:
  `xcrun simctl erase <UDID>`, dann App installieren, dann die Adressen setzen.
- **Nach einem `erase` sind die Kartenkacheln leer.** Der erste Lauf danach
  zeigt ein weißes Gitter statt einer Karte; der zweite ist gut. Also immer
  zweimal laufen lassen und die Bilder ansehen.

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
