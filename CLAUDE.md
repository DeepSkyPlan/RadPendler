# RadPendler

Multimodaler Pendel-Planer (iPhone, iPad, Watch). SwiftUI, XcodeGen, iOS 17+, `de.keese.radpendler`.

**Wiedereinstieg: Kopf von `HANDOVER.md` lesen.** Dort stehen Stand, Build und die offene Prüfliste.

- Einziger Einstieg ist `./dev` (`generate|build|test|open|clean|testflight`). Kein eigenes
  `-derivedDataPath` — Xcode und Kommandozeile teilen sich die Standard-DerivedData.
- Tests: `./dev test` (~270 Tests). `MOTIS_LIVE=1` schaltet den echten Transitous-Aufruf zu.
- Ausliefern nur auf Ansage: `./dev testflight [version]` bzw. Skill `/testflight`.
- Eine seltsame Fahrt aufklären: geteilte `RadPendler-Fahrt-*.json` mit `python3 tools/ride_report.py`
  auswerten, nicht raten.
- Hänger oder Ruckeln: **zuerst die CPU messen, dann Code lesen** (`ps -p $PID -o %cpu=`, `sample $PID 5`
  auf dem Simulator-Prozess). Der Hänger aus 1.2 (TimelineView in einer ToolbarItem, iOS 26) ist
  gelöst; Protokoll und Messfallen in `../RadPendler-Haenger.md`.
- Quelloffen: keine Adressen, Koordinaten oder Schlüssel ins Repo. `Secrets.xcconfig` bleibt lokal.
