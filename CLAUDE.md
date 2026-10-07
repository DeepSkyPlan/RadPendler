# RadPendler

Multimodaler Pendel-Planer (iPhone, iPad, Watch). SwiftUI, XcodeGen, iOS 17+, `de.keese.radpendler`.

**Wiedereinstieg: Kopf von `HANDOVER.md` lesen.** Dort stehen Stand, Build und die offene Prüfliste.

- Einziger Einstieg ist `./dev` (`generate|build|test|lint|check|open|clean|testflight`). Kein eigenes
  `-derivedDataPath` — Xcode und Kommandozeile teilen sich die Standard-DerivedData.
- Tests: `./dev test` (~350 Tests, rund 10 s). `MOTIS_LIVE=1` schaltet den echten Transitous-Aufruf zu.
- Ausliefern nur auf Ansage: `./dev testflight [version]` bzw. Skill `/testflight`.
- Was nur auf dem Gerät prüfbar ist (Ortung, Hintergrund, iCloud, Töne, Uhr): abhakbare Liste
  `tools/pruefliste.html`, veröffentlicht unter <https://claude.ai/artifact/1cPcVH6bKB63rFqTYmGCLk>
  (Stand wird dort gespeichert). Neue Funktion mit Geräteanteil → dort eine Zeile dazu und neu veröffentlichen.
- Eine seltsame Fahrt aufklären: geteilte `RadPendler-Fahrt-*.json` mit `python3 tools/ride_report.py`
  auswerten, nicht raten.
- Hänger oder Ruckeln: **zuerst die CPU messen, dann Code lesen** (`ps -p $PID -o %cpu=`, `sample $PID 5`
  auf dem Simulator-Prozess). Der Hänger aus 1.2 (TimelineView in einer ToolbarItem, iOS 26) ist
  gelöst; Protokoll und Messfallen in `../RadPendler-Haenger.md`.
- Gespeicherte Typen (`Ride`, `LearnedSignal`, `PlaceUse`, …): ein neues Feld darf beim Lesen nie
  Pflicht sein (Vorgabewert reicht nicht, `init(from:)` nötig), Listen über `Stored.list`/`Stored.encode`,
  Zusammenführen muss wiederholbar und von beiden Seiten gleich sein. Dazu eine neue Probe in
  `StoredFormatTests`; `CloudStore.schema` nur hochzählen, wenn eine alte Fassung Schaden anrichten würde.
- Vor dem Pushen `./dev check` (Lint, dann Tests) — dasselbe läuft danach in GitHub Actions
  (`.github/workflows/ci.yml`; Stand: `gh run list -L 3`). Lint meldet nur Neues, Altes steht in
  `.swiftlint-baseline.json`; die Baseline nur nach einer Bereinigung neu schreiben (`./dev lint baseline`).
  SwiftLint 0.65.1 liegt in `~/.local/bin/swiftlint`; CI nimmt dieselbe Fassung.
- Kein nacktes `try?` für etwas, das scheitern kann, ohne dass es jemand sieht (Datei, Kodieren,
  CloudKit, Uhr, Mitteilung): `Log.attempt("was") { try … }` bzw. `await Log.attemptAsync`. `try?` bleibt
  für `Task.sleep`, verzeihendes Lesen und gewollte Rückfälle.
- Quelloffen: keine Adressen, Koordinaten oder Schlüssel ins Repo — auch keine „ungefähren“ in Tests
  und keine Ortsnamen der eigenen Strecke in Kommentaren. Testorte sind Alexanderplatz (52.5210, 13.4130)
  und S Wannsee (52.4213, 13.1794); die eigene Strecke heißt „Teststrecke“. `Secrets.xcconfig` bleibt lokal.
