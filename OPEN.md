# RadPendler — offen (Stand 15.11.2026)

Gesamtstand und Prüfliste: `HANDOVER.md`. Hier nur, was gerade in der Schwebe ist.

## 1.27 (67) in TestFlight (15.11.2026)

Inhalt: Rad nie gegen die Kreisverkehrsrichtung (`RoundaboutRule`, `TripPlanner.rightWayRound`,
Overpass-Kreisverkehre in `RoadData.rings`), „Fahrt beenden?“-Text gekürzt.

Hochgeladen auf Ansage mit `SKIP_ROUTES=1`, weil Overpass überlastet war (27–41 s, 502).
`./dev rules` grün, 429 Tests grün, release-check GO.

**Offen:**
- `./dev routes` mit Straßendaten nachholen, sobald Overpass schnell antwortet (Probe-`curl` unter 10 s).
  Muss grün sein und Kreisverkehre am Weg zeigen. Wird es rot, ist das ein Fehler in 1.27.
- Prüfliste neu veröffentlichen (neuer Punkt `o16`), Gerätetest Rückweg über den Kreisverkehr.
- „Was ist neu (1.27)“ in `appstore/metadata.md` fehlt (`/whatsnew`), erst zur Einreichung nötig.

## Ideen, nicht angefangen

- OSM-Daten korrigieren (`oneway=yes` am Ringradweg), falls er wirklich nur eine Richtung hat — seine
  Entscheidung, öffentliche Änderung.
- Kreisverkehrsregel auch in der Neuplanung unterwegs prüfen (`Replanner`); heute trägt nur der
  Zwischenpunkt aus dem Plan sie dorthin, und `WaypointRouting.ahead` lässt ihn in 150 m Nähe fallen.
