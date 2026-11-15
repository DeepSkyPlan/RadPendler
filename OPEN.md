# RadPendler — offen (Stand 15.11.2026)

Gesamtstand und Prüfliste: `HANDOVER.md`. Hier nur, was gerade in der Schwebe ist.

## 1.27 wartet auf den Upload

Auf `main` (`9063254`), CHANGELOG „## Unveröffentlicht“:

- **Rad nie gegen die Kreisverkehrsrichtung.** Der Radweg um einen großen Kreisverkehr am Rückweg der
  Teststrecke ist in OSM `oneway=no`; BRouter schickte „optimal“, „kürzest“ und „ruhig“ rechts herum.
  Jetzt bringt Overpass die Kreisverkehre mit (`RoadData.rings`, Cache neu als `osm-roads-2`), eine Linie
  rechts herum wird mit Zwischenpunkt auf der anderen Seite neu gefragt (`RoundaboutRule`,
  `TripPlanner.rightWayRound`), sonst nicht gezeigt. Fünf Tests in `RouteRulesTests`; `./dev routes`
  prüft die Regel live und meldet „Kreisverkehre ungeprüft“, wenn Overpass keine Daten liefert.
- „Fahrt beenden?“-Text gekürzt (der Knopf „Weiterfahren“ wurde abgeschnitten).

Stand der Prüfungen (14./15.11.): `./dev check` grün (429 Tests), `./dev rules` grün, release-check **GO**.
`./dev routes` **rot**, weil Overpass überlastet war (502, 23–45 s): ohne Straßendaten wählt
„Berlin Hbf → Rathaus Steglitz“ ein anderes „optimal“ (0 m Prinzregentenstraße). Mit Straßendaten war
der Lauf vom 13.11. grün.

**Nächster Schritt:** sobald Overpass schnell antwortet,
`curl -s -o /dev/null -w "%{http_code} %{time_total}\n" -A RadPendler-dev https://overpass-api.de/api/interpreter --data-urlencode 'data=[out:json];node(around:50,52.5210,13.4130)[highway=traffic_signals];out ids;'`
→ `./dev routes` (muss grün sein und Kreisverkehre am Weg zeigen) → `./dev testflight 1.27`.
`SKIP_ROUTES=1` nur auf ausdrückliche Ansage.

Danach: Prüfliste neu veröffentlichen (neuer Punkt `o16`), Gerätetest Rückweg über den Kreisverkehr.

## Ideen, nicht angefangen

- OSM-Daten korrigieren (`oneway=yes` am Ringradweg), falls er wirklich nur eine Richtung hat — seine
  Entscheidung, öffentliche Änderung.
- Kreisverkehrsregel auch in der Neuplanung unterwegs prüfen (`Replanner`); heute trägt nur der
  Zwischenpunkt aus dem Plan sie dorthin, und `WaypointRouting.ahead` lässt ihn in 150 m Nähe fallen.
