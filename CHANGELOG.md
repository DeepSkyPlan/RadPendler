# Changelog

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
