# Changelog

## 0.7.0 (Build 12, noch nicht hochgeladen)
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
- Büroadresse: Musterstraße 1, 10557 Berlin.
- Rüstzeit (Standard 5 min), Radgeschwindigkeit (Standard 21 km/h), Bahnhofspuffer, Radius, Parkplatzsuche einstellbar.
- Regenvorhersage entlang der Radstrecke zur Durchfahrtszeit; animiertes DWD-Regenradar mit Position auf der Route.
