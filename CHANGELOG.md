# Changelog

## 0.13.0 (Build 20, noch nicht hochgeladen)
- **„Mein Standort" als Startadresse.** Die Adresssuche für den Start beginnt jetzt mit einem Vorschlag: dort, wo du gerade bist. Steht schon eine Erlaubnis, wird die Adresse gleich beim Öffnen aufgelöst und steht mit Straße und PLZ in der Zeile — ein Tipp genügt. Ohne Erlaubnis fragt der erste Tipp danach; wird sie abgelehnt, verschwindet die Zeile und alles andere funktioniert weiter.
- Der Standort wird **einmal** abgefragt, in eine Adresse übersetzt und danach vergessen: kein Mitschreiben, kein Hintergrundzugriff, keine Bewegungsverfolgung. Die Koordinate geht danach denselben Weg wie jede getippte Adresse — an die Routing- und Fahrplandienste, an sonst niemanden.
- „Zuhause" und „Arbeit" in den Einstellungen bekommen denselben Vorschlag.

## 0.12.1 (Build 19, noch nicht hochgeladen)
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
