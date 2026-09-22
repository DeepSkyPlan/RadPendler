# RadPendler

Ein multimodaler Pendel-Planer für iPhone, iPad und Apple Watch: dieselbe Strecke
mit dem **Rad**, mit **Rad + Bahn**, mit dem **Auto** und mit **Bus & Bahn**
nebeneinander — mit Ampeln, Regen auf der Radstrecke und einem Countdown bis zum
Losgehen.

Die App ist für einen Weg gebaut und danach allgemein geworden: sie kennt keine
eingebauten Adressen, rechnet die Radzeit aus der *rollenden* Geschwindigkeit
plus einer Wartezeit je Ampelkreuzung, und sie sagt, was sie nicht weiß, statt
zu raten.

```bash
./dev test       # erzeugt das .xcodeproj bei Bedarf und testet im Simulator
./dev build
./dev open       # Xcode, auf demselben DerivedData
```

Xcode 26, iOS 17+, watchOS 10+. Das `.xcodeproj` ist generiert und nicht
eingecheckt — die Struktur steht in `project.yml` (XcodeGen).

## Was die App tut

- **Vier Verkehrsmittel auf einer Seite**, die ohne Scrollen passt: Karte,
  vier Kästen mit Fahrzeit, und die gewählte Fahrt in zwei Zeilen.
- **Radrouten in Varianten** — schnellst, kürzest, optimal, ruhigst — aus
  mehreren BRouter-Profilen und Apple Karten, bewertet mit Ampeln, gequerten
  Hauptstraßen und Metern neben Hauptstraßen aus OpenStreetMap.
- **Rad + Bahn**: die App sucht sich die Bahnhöfe selbst und nimmt nur Züge,
  auf denen das Rad mitdarf. Was der Fahrplan nicht zusichert, bleibt sichtbar,
  aber als „Mitnahme ungeklärt" — entschieden wird pro Linie, von Hand.
- **Regen je Streckenpunkt** aus dem DWD-Radar und Open-Meteo, als Entscheidung
  zwischen Rad und Bahn, nicht als Wetterbericht.
- **Countdown** bis zum Losgehen, als Ampel gefärbt, mit Mitteilungen auch bei
  geschlossener App — und auf der Uhr.
- **Vorlieben statt Regeln**: in welcher Reihenfolge die Verkehrsmittel gelten,
  welche Routenvariante vorgeschlagen wird und ab wieviel Regen das Rad in die
  Bahn gehört, steht in den Einstellungen.

## Datenquellen

- **VBB HAFAS** (`fahrinfo.vbb.de`, inoffiziell, Profil nach `hafas-client`) —
  Fahrplan und Echtzeit für Berlin/Brandenburg.
- **Apple MapKit** — Auto- und Fußwege, Kartendarstellung, Adresssuche.
- **BRouter** (`brouter.de`) — Radrouten auf OpenStreetMap-Daten.
- **OpenStreetMap über Overpass** — Ampeln und Hauptstraßen entlang der Route.
  © OpenStreetMap-Mitwirkende, ODbL.
- **DWD GeoServer WMS** `dwd:Niederschlagsradar` — Regenradar und 2-h-Nowcast.
- **Open-Meteo** `minutely_15` — Regen je Streckenpunkt.

- **„Mein Standort"** als Startadresse: einmal abgefragt, in eine Adresse
  übersetzt, danach vergessen — die App folgt niemandem.

## Privates

Die App wird **ohne Adressen** ausgeliefert und enthält keine. Der Standort
wird nur auf Tippen abgefragt, einmal, und nur um daraus eine Startadresse zu
machen; danach wird der Manager wieder vergessen. Was der Nutzer
eingibt, bleibt auf seinen Geräten und in seiner eigenen iCloud
(Schlüssel-Wert-Speicher); es geht an keinen Server dieses Projekts, weil es
keinen gibt. Die Testdaten unter `RadPendlerTests/Fixtures` sind echte Antworten
der Dienste, aber auf neutrale Adressen und eine versetzte Geometrie gebracht.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Die Daten der oben genannten Dienste stehen unter
ihren eigenen Bedingungen.
