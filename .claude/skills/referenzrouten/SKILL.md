---
name: referenzrouten
description: RadPendler — die Radplanung dieser Fassung auf bekannten Strecken gegen das prüfen, was dort gelten muss (Arbeitsweg über die Fahrradstraße, nirgends Kopfsteinpflaster). Vor jedem TestFlight-Upload, nach jeder Änderung an BRouter-Profilen, Faktoren oder der Rollenvergabe, und bei "/referenzrouten", "referenzrouten prüfen", "fährt optimal noch über die Prinzregentenstraße?".
---

# Referenzrouten

Prüft mit dem Planer der App selbst (kein nachgebautes Skript), frisch gegen brouter.de, ohne
Zwischenspeicher. Dauert rund eine Minute.

1. Im Repo `RadPendler`: `./dev routes`. Die Ausgabe nennt je Strecke jede gezeigte Linie mit Rolle,
   Länge, Metern Fahrradstraße und Kopfsteinpflaster; darunter jede verletzte Regel mit `✗` und am
   Ende „in Ordnung" oder „NICHT in Ordnung" (Exit 1).
2. **Rot ist ein Befund, kein Hindernis.** Nicht die Schwelle senken, bis es grün ist. Erst klären,
   was sich geändert hat:
   - ein Faktor oder Aufschlag im Profil (`BRouterClient.Profile.cycleStreetAdvantage`,
     `CustomProfile.cobblePenalty`) oder die Rollenvergabe (`BikeCandidate.pick`) → das ist der
     Fehler, dort beheben;
   - `✗ BRouter: …` → ein Profil ließ sich nicht hochladen oder eine Route kam nicht; die Zahlen
     darüber sind dann nicht die dieser Fassung. Ein paar Minuten warten, noch einmal laufen lassen;
   - die Karte selbst (OpenStreetMap: eine Straße umgewidmet, ein Belag neu erfasst) → dem Nutzer
     zeigen, was jetzt herauskommt, und **ihn** entscheiden lassen, ob die Schwelle sich ändert.
3. Dem Nutzer melden: je Strecke eine Zeile zur Linie „optimal" (Länge, Fahrradstraße, Pflaster),
   was rot war und warum. Die eigenen Strecken heißen in der Ausgabe „eigene Strecke 1/2" — ihre
   Orte und Koordinaten nie ausschreiben.

## Wo die Strecken stehen

- Öffentliche: `RadPendlerTests/Fixtures/referenzrouten.json` (im Repository, nur öffentliche Orte:
  Rathaus Steglitz ↔ Berlin Hbf über die Prinzregentenstraße, Pinneberg → Hamburg Hbf,
  München Pasing → Ostbahnhof).
- Die eigene (Arbeitsweg, beide Richtungen): `~/.config/radpendler/referenzrouten.json`, gleiches
  Format, **nur lokal** — nie ins Repository, auch nicht als Beispiel.
- Regeln je Strecke: `optimal`, `quiet` (für die Linie mit dieser Rolle) und `every` (für jede
  gezeigte Linie), jeweils mit `along` + `alongMeters` (Meter an einer Straße aus `streets`),
  `minCycleStreetMeters`, `maxCobbleMeters`, `maxKm`.
- Eine neue Strecke: Eintrag in die passende Datei, einmal `./dev routes`, die Schwellen bei rund
  drei Vierteln des Gemessenen ansetzen. Eine neue Straße für `along`: ihre Punkte (alle ~40 m)
  unter `streets`.

## Vor TestFlight

`./dev testflight` ruft `./dev routes` selbst als Erstes auf und lädt bei Rot nichts hoch
(`SKIP_ROUTES=1` nur auf ausdrückliche Ansage des Nutzers). Der Skill `/testflight` startet diesen
hier trotzdem vorher — damit ein roter Befund besprochen ist, bevor Buildnummer und CHANGELOG
angefasst werden.
