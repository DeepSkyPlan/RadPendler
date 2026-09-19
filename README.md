# Pendel

iOS app: Büro (Musterstraße 1) ↔ Musterort (Beispielweg 2) mit Rad, Rad + Bahn, Bus & Bahn und Auto, inklusive Rüstzeit und Regen auf der Radstrecke.

    xcodegen generate
    xcodebuild -project Pendel.xcodeproj -scheme Pendel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

Quellen: VBB-HAFAS mgate (inoffiziell, Profil aus hafas-client), Apple MapKit (Rad/Auto),
DWD-GeoServer-WMS `dwd:Niederschlagsradar` (Radar + 2-h-Nowcast), Open-Meteo `minutely_15` (Regen je Streckenpunkt).
`tools/hafas_probe.py` = Phase-0-Probe; Fixtures in `PendelTests/Fixtures` stammen daraus.
Launch-Arg `-tab map` öffnet direkt die Karte.
