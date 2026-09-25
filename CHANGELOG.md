# Changelog

## 1.4 (noch nicht hochgeladen) — Pause, Selbstbeenden und weniger Anfragen

- **„Pause" auf dem Fahrtbildschirm.** Für die gewollte Unterbrechung: die Uhr steht, die
  Ortung ist so lange aus, und die Pause zählt weder zur Fahrzeit noch als Halt noch in den
  Schnitt. Es ist zugleich der einzige Knopf dieses Bildschirms, der wirklich Strom spart —
  der Empfänger ist das Teuerste an einer Aufzeichnung.
- **Die App spricht Englisch.** Umgeschaltet wird im Burger-Menü, und die Umstellung wirkt
  sofort, ohne Neustart: 439 Texte liegen als Katalog neben der App, die Uhr bekommt die
  Sprache mit dem Plan, und Zahlen wie Uhrzeiten folgen der gewählten Sprache („1.5 km"
  statt „1,5 km"). Fehlt eine Übersetzung, steht der deutsche Text da — nie ein Platzhalter.
- **Der Bildschirm wird während der Fahrt dunkel**, solange du ihn nicht anfasst (nach 30 s,
  einstellbar, abschaltbar) — und beim ersten Antippen wieder hell, ebenso wenn eine Abbiegung
  ansteht oder du neben der Route bist. iOS dimmt hier von sich aus nichts, weil der
  Ruhezustand für die Fahrt abgeschaltet ist; der Bildschirm ist dabei der größte Posten auf
  der Stromrechnung, größer als die Ortung. Die vorherige Helligkeit kommt bei Fahrtende,
  Pause und beim Verlassen der App zurück.
- **Die Aufzeichnung beendet sich von selbst**, wenn sie länger als eingestellt (10 min,
  abschaltbar) an derselben Stelle steht und dort keine bekannte Ampel ist. Gezählt wird bis
  zum Anfang des Stillstands; eine Mitteilung sagt Bescheid. Das ist der Fall „angekommen
  und vergessen, auf beenden zu tippen", und er kostete bisher eine Stunde Ortung auf dem
  Schreibtisch.
- **„Sonstiges" nach einer Neuplanung.** Wurde unterwegs neu geplant, hingen die Stützpunkte
  des neuen Wegs hinten an der Liste, und die Zuordnung suchte nur vorwärts im Rest des
  alten — sie fand nichts mehr und schrieb **den ganzen Rest der Fahrt** als „sonstiges"
  gut, obwohl jede Straße bekannt war. Die Zuordnung springt jetzt auf den neuen Abschnitt
  und sieht im Zweifel einmal die ganze Liste durch.
- **Eine Zahl statt zweier.** In der Fahrt und in der Fahrtenliste stehen der gefahrene und
  der geplante Schnitt in einem Feld („13,2 / 14,7 Plan"), ebenso die Ampeln („18/20"). Die
  zweite, gleichlautende Zeile darunter ist weg.
- **Eine Fahrt beginnt quer**, oder so, wie du es während der letzten Fahrt zuletzt
  eingestellt hast.
- **Der gemessene Schnitt gilt auch für die Zubringer zum Bahnhof** — dort aber nur, wenn er
  die vorsichtigere Zahl ist: wer den Zug verpasst, wartet zwanzig Minuten.
- **Einstellungen zu- und wieder aufmachen plant nicht mehr neu**, solange nichts geändert
  wurde. Eine volle Planung sind gut zwei Dutzend Anfragen.
- **Die Einstellungen unterscheiden die beiden Geschwindigkeiten**: „Rolltempo ohne Ampeln"
  (daraus rechnet die App jede Linie durch und entscheidet, welche die schnellste ist) und
  den gemessenen „Gesamtschnitt" Tür zu Tür (der entscheidet, wie lange es dauert). Beide
  gemessenen Werte stehen mit dem Satz daneben, wofür sie gelten.
- **Hilfetexte klappen zu**, sobald sie länger als zwei Zeilen sind. Tippen zeigt den Rest.
- **Weniger Anfragen, weniger Strom**: BRouter-Antworten werden zwischengespeichert (drei
  Anfragen je Planung gespart), die im Hintergrund geweckte App fragt nur noch die
  Kategorie, auf die der Countdown zählt (statt aller vier), Radarkacheln werden mit
  vernünftigem Rand statt mit zweieinviertelfacher Fläche geholt, und der Countdown tickt
  nicht mehr sekündlich, wenn es nichts zu zählen gibt.
- **Aus der Prüfrunde**: eine Zielzeit in der Vergangenheit ergibt keine Abfahrt in der
  Vergangenheit mehr; bei „Ankunft um …" gewinnt wieder die späteste Abfahrt statt der
  frühesten Ankunft; veraltete Ortungen (der Empfänger liefert beim Start gern eine alte)
  fließen nicht mehr in die Messung; ein Sprung des Empfängers kommt nicht mehr in die Linie
  und nicht ins Höhenprofil; eine abgebrochene Aufzeichnung behält ihre geplante Linie;
  Fahrtspuren und der OpenStreetMap-Korridor liegen jetzt mit Dateischutz auf der Platte;
  drei Erklärtexte, die seit 1.3 nicht mehr stimmten, stimmen wieder.

## 1.3 (Build 36) — elf Funde von der Testfahrt

- **Die Karte zeigt den Weg, auf den die Pfeile zeigen.** Wird unterwegs neu geplant, stand
  bisher weiter die alte Linie da, während Pfeil und Abweichung längst gegen die neue
  rechneten. Die ursprüngliche Linie liegt ab der ersten Neuplanung dünn und grau daneben.
- **Abbiegepfeil grün und erst 250 m vor der Abbiegung**, Abweichung rot. Rot heißt auf
  diesem Bildschirm ab jetzt genau eine Sache: du bist neben der Route.
- **Während der Fahrt steht da, was noch kommt**: Reststrecke, Restzeit, Ankunftszeit und
  die Ampeln, die noch vor dir liegen. In der Leiste dieselbe Zahl statt des Countdowns —
  wann du losgehen sollst, ist beantwortet, sobald du fährst.
- **Die Ampelzeile zählt „gehalten von geplant"** und läuft sekündlich mit, solange du
  stehst. Auf der Karte liegen die Ampeln der Route als Punkte — und nur die.
- **Die App misst sich selbst nach.** Nach jeder Fahrt schreibt sie aus dem Median der
  letzten acht Radfahrten das rollende Tempo in die Einstellungen und aus den gelernten
  Ampeln die Wartezeit je Ampel, mit dem Anteil daneben, der sie erklärt: „an 38 % der
  Ampeln gehalten". Und **gibt es genug gemessene Fahrten, ist dein Schnitt die angezeigte
  Fahrzeit** — auch wenn er schneller ist als die Rechnung. Welche Linie die schnellste
  ist, entscheidet weiterhin die Rechnung.
- **In den Fahrten**: die geplante Linie dünn neben der gefahrenen, das Höhenprofil unter
  der Straßenart, und zwei Vergleiche — Ampeln und Schnitt gegen das, was angekündigt war.
- **„Sonstiges" war ein Fehler in der Zuordnung.** Eine Zeile der BRouter-Tabelle ist eine
  Strecke, keine Stelle — bis zu zwei Kilometer lang. Damit lagen 38 % der gefahrenen Meter
  zu weit von jedem Stützpunkt entfernt und zählten als „sonstiges", obwohl die Straße
  bekannt war.
- **Die Ausrichtung am Lenker bleibt am Lenker**: was du im Fahrtmodus wählst, gilt ab dann
  für jede Fahrt. Nach „Fahrt beenden" dreht sich die App wieder wie jede andere.
- **Gelernte Ampeln rechnen mit ihrer gemessenen Zeit** statt mit dem Pauschalwert, und jede
  Aufzeichnung zählt dafür auch, wo sie ohne Halt durchgekommen ist. Vorher wuchs die
  geplante Radzeit mit jeder Fahrt, weil jede neue Ampeln lernte und keine je billiger
  wurde. Der erste und der letzte Stillstand einer Fahrt sind dabei keine Ampel mehr — das
  ist die eigene Haustür, nicht eine Kreuzung. Und die Detailseite schreibt die Ampelzeit
  neben die Ampelzahl, damit die Fahrzeit nachrechenbar ist.

## 1.3 (Build 35) — weniger, dafür deutlicher

- **Keine namenlosen „Alternative"-Kästen mehr.** Drei- bis fünfmal „Alternative"
  untereinander sagt nichts, und jede davon kostete eine Anfrage.
- **Neu: „Möglichkeiten je Verkehrsmittel" (1–3).** Begrenzt nicht nur die Anzeige,
  sondern das Rechnen: statt neun BRouter-Anfragen sind es voreingestellt vier.
- **Voreingestellte Reihenfolge ist jetzt optimal › schnellst › kürzest.** „wenig Autos"
  und „wenig Halts" stehen dahinter; wer sie sehen will, zieht sie in den Einstellungen
  nach oben. Genau deshalb waren sie zuletzt verschwunden.
- **Die Einstellungen stehen auf vier Seiten** statt auf einer mit sechzehn Abschnitten:
  Adressen, Navigation, Verkehrsmittel, Einstellungen.
- **Die Detailseite**: größere Karte, vor und zurück innerhalb der Kategorie, die Liste
  der gequerten Hauptstraßen eingeklappt, und kein Zeitstrahl mehr, wo er nur wiederholt,
  was zwei Zeilen höher steht.
- **Wenn die Linien nicht in die iCloud kommen, steht das jetzt in der Fahrtenliste** —
  mit dem Grund. Vorher war es folgenlos und unsichtbar zugleich.

## 1.3 (Build 33) — vier Funde von der Heimfahrt

- **Im Fahrtmodus bleibt der Bildschirm an**, bis du die Fahrt beendest. Vorher ging er
  aus, obwohl der Schalter „Bildschirm anlassen" an war: das Flag gilt nur, solange die
  App vorn ist, und auf einer Fahrt kommt sie dauernd aus dem Hintergrund zurück. Den
  Schalter gibt es nicht mehr — ein Blick auf die Karte an der Kreuzung nützt nichts,
  wenn man vorher entsperren muss. Das kostet Strom und ist so gewollt.
- **Die Karte bleibt beim Verlassen der Route in Fahrtrichtung gedreht.** In Build 31/32
  stellte sie sich dabei auf Norden — falsch: eine Karte, die sich dreht, wenn man falsch
  fährt, ist genau dann unlesbar, wenn man sie braucht.
- **Neu berechnet wird ab 200 m statt ab einem Kilometer**, und einstellbar: „Neu
  berechnen ab" (Entfernung) und „… oder nach" (Minuten daneben) — was zuerst eintritt.
  Die Entfernung greift erst nach fünfzehn Sekunden am Stück, damit ein Bogen um eine
  Baustelle keine Neuplanung auslöst; die Zeit greift unabhängig davon, für den Fall, dass
  man im Kreis um einen gesperrten Weg fährt.
- **Die Fahrtansicht zeigt, wie lange insgesamt gestanden wurde** — neben der Zeit an den
  Ampeln, nicht statt ihrer, und im Sekundentakt mitlaufend.

## 1.3 (Build 32) — die Ampeln kommen zurück

**OpenStreetMap wird jetzt entlang der Route gefragt, nicht im umschließenden Kasten.**
Bei einer diagonalen Pendelstrecke war der Kasten halb Berlin. Gemessen an 20 km quer
durch Berlin: **287 kB statt 3,6 MB**, 1 410 statt 18 238 Elemente. Genau daran war die
Abfrage auf dem Gerät gescheitert — der Dienst brach sie mit einem Zeitfehler ab, und
ohne sie fehlten die Ampelzahl, die Straßenarten und jede Bewertung nach „ruhigst" oder
„verkehrsarm".

- **Scheitert sie trotzdem, läuft ein zweiter Versuch in Ruhe im Hintergrund** und füllt
  den Zwischenspeicher; der hält 30 Tage, der nächste Plan hat die Daten dann. Die Notiz
  sagt das auch.
- Der Zwischenspeicher prüft jetzt, ob das Gespeicherte die neue Strecke wirklich abdeckt —
  sonst hätten Ampeln gefehlt, ohne dass es auffällt.

## 1.3 (Build 31) — mehr Radrouten, und die Karte zeigt gleich etwas

- **Jede gefundene Radroute bleibt wählbar.** Bisher wurden fünf Rollen vergeben —
  schnellst, kürzest, optimal, ruhigst, verkehrsarm — und eine Linie, die keine davon
  gewann, fiel heraus. Auf einer Stadtstrecke ist oft dieselbe Linie die schnellste *und*
  die ruhigste; dann blieben von fünf Wegen zwei Kästen übrig. Jetzt steht jede übrige
  Linie als „Alternative" daneben. Gleiche Linien, die mehrere Profile zurückgeben, zählen
  vorher als eine.
- **Die Karte zeigt von Anfang an Start und Ziel**, statt in den ersten Sekunden auf halb
  Europa zu stehen.
- **Der Straßenbalken auf der Hauptseite ist dünner.**

Aus Build 30, für alle, die ihn übersprungen haben: die Kästen füllen sich der Reihe nach
in der Reihenfolge aus den Einstellungen, Höhenmeter zählen in die Fahrzeit, das
Regenradar ist geglättet, und der Straßenbalken steht auch auf der Hauptseite.

## 1.3 (Build 30) — Reihenfolge, Höhenmeter, weicheres Radar

- **Die Kästen füllen sich der Reihe nach.** Bisher stand der ganze Bildschirm auf
  „sucht …", bis der langsamste der vier Dienste geantwortet hatte. Gefragt wird weiter
  alles gleichzeitig; was da ist, steht jetzt sofort da. Die Reihenfolge ist die aus den
  Einstellungen — dieselbe Liste, die schon die Kästen anordnet.
- **Geöffnet ist der erste Kasten deiner Reihenfolge, nicht der empfohlene.** Wer das Rad
  nach oben gestellt hat, sieht die Radroute und nicht Rad + Bahn, nur weil die zwei
  Minuten früher ankommt. Der Stern sagt weiterhin, was die App für die bessere Wahl hält.
- **Höhenmeter zählen mit.** Jede Radroute zeigt ihren Anstieg, und er geht in die
  Fahrzeit ein: fünf Sekunden je Meter, also 720 Höhenmeter in der Stunde. Bei gleicher
  Länge gewinnt damit die flachere Strecke — ein halber Kilometer Umweg schlägt
  115 Höhenmeter. Bergab wird nichts gutgeschrieben; die Zeit holt man nicht wieder herein.
- **Der Straßenbalken steht auch auf der Hauptseite**, unten in der Streckenbox, ohne
  Legende. Die Kilometer je Straßenart bleiben im Detail.
- **Das Regenradar sieht aus wie ein Feld, nicht wie ein Schachbrett.** Der DWD misst in
  1-km-Zellen und malt sie als Rechtecke aus; auf Pendelstrecken-Zoom ist eine Zelle
  26 Pixel breit. Sie werden jetzt geglättet — über den Kachelrand hinaus, damit keine
  Nähte entstehen.
- **Radrouten: höchstens drei Anfragen gleichzeitig**, und wenn der Routendienst nicht
  antwortet, steht das jetzt da. Vorher verschwanden die Varianten stillschweigend und es
  blieb eine statt fünf.

## 1.3 (Build 28) — der Hänger ist gefunden

**Ursache der Hänger: ein `TimelineView` in einer `ToolbarItem`.** Unter iOS 26 legt jeder
Takt die Navigationsleiste neu aus, und dieses Auslegen macht den Ansichtsgraphen erneut
schmutzig — worauf er sofort den nächsten Durchlauf anfordert. Die App lief dauerhaft mit
voller Bildrate durch, ohne dass sich etwas änderte. Leerlauf-CPU im Simulator, Release:
**70–85 % vorher, 0 % nachher.** Auf dem Gerät war das der Stromverbrauch, die drei
Sekunden pro Berührung und am Ende der `scene-update`-Watchdog.

Der Fehler steckte in 1.0, 1.1 und 1.2 gleichermaßen — es gibt ihn, seit es den Countdown
gibt. Build 23 war nie heil, Build 27 ist codegleich und war es ebenso wenig, das iPad
zeigte dasselbe, und keine Neuinstallation konnte je helfen. Der Countdown bekommt jetzt
eine eigene Uhr: ein `@State` und ein `.task`, das einmal die Sekunde schreibt. Tickt
genauso, löst aber kein Auslegen der Leiste aus.

**Neu: neben der Route weist ein Pfeil den Weg zurück.** Wer eine Abbiegung verpasst oder
bewusst anders fährt, bekam bisher weiter Abbiegehinweise für eine Straße, auf der er
nicht mehr ist. Jetzt tritt ein Pfeil an ihre Stelle — dorthin, wo die Route liegt, mit
dem Abstand daneben —, die Karte geht heraus, bis beides im Bild ist, und steht dabei nach
Norden. Über einem Kilometer daneben wird der Weg zum Ziel von der aktuellen Position aus
neu berechnet, höchstens einmal die Minute.

**Neu: die Warnungen stimmen auch, während die App zu ist.** Sie standen fest, sobald ein
Plan da war — fuhr der Zug danach fünf Minuten später, klingelte es fünf Minuten zu früh.
iOS weckt die App jetzt gelegentlich, und sie stellt dieselbe Frage noch einmal: dieselbe
Kategorie, dieselbe Abfahrt oder Ankunft.

**Die Linien der Fahrten können reisen.** Bisher reisten nur die Zahlen einer Fahrt; unter
einer auf dem iPhone aufgezeichneten Fahrt stand auf dem iPad „nicht auf diesem Gerät".
Der Weg über CloudKit ist gebaut und wird eingeschaltet, sobald der iCloud-Container steht.

Dazu, unsichtbar, aber auf demselben Weg — dem Hauptthread beim Start:

- Der iCloud-Abgleich rechnet nicht mehr auf dem Hauptthread (zlib, JSON, und ein
  Vergleich jeder gelernten Ampel mit jeder).
- Die Einstellungen melden nur noch Änderungen, die welche sind. Vorher waren es dreißig
  gemeldete Änderungen je Rückmeldung aus iCloud — und damit der halbe Bildschirm samt
  Karte.
- Was das Zusammenführen zweier Geräte dazugewinnt, geht jetzt auch wirklich hinaus; das
  tat es bisher nie.
- Eine abgebrochene Aufzeichnung wird erst gelöscht und dann ausgepackt. Stirbt die App am
  Auspacken, fand der nächste Start bisher dieselbe Datei wieder — eine Startschleife, aus
  der nur das Löschen der App führte.

## 1.2 (Build 26) — zwei Funde, ein Messgerät
Build 25 war **nicht** die Lösung: die App hängt weiter, und der zweite Absturzbericht
zeigt denselben `scene-update`-Watchdog — über zehn Sekunden in *einem* SwiftUI-Layoutlauf,
beide Male beim Wechsel in den Hintergrund. Was hier drin ist:

- **Die Detailspalte steht wieder nur auf dem iPad.** In 1.2 füllte sie auch die
  Querformatspalte des Telefons — das sah aufgeräumter aus und kostete Sekunden: der ganze
  Zeitstrahl, in eine 360-Punkt-Spalte auf einem knapp 390 Punkte hohen Bildschirm, in
  einem Durchlauf. Gemessen 0,4 s hochkant gegen 5,3 s quer; nach dem Rückbau 0,44 s.
  Quer dreht man das Telefon ohnehin wegen der Karte.
- **Der Analysebalken wird gezeichnet statt gelegt.** Ein `GeometryReader` liest die Breite
  und gibt sie seinen Kindern als feste Breite zurück — in einer scrollenden Spalte eine
  Größenverhandlung, die SwiftUI jedes Mal ausrechnen muss. Ein `Canvas` nimmt, was er
  bekommt, und malt.
- **Der Countdown-Terminplan hält sich an seinen Vertrag.** Seine erste Marke war `start`
  selbst, also „jetzt".
- **Neu und vorübergehend: ein Hänger-Zähler.** Ein Timer misst, wie spät der Hauptthread
  drankommt; was über eine halbe Sekunde geht, wird gezählt. Steht etwas an, erscheint im
  Menü unten eine orange Zeile: „3 Hänger, längster 12,4 s". Absichtlich auch im
  ausgelieferten Build — ein Hänger, der nur auf einem bestimmten Telefon auftritt, ist im
  Simulator nicht zu finden; das hat diese Runde zweimal bewiesen.

**Was weiterhin offen ist:** die Ursache der Hänger. Die Dauerlast, der ich zuerst
nachgegangen bin, steckt nachweislich schon in 1.1 und ist es nicht.

## 1.2 (Build 25, zurückgezogen) — Notbremse für Build 24
**Build 24 nicht benutzen.** Er wurde von Minute zu Minute langsamer, das Kartenfenster
schrumpfte dabei, und am Ende stürzte die App ab. Ursache war ein Fehler aus derselben
Runde: um MapKits Kompass unter dem neuen Abbiegeband wegzuschieben, setzte die App die
`layoutMargins` der Karte — und weil `insetsLayoutMarginsFromSafeArea` voreingestellt an
ist, liest sich der Wert nie so zurück, wie er gesetzt wurde. Also wurde bei *jedem*
Neuzeichnen verglichen, für ungleich befunden und neu gesetzt: eine Rückkopplung, die
die Karte jedes Mal neu auslegte und ihre Fläche ein Stück kleiner machte, bis der
Watchdog die App beendete.

Der Kompass wird jetzt einfach ausgeblendet, solange das Abbiegeband oben steht — das
Band sagt, wo es langgeht, und der Pfeil, wohin man zeigt. An `layoutMargins` fasst die
App nicht mehr.

Nachgemessen im Simulator: Kartenfenster über 90 Sekunden und sechs Wechsel unverändert
370 × 414, ein Boxenwechsel dauert 0,4 statt 3 Sekunden.

## 1.2 (Build 24, zurückgezogen) — nach der ersten Testfahrt
Punkte aus der Praxis, nicht aus dem Simulator.

**Der Grund, warum die App geruckelt und Strom gezogen hat, war ein Buchhaltungsfehler beim Regenradar.** Es hängte nach jedem Neuzeichnen alle 22 Kachelebenen wieder an die Karte, nachdem es 19 davon gerade abgeräumt hatte — hunderte Kachelanfragen pro Sekunde, für Bilder, die niemand ansah. Das erklärt beides auf einmal: das Stocken beim Schieben der Karte *und* dass sogar das Einstellen der Uhrzeit hakte, auf einem Bildschirm, hinter dem nur die Karte lag. Ein Test hält jetzt fest, dass die Buchhaltung zur Ruhe kommt: zweimal hintereinander gefragt, passiert nichts mehr.

- **Weniger Aktualisierungen, weniger Strom.** Radarkacheln der Nachbarminuten werden nur noch beim Abspielen vorgehalten, nicht im Stehen. Der Countdown tickt im Sekundentakt nur unter zehn Minuten, wo Sekunden zu sehen sind — darüber alle 20 Sekunden. Die Fahrtansicht lässt nur noch Uhr und Tempo sekündlich laufen statt der ganzen Seite samt Karte. Die Ortung läuft auf `Best` statt `BestForNavigation` (letzteres ist für Abbiegenavigation gedacht und der teuerste Modus, den es gibt). An die Uhr gehen die Zahlen alle zwei statt jede Sekunde.
- **Neu: „Bildschirm anlassen"**, voreingestellt **aus**. Bisher blieb der Bildschirm die ganze Fahrt an — am Lenker richtig, in der Tasche der größte Stromfresser überhaupt. Aufgezeichnet wird auch mit dunklem Bildschirm.
- **Die gefahrene Linie wird geglättet eingefärbt.** Bei konstant 20 km/h meldet der Empfänger abwechselnd 19,8 und 20,1 — daraus wurden hunderte Zwei-Punkt-Linien, jede eine eigene Ebene, die MapKit unter dem Daumen zeichnen musste. Jetzt erst, wenn das Tempo deutlich in der nächsten Stufe liegt.
- **Der Abbiegehinweis wird je Ortung berechnet, nicht je Bild.** Vorher lief bei jedem Neuzeichnen eine Suche über die ganze Route samt neuer Längentabelle.

### Analysebalken: worauf gefahren wird
- **Neu: ein Balken je Radroute und je gefahrener Fahrt**, der zeigt, wie viele Kilometer auf **Hauptstraße, Nebenstraße, Radweg, Weg, Fußweg** liegen. Die Angaben kommen aus BRouters eigenen Segmentdaten, die mit jeder Route ohnehin mitgeliefert werden — keine neue Quelle, kein Schlüssel, keine zusätzliche Anfrage.
- Ein Fußweg mit `bicycle=designated` zählt als Radweg, und eine Hauptstraße mit eigenem Radweg daneben auch — unter dem Rad ist das ein Radweg. Eine Radspur auf der Fahrbahn nicht.
- Bei einer gefahrenen Fahrt wird die tatsächlich gefahrene Strecke der geplanten Linie zugeordnet. Was mehr als 60 m daneben liegt, heißt „sonstiges" — so sieht ein Umweg aus, und so soll er aussehen.

- **Der Pfeil zeigt immer in Fahrtrichtung.** Vorher zeigte er doppelt daneben: die Karte dreht sich beim Folgen selbst in den Kurs, und der Pfeil drehte noch einmal denselben Winkel obendrauf. Jetzt ist es der Kurs **minus** der Blickrichtung der Karte. Meldet der Empfänger im Stand keinen Kurs — das tut er nie —, bleibt der letzte stehen; gab es noch nie einen, kommt er aus der gefahrenen Linie.
- **Nach Zoomen oder Schieben kommt die Karte von selbst zurück**, 30 Sekunden nach der letzten Berührung. Der Knopf oben links schaltet das Folgen weiterhin von Hand um.
- **Ausrichtung festhalten.** Ein Knopf auf der Fahrtansicht schaltet automatisch › hochkant › querformat; dieselbe Einstellung steht unter *Fahrt aufzeichnen*. Am Lenker ist eine Karte, die sich in der Kurve selbst dreht, keine Hilfe.
- **Abbiegehinweise.** Ganz oben ein rotes Band mit großem Pfeil: was kommt und in wie vielen Metern. Die Kurven rechnet die App aus der gezeichneten Linie selbst aus — kein zusätzlicher Dienst, keine Straßennamen, keine Ansage. Die Route dafür wird **beim Start der Fahrt festgehalten**, damit eine Neuplanung unterwegs den Pfeil nicht auf eine Straße zeigen lässt, auf der man nicht ist.
- **Ein Stillstand ab 30 Sekunden ist eine Ampel**, auch wenn keine Karte dort eine kennt. Die Schwelle steht in den Einstellungen.
- **Die aktuelle Geschwindigkeit ist jetzt die große Zahl** auf der Fahrtansicht — in der Farbe, in der die Linie gerade gezeichnet wird. Schnitt und Strecke stehen klein daneben.
- **Die App merkt sich, wo du stehst.** Jede gezählte Ampel wird als Ort behalten, mit Anzahl und Wartezeit, und ab der nächsten Fahrt mitgerechnet: beim Erkennen eines Halts **und** in der Ampelzahl einer Radroute, also in ihrer Fahrzeit. Zwei Geräte führen ihre Listen zusammen. In den Einstellungen stehen sie mit Zähler und lassen sich vergessen.
- **Doppeltipp auf die Adressbox setzt die Pendelstrecke ein**: aktueller Standort als Start, Zuhause oder Arbeit als Ziel. Was von beidem, entscheidet der Ort — am Zuhause geht es zur Arbeit, an der Arbeit nach Hause —, und wenn keines in der Nähe ist, die Uhr.
- **Ampeln und Halte sind auf der Karte einer gefahrenen Fahrt deutlich markiert**: gelb mit Ampelzeichen und Wartezeit, alles andere klein und grau.
- **Neue Radvariante „verkehrsarm"** neben „ruhigst", und die beiden fragen jetzt wirklich Verschiedenes: „ruhigst" die geringste Störung insgesamt, „verkehrsarm" die **wenigsten Stellen, an denen der Verkehr zum Anhalten zwingt** — Ampeln und gequerte Hauptstraßen —, mit den Metern neben Hauptstraßen nur als Gleichstandsregel. Damit auch etwas zur Auswahl steht, fragt die App jetzt zwei `fastbike-lowtraffic`-Varianten **und** BRouters `shortest`-Profil zusätzlich ab; vorher war „kürzest" immer eine der Strecken, die schon etwas anderes gewonnen hatte.
- **Ampeln sind schon während der Fahrt auf der Karte** zu sehen, nicht erst hinterher: die der geplanten Route und die selbst gelernten.

## 1.1 (Build 23, TestFlight 2026-09-23)
- **Querformat.** Gedreht steht die App zweispaltig wie auf dem iPad: Kopfzeile, Boxen und Fahrtzeile links in einer 360 Punkte breiten Spalte, die Karte rechts über die ganze Höhe. Die Detailspalte des iPads kommt mit: sie füllt, was sonst ein leeres Drittel der Spalte wäre, und scrollt, wo sie nicht passt.
- **Fahrt aufzeichnen.** Der Knopf rechts neben der gewählten Fahrt startet die Aufzeichnung; die Karte nimmt die ganze Seite, folgt dir und zeichnet den gefahrenen Weg **nach Geschwindigkeit eingefärbt** (fünf Stufen, rot unter 8 bis grün über 26 km/h, mit Skala in der Ecke). Uhr, Ø-Tempo, aktuelles Tempo und Strecke stehen darunter. Ein Wisch über die Karte löst das Folgen, der Knopf oben links schaltet es wieder ein.
- **Ampelhalts werden gezählt.** Stillstand ab fünf Sekunden ist ein Halt; liegt er im Umkreis von 45 m um eine Ampelkreuzung der **geplanten** Route, ist es ein Ampelhalt mit Wartezeit, sonst ein gewöhnlicher Halt. Die Kreuzungen werden beim Start der Fahrt festgehalten — eine Neuplanung unterwegs kann die Antwort nachträglich nicht mehr ändern.
- Gemessen wird mit Hysterese (unter 1,0 m/s steht man, erst über 1,8 m/s fährt man wieder), damit langsames Rollen nicht jeden Pedaltritt zu einem Halt macht. Strecke wächst **nur in Bewegung**, sonst wandert man im Stand die Straße hinunter; Sprünge des Empfängers, Fixes über 50 m Ungenauigkeit und Lücken über 30 s zählen nicht als gefahrener Weg.
- **Menü → Fahrten.** Alle Aufzeichnungen, nach Jahren und Monaten gruppiert, neueste zuerst; die Monatsüberschrift trägt Kilometer, Schnitt und Ampelhalts des Monats. Eine Fahrt zeigt die gefahrene Linie, jede gemessene Zahl und die längsten Halte — dazu, ob sie schneller oder langsamer war als der Plan versprochen hat.
- **Die Kennzahlen jeder Fahrt reisen durch deine iCloud**, im selben Schlüssel-Wert-Speicher wie die Einstellungen, zlib-komprimiert und als Vereinigung beider Geräte zusammengeführt — was ein Gerät noch nicht gesehen hat, kann es nicht löschen. **Die gefahrene Linie bleibt auf dem Gerät, auf dem sie entstanden ist**: der Speicher fasst 1 MB für die ganze App, eine Linie allein ist achtzig Kilobyte. Die Liste ist also überall vollständig, die Karte einer fremden Fahrt sagt, wo sie liegt. Ohne iCloud-Konto bleibt alles lokal, wie bei den Einstellungen auch. (Ein echter CloudKit-Abgleich samt Linien kommt nach, sobald der iCloud-Container im Entwicklerkonto steht — er lässt sich nur von Hand anlegen.)
- **Auf der Uhr** gibt es während der Fahrt eine eigene erste Seite: laufende Uhr, Ø- und aktuelles Tempo, Ampelhalts mit Gesamt- und Durchschnittswartezeit, Rollzeit und Standzeit. Nach der Ankunft bleibt dieselbe Seite eine Stunde lang als Zusammenfassung stehen. Die Uhr rechnet weiterhin **nichts** selbst; verliert sie den Kontakt, schreibt sie das Alter der Zahlen dazu.
- Eine Fahrt, die die App nicht überlebt (Absturz, vom System beendet), wird alle 30 Sekunden mitgeschrieben und beim nächsten Start als das abgelegt, was sie war.
- **Ortung im Hintergrund** — neu und ausdrücklich erlaubt (Nutzer, 23.09.2026). Sie läuft **ausschließlich** zwischen „Fahrt“ und „Fahrt beenden“, iOS zeigt solange die blaue Leiste, danach schaltet die App den Modus selbst wieder ab. Alles andere bleibt wie es war: „Mein Standort“ ist weiterhin ein einzelner Fix auf Tippen. **Datenschutz-Fragebogen und Datenschutzerklärung müssen vor dem nächsten Upload nachgezogen werden.**

## 1.0 (Build 22, TestFlight 2026-09-22)
- **Version 1.0.** Eine 0.x im Store liest sich wie eine Beta.
- **Ein Tipp auf Start oder Ziel bricht die laufende Berechnung ab.** Bei einer weiten Strecke wartete man vorher Sekunden auf einen Plan, den man gerade wegwerfen wollte. Die Abbrüche laufen bis in die Netzverbindungen durch.
- **Auf der Uhr führt die Wahl eines Weges zurück zum Countdown**, statt in der Liste stecken zu bleiben — und die Wahl bleibt nicht auf der Uhr: **das iPhone übernimmt sie**. Erreichbar per Nachricht, sonst als Übertragung nachgereicht. Gemerkt wird Kategorie plus Position, nicht die id, damit die Wahl eine Neuplanung überlebt.
- Im Menü stehen die Quellen wieder **nur als Namen**; die anklickbaren Links stehen in den Einstellungen, wo sie nach Links aussehen dürfen.
- Store-Texte deutsch und englisch auf denselben Stand.

## 0.14.0 (Build 21, TestFlight 2026-09-22)
- **Der Countdown lässt sich abschalten.** Ein Tipp auf die Pille stellt ihn aus: grau, „aus", durchgestrichene Glocke — und die Mitteilungen werden mit abbestellt. Nochmal tippen schaltet ihn wieder an. Sobald eine **andere** Abfahrt gilt, gilt das Nein nicht mehr, denn eine neue Abfahrt ist eine neue Frage.
- **Die Pille ist jetzt immer da**, auch bei Rad und Auto ohne feste Abfahrt — dort grau statt weg, damit die Titelzeile nicht springt.
- **Das Auto zeigt alle Linien, die Apple anbietet**, nicht nur die schnellste. Neue Variante **„optimal"** wie beim Rad (Fahrzeit plus die Wartezeit an den Ampeln), dazu schnellst, kürzest und wenig Ampeln; eine Linie ohne eigene Rolle heißt „Alternative" und wird trotzdem gezeigt. Vorbelegt ist „optimal" zuerst. Linien, die sich um weniger als 100 m und eine Minute unterscheiden, gelten als dieselbe.
- **„Mein Standort" steht jetzt im Suchfeld.** Öffnet man die Startadresse ohne gesetzten Start und mit erteilter Ortungserlaubnis, steht die aktuelle Adresse gleich im Feld — zum Übernehmen oder Überschreiben. Die Standortzeile bleibt oben stehen, auch während getippt wird.

## 0.13.0 (in Build 21 ausgeliefert)
- **„Mein Standort" als Startadresse.** Die Adresssuche für den Start beginnt jetzt mit einem Vorschlag: dort, wo du gerade bist. Steht schon eine Erlaubnis, wird die Adresse gleich beim Öffnen aufgelöst und steht mit Straße und PLZ in der Zeile — ein Tipp genügt. Ohne Erlaubnis fragt der erste Tipp danach; wird sie abgelehnt, verschwindet die Zeile und alles andere funktioniert weiter.
- Der Standort wird **einmal** abgefragt, in eine Adresse übersetzt und danach vergessen: kein Mitschreiben, kein Hintergrundzugriff, keine Bewegungsverfolgung. Die Koordinate geht danach denselben Weg wie jede getippte Adresse — an die Routing- und Fahrplandienste, an sonst niemanden.
- „Zuhause" und „Arbeit" in den Einstellungen bekommen denselben Vorschlag.

## 0.12.1 (in Build 21 ausgeliefert)
- Im Menü dritte Zeile beim Copyright: **„inspired by Oleg"**.
- Die Datenquellen sind jetzt **wirklich kursiv**. Vorher nicht: SF Rounded hat keinen kursiven Schnitt, und weder SwiftUI noch der Renderer erfinden einen — `.italic()` blieb wirkungslos. Die zwei Zeilen stehen deshalb im normalen Systemschnitt, gleiche Größe wie das Copyright.
- **Die Quellenangaben sind anklickbare Links** — `transitous.org/sources` und `openstreetmap.org/copyright`, unterstrichen, in der Akzentfarbe, mit Pfeil. Vorher standen sie in derselben grauen Schrift wie der Rest und sahen nach Text aus. Dieselben zwei Links stehen in den Einstellungen unter „Fahrplanquelle".

## 0.12.0 (Build 18, TestFlight 2026-09-22)
- **Bundesweite Fahrpläne über Transitous.** Neben dem VBB kennt die App jetzt Transitous, die von Freiwilligen betriebene MOTIS-Instanz auf dem bundesweiten DELFI-Datensatz (und darüber hinaus). Neue Einstellung **Fahrplanquelle**: „Automatisch" fragt den VBB, solange Start *und* Ziel in Berlin/Brandenburg liegen — dort ist er genauer und sagt als Einziger je Zug, ob Räder mitdürfen — und Transitous für alles andere. „VBB" und „Transitous" lassen sich auch fest wählen.
- **Rad + Bahn über beliebige Entfernungen**: Transitous plant intermodal, also Rad zum Bahnhof, Zug, Rad weiter — in *einer* Anfrage. Die App muss sich die Bahnhöfe nicht mehr selbst suchen (beim VBB tut sie das weiter, mit 16 Abfragen je Durchlauf). Probe Berlin → Hamburg: Rad, S5, Umstieg, ICE, Rad.
- Fahrradmitnahme aus GTFS wird **nie als Nein gelesen**: die meisten Datensätze lassen `bikes_allowed` auf der Voreinstellung stehen. Ein „nein" kommt weiter nur aus deiner Linienliste; alles andere ist „ungeklärt" und wird als solches gezeigt.
- Gleisangaben werden auch aus dem Klartext gelesen („S-Bahnsteig Gleis 4"), wenn der Datensatz kein eigenes Feld dafür hat.
- Attribution, wie die Nutzungsbedingungen es verlangen: Link auf die Quellen von Transitous im Menü und in den Einstellungen, und jede Anfrage trägt einen `User-Agent` mit Name, Version und Kontakt.

## 0.11.0 (in Build 18 ausgeliefert)
- **Zuhause und Arbeit** sind jetzt richtige Adressen in den Einstellungen, jede über die Adresssuche wählbar. Beide bekommen überall ein Zeichen — in der Kopfzeile der Hauptseite, in der Adresssuche und in der Liste der benutzten Adressen — und stehen in der Suche ganz oben.
- **Fahrradmitnahme pro Linie**: eine neue Liste in den Einstellungen sammelt die Linien, die in gefundenen Verbindungen vorkommen. Was die Auskunft selbst zusichert (VBB-Vermerk `FK`), steht schon auf „Rad ja"; alles andere entscheidest du — ja, nein oder offen. Linien lassen sich auch von Hand eintragen. **Offene Linien werden nicht mehr verschwiegen**: die Verbindung wird vorgeschlagen und trägt den Hinweis „Mitnahme ungeklärt", bis du entschieden hast. Ein „Rad nein" nimmt die Linie aus den Rad + Bahn-Vorschlägen heraus.
- Das Scrollen in den Einstellungen ruckelte: der iCloud-Abgleich schrieb bei **jeder** Änderung an den Systemeinstellungen den ganzen Satz neu und flusht ihn auf Platte. Jetzt wird nur geschrieben, was sich wirklich geändert hat, und das außerhalb des Hauptthreads.
- Das Menü ist ein eigenes kleines Fenster statt eines iOS-Menüs: Version und Copyright klein auf getrennten Zeilen, die Quellen als „Datenquellen:" ebenso klein und kursiv.
- **Das Projekt ist quelloffen** (MIT) — Voraussetzung für die kommende Anbindung von Transitous/MOTIS. Die Testdaten wurden dafür auf neutrale Adressen gebracht, die App selbst enthielt noch nie welche.

## 0.10.1 (in Build 18 ausgeliefert)
- Das Burger-Menü ist jetzt ein eigenes kleines Fenster statt eines iOS-Menüs: Version und Copyright stehen klein und **auf getrennten Zeilen**, die Quellen heißen **„Datenquellen:"** und stehen ebenso klein und **kursiv** darunter. Ein iOS-Menü zeichnet nur einfachen Text in einer Größe — deshalb der Wechsel.

## 0.10.0 (Build 16, TestFlight 2026-09-21)
- **Vorlieben einstellbar** (Einstellungen, gleich unter den Adressen). Dein bisheriges Verhalten ist überall die Voreinstellung:
  - **Verkehrsmittel** als Liste zum Ziehen — Rad › Rad + Bahn › Auto › Bahn & Bus. Die Reihenfolge entscheidet, was gewinnt, wenn zwei Fahrten innerhalb von drei Minuten ankommen, sie bestimmt die Reihenfolge der vier Kästen und die Reihenfolge, in der die Empfehlung durchprobiert, wenn keine Verbindung mit Radmitnahme da ist.
  - **Radrouten** als Liste — optimal › schnellst › ruhigst › kürzest. Die oberste ist die, die vorgeschlagen und im Kasten genannt wird; „weniger Ampeln vor kürzest" ist damit ein Zug mit dem Finger.
  - **Autorouten** genauso — schnellst › kürzest › wenig Ampeln.
  - **„Rad in die Bahn ab"** — bisher fest bei leichtem Regen, jetzt wählbar zwischen „Schauer möglich" und „starker Regen".
  - **„Zurück auf Werkseinstellung"** stellt alle vier auf den Auslieferungszustand.
- **Lange Strecken**: jenseits von 100 km rutscht die reine Fahrrad-Option ans Ende der Kästenreihe, und die Ampelzählung wird übersprungen, statt Overpass nach einem Korridor zu fragen, den es nicht beantworten kann. Voll relevant wird das erst mit bundesweiten Fahrplandaten — bis dahin verhindert es vor allem ein Hängen bei weit entfernten Zielen.

## 0.9.0 (Build 15, TestFlight 2026-09-21)
- **Abgleich über iCloud**: Start, Ziel, Arbeitsadresse, Fixpunkte, die Liste der benutzten Adressen und alle Einstellungen wandern über den iCloud-Schlüssel-Wert-Speicher zwischen deinen Geräten — das iPad startet also mit dem, was das iPhone schon weiß. Ohne angemeldetes iCloud-Konto passiert nichts und die App verhält sich wie vorher. Die Adressliste wird dabei **zusammengeführt**, nicht überschrieben (je Adresse der höhere Zähler und die spätere Benutzung), damit ein Gerät, das gerade erst gezogen hat, die Liste nicht kürzen kann. Der Fahrplan selbst geht weiter direkt per WatchConnectivity an die Uhr — er ist nach Minuten veraltet, dafür ist iCloud zu langsam.
- **Benutzte Adressen merken**: jede gewählte Adresse landet in einer Liste auf dem Gerät. Die Adresssuche zeigt sie unter „Schon benutzt" noch bevor etwas getippt ist — **nach Häufigkeit sortiert**, bei Gleichstand die zuletzt benutzte zuerst, mit der Zahl der Benutzungen rechts. Tippen übernimmt sie sofort (kein zweiter Geocoder-Aufruf), Wischen vergisst sie. Beim Tippen wird die Liste mitgefiltert (ohne Rücksicht auf Groß/klein und Umlaute) und steht über den Vorschlägen von Apple. Maximal 40 Einträge, danach fallen die am seltensten benutzten heraus.
- **Adressen mit Postleitzahl**: PLZ und Ort stehen jetzt überall neben bzw. unter der Straße — in der Kopfzeile klein hinter dem Straßennamen, in der Suche und in den Einstellungen als eigene Zeile. PLZ und Ort werden beim Wählen als eigene Felder gespeichert; für Adressen aus älteren Versionen werden sie aus dem gespeicherten Namen gelesen.

## 0.8.0 (Build 14, TestFlight 2026-09-21)
- **iPad**: die App ist jetzt universal und läuft im Vollbild (kein iPadOS-Fenster). Ab regulärer Breite steht alles nebeneinander — links eine Spalte mit Adressen, Zeitwahl, den vier Modus-Boxen und der Fahrtzeile, rechts die Karte über die ganze Höhe. **Alle Streckendetails stehen auf derselben Seite**: Begründung der Empfehlung, Regen- und Umstiegs-Hinweise, die Rad- bzw. Autoroutenkarte mit Ampeln und Querungen und der komplette Zeitstrahl — auf dem iPad ist nichts mehr hinter einem Tipp versteckt.
- **Apple Watch**: eine eigene watchOS-App (watchOS 10+), die in der iPhone-App mitgeliefert wird. Drei Seiten, vertikal gewischt:
  - **Countdown** in derselben Ampelfarbe wie auf dem iPhone, mit Linie und Abfahrt → Ankunft. Ohne feste Abfahrt bleibt er grau statt rot zu blinken.
  - **Fahrt** mit allen Abschnitten, Zeiten, Linien und Kilometern.
  - **Wie?** — die vier Kategorien Fahrrad, Rad + Bahn, Auto, Bahn & Bus mit ihrer besten Zeit und der Zahl der Wege; eine Kategorie öffnen, einen Weg antippen, und der Countdown zählt auf diesen. „Vorschlag des iPhones" stellt die Auswahl zurück.
  - Die Uhr **plant nichts selbst**: sie bekommt den fertigen Plan vom iPhone (WatchConnectivity, immer nur der neueste Stand) und legt ihn auf Platte — außer Reichweite steht der letzte bekannte Plan da, mit seinem Alter darunter.

## 0.7.0 (Build 13, TestFlight 2026-09-21)
- **Neues App-Zeichen**: eine grüne Kartennadel mit dem Fahrrad im Kopf und einem orangen Bus-Abzeichen an der Schulter, das durch eine Kerbe von der Nadel freigestellt ist (Entwurf „N2 · Wald" aus `_reports/RadPendler_Logos_2.html`). Homescreen und Titelzeile zeichnen dieselbe Geometrie aus `Views/Mark.swift` — sie können nicht mehr auseinanderlaufen.
- **Der Countdown hat seine eigene Pille**: auf iOS 26 packte die Titelzeile ihn mit dem Burger-Menü in eine gemeinsame Glaskapsel, jetzt trennt ein fester Abstand die beiden.
- **Der Countdown wechselt die Farbe**: grün über eine halbe Stunde, gelb ab 30 min, orange ab 10 min, rot ab 5 min, dunkelrot sobald die Bahn weg ist. Die Stufen sind die voreingestellten Warnminuten — die Farbe springt in dem Moment um, in dem die App piept.
- **Stand der Berechnung auf der Zeitachse**: in der Radarpille unter der Karte, zweite Zeile: „Stand 09:54 · vor 3 min“, mitlaufend. Antippen rechnet neu — die Seite scrollt nicht mehr, also gibt es kein Ziehen nach unten mehr.
- **Auto in drei Varianten**: schnellst (Voreinstellung), kürzest und wenig Ampeln, aus den Alternativrouten von Apple Karten, die Ampeln aus denselben OpenStreetMap-Daten wie beim Rad. Wie bei den Radrouten: erster Tipp wählt, jeder weitere schaltet weiter, lang drücken zurück auf die beste. Gewinnt eine Linie alles, heißt sie schlicht „schnellst“.
- **Eine Seite ohne Scrollen**: die Fahrtzeile ist auf zwei Zeilen eingedampft (Zeiten, Abschnitte, Dauer; darunter Chips für Losgehen, km, Ampeln, Umstiege und höchstens eine Warnung), die Fußzeile ist weg und die Karte nimmt sich den übrigen Platz. Begründung der Empfehlung, Regentext im Klartext und die Hinweise stehen jetzt im Detail hinter dem Pfeil.
- **Abfahrt/Ankunft neben den Adressen**: zwei kleine Pillen rechts statt eines eigenen Segmentschalters — eine Zeile gespart.
- Menü: die Datenquellen stehen jetzt ganz unten und kursiv (ein iOS-Menü zeichnet nur einfachen Text, dort bleiben sie grau und unantastbar).

## 0.6.1 (Build 12, TestFlight 2026-09-20)
- App-Zeichen größer und nach oben links, daneben der Name; der Countdown sitzt jetzt als rote Pille **zwischen Name und Burger-Menü** und ist aus der Adresskarte verschwunden.
- Die Karte zeigt an, wenn Radarbilder noch geladen werden.
- Langes Drücken auf eine Modus-Box springt zurück auf deren erste — also beste — Möglichkeit.
- Langes Drücken auf die Karte holt die ganze Strecke wieder ins Bild (vorher: nächste Radroute).
- Rad + Bahn trägt jetzt Rad **und** Bahnsymbol; die Farbe ist ein blaueres Grün (#00A8BA).
- Menü: Version mit „v“, Copyright nur noch „© 2026 AK“ und die Datenquellen — beide so klein wie die Version.
- Nachplanen: das Ziehen nach unten setzt auch die Mitteilungen neu; ein Suchlauf ohne Ergebnis lässt die bereits scharfen Warnungen stehen, statt sie zu löschen.

## 0.6.0 (Build 11, TestFlight 2026-09-20)
- **Mitteilungen auch bei geschlossener App**: die Warnungen vor dem Losgehen kommen jetzt als echte iOS-Mitteilung („In 10 min los“ … „Jetzt los“) mit Verkehrsmittel, Zeiten und Zug; bei offener App zusätzlich der Ton wie bisher. Die App fragt einmal nach der Erlaubnis; ist sie verweigert, steht das in den Einstellungen mit einem Weg dorthin.
- Der Countdown zählt bis zum **Losgehen** (Abfahrt minus Rüstzeit) statt bis zur Abfahrt — dieselbe Zeit, die der „los …“-Chip nennt; darunter weiter Linie und Abfahrtszeit. „ABGEFAHREN“ erscheint erst, wenn die Bahn wirklich weg ist.
- Statt vier Blöcken eine Reihe aus vier Boxen: Fahrrad, Rad + Bahn, Auto, Bahn & Bus — je Box Fahrzeit, worum es sich handelt (Radvariante bzw. Abfahrt) und Punkte für die Zahl der Möglichkeiten. Erster Tipp wählt, jeder weitere schaltet zur nächsten.
- Die gewählte Fahrt steht als eine Zeile darunter: Abfahrt → Ankunft, Abschnitte, km, Ampeln, „los …“; Antippen öffnet den Zeitstrahl.
- Gelber Stern markiert die Empfehlung.
- Burger-Menü oben rechts mit Einstellungen, **Anleitung** (neu) sowie Version und Datenquellen; das App-Zeichen steht in der Titelzeile.
- Aktualisieren nur noch durch Ziehen nach unten — der Spinner läuft, solange die Suche läuft; der Knopf ist weg.
- Countdown-Kasten erscheint nur, wenn die Abfahrt feststeht (Bahn/Bus oder gesetzte Ankunftszeit), sonst gar nicht.
- Ankunftssuche bietet nur die zwei Zeiten, die der Pendelweg hat (9 und 19 Uhr), alles andere über die Uhr; Umschalten auf „Ankunft“ springt auf die nächste davon.
- Regenradar sagt, welche Minute zu sehen ist („jetzt 14:48“, „in 25 min 15:10“), öffnet auf der aktuellen Minute und springt per Tipp dorthin zurück.
- App-Symbol zeigt jetzt Rad über Zug **und** Bus, dasselbe Zeichen wie in der Titelzeile.

## 0.5.0 (Build 9, TestFlight 2026-09-20)
- Eine Seite statt Liste/Karte: Kopfzeile, Karte, darunter je ein Block für Fahrrad, Rad + Bahn, Auto, Bahn & Bus — jeder Block zeigt eine Karte, die Auswahl läuft über Chips (Radrouten nach Namen, Verbindungen nach Abfahrt und Umstiegen).
- Ankunftszeit als Suchziel: Umschalter Abfahrt/Ankunft; Fahrten zur Arbeitsadresse starten automatisch mit „Ankunft um 9 Uhr“, Fahrten nach Hause mit „Abfahrt jetzt“.
- Countdown läuft nur für Bahn/Bus — oder für jede Fahrt, wenn eine Ankunftszeit gesetzt ist; weiß auf Rot wenn aktiv, grau wenn nicht, mit Warntönen bei 10/5/1 min (in den Einstellungen).
- Puffer vor Abfahrt und Ankunft in den Einstellungen, zählen nicht zur Fahrzeit.
- Startzeiten als Uhrzeiten möglich („um 8 Uhr“, heute oder morgen).
- Langes Drücken auf eine Radroute in der Karte schaltet zur nächsten Radroute.
- Umstiege rot markiert, Ampelzahl mit Ampel-Symbol, Gesamtdauer überall fett, Fahrzeit daneben grau.

## 0.4.0 (Build 8, TestFlight 2026-09-20)
- Countdown in der Adressbox, rechte Hälfte: „LOS IN 4:07“ zur nächsten Bahn/Bus-Verbindung, unter 10 min sekundengenau, ab 5 min orange, nach der Abfahrt rot. Darunter Linie und Abfahrtszeit.
- App heißt jetzt überall **RadPendler** (Homescreen und Titelzeile).

## 0.3.2 (Build 7, TestFlight 2026-09-20)
- Radrouten wieder in vier Varianten: schnellst, kürzest, optimal, ruhigst — im Abschnitt „Fahrrad“ als Chips umschaltbar.
- Gesamtdauer fett in Modusfarbe, Abfahrt → Ankunft daneben in Grau.
- Vermutete Ampelkreuzungen der gewählten Radroute als gelbe Punkte auf der Karte.

## 0.3.1 (Build 6, TestFlight 2026-09-20)
- Farben: Rad grün, Auto rot, Bus orange, alles auf Schienen blau (S hell, U dunkel, RE und Tram dazwischen), Fähre türkis.
- Neue Kopfzeile: Start und Ziel an einer gepunkteten Schiene, Tauschknopf dreht sich, Startzeiten als Chips (Jetzt, +15 min, +1 h, +8 h, +18 h, freie Zeit).
- Karte ist die Standardansicht; ohne Adressen steht dort jetzt derselbe Hinweis wie in der Liste.

## 0.3.0 (Builds 4 und 5, TestFlight 2026-09-20)
- Build 5: Farbfamilien — Rad grün, Auto rot, Bus orange, alles auf Schienen blau (S hell, U dunkel, RE/Tram dazwischen), Fähre türkis; Styleguide angepasst.
- Neues Design: Karten statt Listenzeilen, runde Typografie, Akzentfarbe Petrol, animierter Liste/Karte-Umschalter, Detailseite als Zeitstrahl.
- App startet **ohne Adressen**; Start und Ziel werden nach der ersten Wahl auf dem Gerät gespeichert (keine privaten Adressen im Store-Build).
- Jede Verbindung zeigt ihre Abschnitte als Icons mit km (Rad, Auto, S/U/Bus/Tram), dazu Gesamt-km und Ampelzahl; auf der Karte je Abschnitt ein Schild.
- Rad ist jetzt violett, damit es sich klar von der grünen S-Bahn unterscheidet.
- **Rad + Bahn** ist jetzt Türkis (#00ADA3) statt Akzent-Petrol, damit die Empfehlungskarte oben und der Rad-+-Bahn-Abschnitt sich klar vom S-Bahn-Grün darunter absetzen.
- Regenradar folgt der Fahrt: Play läuft vom Losfahren bis zur Ankunft, die Positionsmarke wandert mit.
- Radrouten heißen **schnellst** (kürzeste Fahrzeit inkl. Ampeln), **optimal** und **ruhigst**.
- Fixpunkte in den Einstellungen: Verbindungen, die nicht daran vorbeiführen, werden ausgegraut und nie empfohlen.
- Startzeiten-Vorschläge (in 15 min, 1 h, 8 h, 18 h) — in den Einstellungen änderbar.
- Rechte und Datenquellen vollständig am Ende der Einstellungen.
- Farben: Auto rot, RE/RB orange, Tram dunkelrot, Rad + Bahn eigenes Türkis; Styleguide unter design/.

## 0.2.0 (unreleased)
- Radroute in drei Varianten: kürzest, Mittelweg, ruhigst (BRouter + Apple Karten), bewertet nach Ampelkreuzungen, gequerten Hauptstraßen (mit Namen, z. B. B 1) und Metern an Hauptstraßen (OpenStreetMap, 30 Tage zwischengespeichert).
- Fahrgeschwindigkeit (rollend, Standard 29 km/h) + Wartezeit je Ampel inkl. Anfahren (Standard 20 s) = Radfahrzeit, auch bei Rad + Bahn; Ø km/h inkl. Ampeln wird angezeigt.
- Umstiege zählen je 10 min (einstellbar); Karte zeigt alle Optionen grau mit Dauer/Umstiegen.

## 0.1.0 (1) — 2026-09-19
- Erste Version: Liste und Karte für Fahrrad, Rad + Bahn (nur Züge mit Fahrradmitnahme), Bus & Bahn, Auto.
- Rad + Bahn bevorzugt S-Bahn und Regionalzug (festes Radabteil); U-Bahn/Tram nur als markierte Alternative.
- Büroadresse: Musterstraße 1, 10115 Berlin.
- Rüstzeit (Standard 5 min), Radgeschwindigkeit (Standard 21 km/h), Bahnhofspuffer, Radius, Parkplatzsuche einstellbar.
- Regenvorhersage entlang der Radstrecke zur Durchfahrtszeit; animiertes DWD-Regenradar mit Position auf der Route.
