# -*- coding: utf-8 -*-
"""Deutsch → Englisch für RadPendler.

Der Schlüssel ist der deutsche Text, so wie er im Quelltext steht. Was hier
nicht drinsteht, wird nicht angefasst — Protokolltexte (HAFAS-Vergleichsmuster,
User-Agent), SF-Symbole und UserDefaults-Schlüssel gehören nicht hierher.
"""

T = {
# --- Menü, Kopfzeile, Hauptbildschirm
"Menü": "Menu",
"Anleitung": "Guide",
"Fahrten": "Rides",
"Einstellungen": "Settings",
"Adressen": "Addresses",
"Navigation": "Navigation",
"Verkehrsmittel": "Modes",
"Fertig": "Done",
"Abbrechen": "Cancel",
"Start und Ziel wählen": "Choose start and destination",
"Oben auf die beiden Zeilen tippen. Die Adressen bleiben auf diesem Gerät.": "Tap the two lines above. The addresses stay on this device.",
"Start wählen": "Choose start",
"Ziel wählen": "Choose destination",
"Richtung tauschen": "Swap direction",
"Start: ": "Start: ",
"Ziel: ": "Destination: ",
"nicht gesetzt": "not set",
"Pendelstrecke einsetzen": "Use my commute",
"Wann da sein?": "Arrive when?",
"Wann losgehen?": "Leave when?",
"Übernehmen": "Apply",
"Jetzt": "Now",
"Abfahrt": "Departure",
"Ankunft": "Arrival",
"Datenquellen: VBB · Transitous/MOTIS · Apple Karten · BRouter und OpenStreetMap · DWD · Open-Meteo":
    "Data: VBB · Transitous/MOTIS · Apple Maps · BRouter and OpenStreetMap · DWD · Open-Meteo",
"Wie das Telefon": "Match the phone",

# --- Verkehrsmittel und Rollen
"Fahrrad": "Bike",
"Rad + Bahn": "Bike + rail",
"Auto": "Car",
"Bus & Bahn": "Transit",
"ÖPNV": "Transit",
"schnellst": "fastest",
"kürzest": "shortest",
"optimal": "balanced",
"ruhigst": "quietest",
"verkehrsarm": "low traffic",
"Alternative": "Alternative",
"Vorige Möglichkeit": "Previous option",
"Nächste Möglichkeit": "Next option",
"Keine feste Abfahrt": "No fixed departure",
"Fällt aus": "Cancelled",
"Kein Plan": "No plan",
"läuft": "running",
"Fahrt läuft": "Ride in progress",
"wird berechnet …": "calculating …",
"wird bestimmt …": "locating …",

# --- Fahrradmitnahme
"Rad ja": "Bike yes",
"Rad nein": "Bike no",
"offen": "open",
"Rad ungeklärt": "Bike unclear",
"Fahrradmitnahme möglich": "Bikes allowed",
"Fahrradmitnahme ungeklärt": "Bike carriage unclear",
"keine Fahrradmitnahme": "No bikes allowed",
"alle geklärt": "all settled",
"Gesehene Linien": "Lines seen so far",
"Linie, z. B. RE 7": "Line, e.g. RE 7",
"Hinzufügen": "Add",
"Alternative mit U-Bahn/Tram — kein festes Radabteil": "Alternative by metro/tram — no dedicated bike space",

# --- Karte, Radar
"Regenradar (DWD)": "Rain radar (DWD)",
"Regenradar": "Rain radar",
"Radarbilder werden geladen": "Loading radar frames",
"Abspielen": "Play",
"Anhalten": "Pause",
"Karte folgt dir": "Map is following you",
"Karte folgt dir nicht, kommt in 30 Sekunden zurück": "Map is not following you, returns in 30 seconds",
"Du": "You",
"Mein Standort": "My location",
"dort, wo du gerade bist": "wherever you are right now",
"Vorschlag des iPhones": "From the iPhone",
"Adresse oder Ort": "Address or place",
"Adresse nicht gefunden": "Address not found",
"Noch keine Adresse": "No address yet",
"Schon benutzt": "Used before",
"Suche": "Search",
"keine Regendaten": "no rain data",
"Schauer möglich": "Showers possible",
"trocken und mit der Bahn schneller als die ganze Strecke per Rad": "dry, and the train beats riding the whole way",

# --- Straßenarten
"Hauptstraße": "Main road",
"Nebenstraße": "Side street",
"Radweg": "Bike path",
"Weg": "Track",
"Fußweg": "Footpath",
"sonstiges": "other",
"Worauf gefahren": "Surface ridden",
"Höhe": "Elevation",

# --- Fahrt aufzeichnen
"Fahrt": "Ride",
"Fahrt aufzeichnen": "Record ride",
"Fahrt beenden": "End ride",
"Fahrt beenden?": "End the ride?",
"Weiterfahren": "Keep riding",
"Die Aufzeichnung wird gespeichert und die Ortung hört auf.": "The recording is saved and location tracking stops.",
"Pause": "Pause",
"Weiter": "Resume",
"Fahrt anhalten": "Pause the ride",
"Fahrt fortsetzen": "Resume the ride",
"Fahrt beendet": "Ride ended",
"steht": "standing",
"gestanden": "standing",
"jetzt": "now",
"Ø": "avg",
"Ø / Plan": "avg / plan",
"Ø gesamt": "avg overall",
"Ø gesamt / Plan": "avg overall / plan",
"Ø rollend": "avg rolling",
"Ø je Ampel": "avg per light",
"Spitze": "top",
"Strecke": "Distance",
"Fahrzeit": "Ride time",
"Ampelhalts": "Light stops",
"Ampeln": "Lights",
"Ampeln / Plan": "Lights / plan",
"Ampelwartezeit": "Time at lights",
"Halte": "Stops",
"Ampel": "Light",
"Halt": "Stop",
"Angekommen": "Arrived",
"Noch keine Fahrt": "No rides yet",
"Keine Linie": "No track",
"noch keine Linie": "no track yet",
"keine Wartezeit": "no waiting time",
"noch keine Wartezeit": "no waiting time yet",
"Fahrt löschen?": "Delete this ride?",
"Löschen": "Delete",
"Behalten": "Keep",
"Gefahrene Fahrten": "Rides you took",
"Von selbst beendet: du standst lange an derselben Stelle, und dort ist keine Ampel. Gezählt wurde bis zum Anfang des Stillstands.":
    "Ended by itself: you stood in the same spot for a long time, and there is no traffic light there. Counted up to the start of that standstill.",
}

T.update({
# --- Countdown, Warnungen, Uhr
"LOS IN": "LEAVE IN",
"LOSGEHEN": "GO NOW",
"KEINE ABFAHRT": "NO DEPARTURE",
"Jetzt los": "Leave now",
"Countdown": "Countdown",
"Countdown ausgeschaltet": "Countdown switched off",
"Warnung vor dem Losgehen": "Warning before leaving",
"Mitteilungen sind aus — in den iOS-Einstellungen erlauben": "Notifications are off — allow them in iOS Settings",
"Wie?": "How?",
"RadPendler auf dem iPhone öffnen — der Plan kommt von dort.": "Open RadPendler on the iPhone — the plan comes from there.",
"Die Uhr zeigt dieselben Zahlen, solange das iPhone in Reichweite ist — sie rechnet nichts selbst.":
    "The watch shows the same numbers as long as the iPhone is in range — it computes nothing itself.",
" und ": " and ",

# --- Fehler und Hinweise der Dienste
"Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben.":
    "RadPendler is not allowed to use your location — enable it in iOS Settings.",
"Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen unter Datenschutz freigeben.":
    "RadPendler is not allowed to use your location — enable it under Privacy in iOS Settings.",
"Keine Radroute gefunden (Apple Karten und BRouter)": "No bike route found (Apple Maps and BRouter)",
"keine Verbindung mit Radmitnahme gefunden": "no connection found that takes bikes",
"BRouter: unerwartete Antwort": "BRouter: unexpected response",
"Transitous: unerwartete Antwort": "Transitous: unexpected response",
"VBB-Auskunft: unerwartete Antwort": "VBB service: unexpected response",
"Wetterdaten: unerwartete Antwort": "Weather data: unexpected response",
"OpenStreetMap-Daten: unerwartete Antwort": "OpenStreetMap data: unexpected response",
"Nur die Route von Apple Karten — BRouter antwortet gerade nicht": "Apple Maps route only — BRouter is not answering right now",
"Route von Apple Karten": "Route from Apple Maps",
"Fahrzeit laut Apple Karten mit Verkehrslage": "Travel time from Apple Maps, traffic included",
"Linienführung und Fahrzeit von Apple Karten, Ampeln aus OpenStreetMap": "Route and time from Apple Maps, traffic lights from OpenStreetMap",
"Fahrten von Transitous; Radzeiten nach deren Schätzung": "Trips from Transitous; bike times are their estimate",
"Strecke zu lang für die Ampelzählung (OpenStreetMap)": "Route too long to count traffic lights (OpenStreetMap)",
"Ampeln und Hauptstraßen auf dieser Länge nicht gezählt": "Traffic lights and main roads not counted over this distance",
"Ampeln und Hauptstraßen unbekannt — OpenStreetMap antwortete nicht, wird im Hintergrund nachgeholt":
    "Traffic lights and main roads unknown — OpenStreetMap did not answer; retried in the background",
"Ampeln unbekannt": "Lights unknown",
"führt nicht über die Fixpunkte": "does not pass your fixed points",
"ohne Fixpunkte": "no fixed points",
"Die Linien reisen gerade nicht in deine iCloud.": "Your tracks are not reaching iCloud right now.",
"Die Linien reisen, sobald wieder Netz da ist.": "Your tracks will travel as soon as there is a connection again.",
"Die Linien bleiben auf dem Gerät: keine Apple-ID angemeldet.": "Tracks stay on this device: no Apple ID signed in.",
"Die Linien bleiben auf dem Gerät: dein iCloud-Speicher ist voll.": "Tracks stay on this device: your iCloud storage is full.",
"Die Linien reisen nicht: iCloud kennt den Datensatztyp nicht (Schema nicht übernommen).":
    "Tracks are not travelling: iCloud does not know the record type (schema not deployed).",
"Die Zahlen dieser Fahrt sind da, die gefahrene Linie nicht: entweder wurde sie vor 1.3 auf einem anderen Gerät aufgezeichnet, oder sie ist gerade nicht aus iCloud zu holen.":
    "The numbers of this ride are here, the track is not: either it was recorded on another device before 1.3, or it cannot be fetched from iCloud right now.",
"Auf diesem Gerät. Andere Geräte behalten sie, bis du sie auch dort löschst.":
    "On this device. Other devices keep it until you delete it there too.",
"Auf der Hauptseite eine Verbindung wählen und „Fahrt aufzeichnen“ antippen. Was aufgezeichnet wurde, steht danach hier.":
    "Pick a trip on the main screen and tap “Record ride”. Whatever was recorded shows up here.",

# --- Einstellungen: Überschriften und Zeilen
"Zuhause und Arbeit": "Home and work",
"Zuhause": "Home",
"Arbeit": "Work",
"Beide vergessen": "Forget both",
"Beide Adressen löschen": "Delete both addresses",
"Bei der Arbeit sein um": "Be at work by",
"Fixpunkte": "Fixed points",
"Fixpunkt": "Fixed point",
"Fixpunkt hinzufügen": "Add a fixed point",
"Alle Fixpunkte verlangen": "Require every fixed point",
"Rüstzeit": "Preparation",
"Umsteigen": "Changing trains",
"Startzeiten": "Start times",
"Zeitpunkt hinzufügen": "Add a time",
"Puffer": "Buffers",
"Vorlieben": "Preferences",
"Möglichkeiten je Verkehrsmittel": "Options per mode",
"Radrouten": "Bike routes",
"Autorouten": "Car routes",
"Rad in die Bahn ab": "Bike on the train from",
"Zurück auf Werkseinstellung": "Back to factory settings",
"Fahrplan": "Timetable",
"Fahrplanquelle": "Timetable source",
"Ausrichtung": "Orientation",
"Automatisch": "Automatic",
"Hochkant": "Portrait",
"Querformat": "Landscape",
"Neu berechnen ab": "Recalculate after",
"… oder nach": "… or after",
"Bildschirm abdunkeln nach": "Dim the screen after",
"Von selbst beenden nach": "End by itself after",
"Gelernte Ampeln": "Learned traffic lights",
"Gelernte Ampeln vergessen": "Forget learned traffic lights",
"Noch keine gemessenen Fahrten": "No measured rides yet",
"Gesamtschnitt": "Overall average",
"Rolltempo": "Rolling speed",
"Tür zu Tür, mit Ampeln und Halten — damit wird die Fahrzeit gerechnet":
    "Door to door, traffic lights and stops included — this is what the travel time is based on",
"nur die fahrende Zeit — daraus kommt die Einstellung darüber":
    "only the time in motion — this is where the setting above comes from",
"Hilfe und Rückmeldung": "Help and feedback",
"Hilfe und Rechtliches": "Help and legal",
"Quelltext auf GitHub": "Source code on GitHub",
"Daten, Rechte und Version": "Data, rights and version",
"Datenschutz": "Privacy",
"Sprache": "Language",
"Die vier Boxen": "The four boxes",
"Die Zeile darunter": "The line below",
"Start und Ziel": "Start and destination",
"Abfahrt oder Ankunft": "Departure or arrival",
"Was die App voraussetzt": "What the app assumes",
"Alle Zeiten ohne Gewähr.": "All times without guarantee.",
"© 2026 AK. Alle Zeiten ohne Gewähr.": "© 2026 AK. All times without guarantee.",
"Neu berechnen": "Recalculate",
"Tippen zum Zuklappen": "Tap to collapse",
"Tippen für den ganzen Text": "Tap for the full text",
"mehr": "more",
"weniger": "less",
})

T.update({
# --- Anleitung (HelpView)
"Fahrrad, Rad + Bahn, Auto, Bus & Bahn — jede Box zeigt die Fahrzeit und worum es sich handelt: bei Radrouten schnellst, kürzest, optimal oder ruhigst, bei Verbindungen die Abfahrt.":
    "Bike, bike + rail, car, transit — each box shows the travel time and what it is: for bike routes fastest, shortest, balanced or quietest; for connections the departure.",
"Ein Tipp wählt die Box aus, der nächste Tipp schaltet zur nächsten Möglichkeit. Die Punkte unter der Zeit zeigen, wie viele es sind.":
    "One tap selects the box, the next tap steps to the next option. The dots below the time show how many there are.",
"Lang drücken springt zurück auf die erste und damit beste Möglichkeit dieser Box.":
    "Press and hold to jump back to the first — and therefore best — option in that box.",
"Der gelbe Stern steht an dem, was die App empfiehlt.": "The yellow star marks what the app recommends.",
"Beim Rad gibt es „verkehrsarm“ zusätzlich zu „ruhigst“: „ruhigst“ zählt auch Ampeln und Querungen, „verkehrsarm“ fragt nur, wo die Autos sind.":
    "For bikes there is “low traffic” next to “quietest”: “quietest” also counts lights and crossings, “low traffic” only asks where the cars are.",
"Sie zeigt die gewählte Fahrt: Abfahrt → Ankunft, die Abschnitte, Kilometer, Ampeln und wann es losgeht.":
    "It shows the chosen trip: departure → arrival, the legs, kilometres, traffic lights and when to set off.",
"Antippen öffnet die Route im Detail — Zeitstrahl mit Bahnsteigen, Verspätungen und Radabschnitten.":
    "Tap it to open the route in detail — a timeline with platforms, delays and bike legs.",
"Der grüne Knopf rechts neben der gewählten Fahrt zeichnet auf, was du wirklich fährst: Strecke, Geschwindigkeit, Ampelhalts.":
    "The green button beside the chosen trip records what you actually ride: distance, speed, stops at lights.",
"Oben auf die beiden Zeilen tippen und die Adresse suchen. Beide bleiben nur auf diesem Gerät.":
    "Tap the two lines at the top and search for the address. Both stay on this device only.",
"Der Pfeil daneben dreht die Richtung um.": "The arrow beside them swaps the direction.",
"Ein Doppeltipp auf die Box setzt die Pendelstrecke ein: dein Standort als Start, Zuhause oder Arbeit als Ziel. Welches von beidem, entscheidet der Ort — und wenn keiner passt, die Uhrzeit.":
    "A double tap on the box fills in your commute: your location as the start, home or work as the destination. Which of the two depends on where you are — and if neither fits, on the time of day.",
"„Abfahrt“ sucht ab einer Startzeit — Jetzt oder eine der gespeicherten Startzeiten.":
    "“Departure” searches from a start time — Now, or one of the saved start times.",
"„Ankunft“ sucht rückwärts und bietet die zwei Zeiten an, die der Pendelweg wirklich hat: 9 Uhr hin, 19 Uhr zurück. Jede andere Zeit über das Uhr-Feld.":
    "“Arrival” searches backwards and offers the two times a commute really has: 9 in the morning out, 7 in the evening back. Any other time through the clock field.",
"Ist das Ziel die Arbeitsadresse (Einstellungen → Arbeitsweg), startet die Suche mit „Ankunft“, sonst mit „Abfahrt jetzt“.":
    "If the destination is your work address (Settings → commute), the search starts with “Arrival”, otherwise with “Departure now”.",
"Die Rüstzeit ist die Zeit vom Blick auf die App bis zum Losgehen; sie steckt in „los …“.":
    "Preparation time is the time between looking at the app and walking out; it is included in “leave …”.",
"Die gewählte Fahrt liegt farbig oben, die anderen blass darunter. Ein Tipp auf ein Schild in der Karte wählt diese Fahrt.":
    "The chosen trip is drawn in colour on top, the others pale below. Tapping a label on the map selects that trip.",
"Gelbe Punkte sind vermutete Ampelkreuzungen der gewählten Radroute — aus OpenStreetMap und aus dem, was deine eigenen Fahrten gelernt haben.":
    "Yellow dots are presumed signalised junctions on the chosen bike route — from OpenStreetMap and from what your own rides have learned.",
"Auf der Karte einer gefahrenen Fahrt sind die Ampeln gelb markiert und tragen ihre Wartezeit; andere Halte stehen klein und grau daneben.":
    "On the map of a recorded ride the traffic lights are marked yellow and carry their waiting time; other stops sit beside them, small and grey.",
"Langes Drücken irgendwo auf der Karte holt die ganze Strecke wieder ins Bild.":
    "Press and hold anywhere on the map to bring the whole route back into view.",
"Der Schalter unten links auf der Karte zeigt das DWD-Radar. Rechts steht, welche Minute zu sehen ist — „jetzt 14:48“, „in 25 min 15:10“. Ein kleiner Kreisel daneben heißt: Bilder laden noch.":
    "The switch at the bottom left of the map shows the DWD radar. On the right it says which minute you are looking at — “now 14:48”, “in 25 min 15:10”. A small spinner beside it means frames are still loading.",
"Play läuft die Bilder durch; der lila Punkt zeigt, wo man zu dieser Minute auf der Strecke wäre.":
    "Play runs through the frames; the purple dot shows where you would be on the route at that minute.",
"Ein Tipp auf die Zeit springt zurück auf jetzt.": "Tapping the time jumps back to now.",
"Der rote Kasten erscheint nur, wenn es eine feste Abfahrt gibt: bei Bahn und Bus, oder wenn eine Ankunftszeit gesetzt ist.":
    "The red box only appears when there is a fixed departure: for trains and buses, or when an arrival time is set.",
"Er zählt bis zum Losgehen — Abfahrt minus Rüstzeit —, unter 10 Minuten sekundengenau.":
    "It counts down to setting off — departure minus preparation — and to the second below 10 minutes.",
"Die Warnungen (Einstellungen → Countdown) kommen als Mitteilung aufs Sperrbild, auch wenn die App zu ist; bei offener App zusätzlich als Ton.":
    "The warnings (Settings → Countdown) arrive as notifications on the lock screen, even when the app is closed; with the app open there is a sound as well.",
"Die große Zahl ist dein aktuelles Tempo, in der Farbe, in der die Linie gerade gezeichnet wird. Der Pfeil auf der Karte zeigt immer dahin, wo du hinfährst.":
    "The large number is your current speed, in the colour the line is being drawn in. The arrow on the map always points the way you are heading.",
"Unten steht, was noch kommt: Reststrecke, Restzeit und die Uhrzeit der Ankunft. Oben in der Leiste stehen dieselben zwei Zahlen statt des Countdowns — losgehen musst du nicht mehr.":
    "Below you see what is left: distance, time and the arrival clock. The same two numbers stand in the toolbar in place of the countdown — there is nothing left to set off for.",
"Oben im roten Band steht, was als Nächstes kommt und in wie vielen Metern. Die Kurven rechnet die App aus der geplanten Linie — es sind Hinweise, keine Navigation, und sie sagt nichts an.":
    "The red banner at the top says what comes next and in how many metres. The turns are computed from the planned line — they are hints, not navigation, and nothing is spoken.",
"Der Abbiegepfeil ist grün und kommt erst 250 m vor der Abbiegung — ein Pfeil, der zwei Kilometer lang „rechts“ sagt, sieht man nicht mehr an, wenn es so weit ist. Rot ist nur eines: dass du neben der Route bist.":
    "The turn arrow is green and only appears 250 m before the turn — an arrow that says “right” for two kilometres is no longer looked at when the moment comes. Red means one thing only: you are off the route.",
"Nach Zoomen oder Schieben kommt die Karte 30 Sekunden später von selbst zu dir zurück. Der Knopf oben links schaltet das Folgen von Hand.":
    "After zooming or panning the map comes back to you by itself 30 seconds later. The button at the top left switches following by hand.",
"Der Knopf daneben hält die Ausrichtung fest — automatisch, hochkant, querformat. Am Lenker will man keine Karte, die sich in der Kurve dreht.":
    "The button beside it locks the orientation — automatic, portrait, landscape. On a handlebar nobody wants a map that turns in a corner.",
"Die Karte geht auf ganze Seite und folgt dir; die gefahrene Linie färbt sich nach Tempo — rot unter 8, grün über 26 km/h. Ein Wisch über die Karte löst das Folgen, der Knopf oben links schaltet es wieder ein.":
    "The map takes the whole screen and follows you; the track is coloured by speed — red below 8, green above 26 km/h. A swipe across the map releases the following, the button at the top left switches it back on.",
"Ein Halt zählt ab fünf Sekunden Stillstand. Als Ampelhalt zählt er, wenn er an einer Ampelkreuzung der geplanten Route liegt — oder wenn er länger als 30 Sekunden dauert, denn so lange steht niemand ohne Grund. Die Schwelle steht in den Einstellungen. Das Stehen vor der ersten Kurbelumdrehung und das Stehen nach der Ankunft zählen nie als Ampel: das ist die eigene Haustür, keine Kreuzung.":
    "A stop counts from five seconds of standing still. It counts as a stop at a light if it lies at a signalised junction of the planned route — or if it lasts longer than 30 seconds, because nobody stands that long for no reason. The threshold is in the settings. Standing before the first pedal stroke and standing after arriving never count as a light: that is your own front door, not a junction.",
"Solche Stellen merkt sich die App. Ab der nächsten Fahrt erkennt sie den Halt dort wieder, und die Ampel zählt auch beim Planen mit.":
    "The app remembers such places. From the next ride on it recognises the stop there, and that light counts when planning too.",
"Dabei zählt jede Aufzeichnung auch, wo sie ohne Halt durchgekommen ist. Eine gelernte Kreuzung kostet beim Planen deshalb nicht den eingestellten Mittelwert, sondern das, was sie dich im Schnitt wirklich gekostet hat — über alle Vorbeifahrten, nicht nur über die Male mit Rot.":
    "Every recording also counts where it got through without stopping. A learned junction therefore costs the plan not the configured average, but what it has really cost you on average — across every pass, not only the ones with a red light.",
"„Pause“ hält die Fahrt an: die Uhr steht, die Ortung ist so lange aus, und die Pause zählt weder zur Fahrzeit noch als Halt. „Weiter“ nimmt sie wieder auf. Das ist auch der Knopf, der während einer Fahrt am meisten Strom spart.":
    "“Pause” stops the ride: the clock stands still, location tracking is off meanwhile, and the break counts neither as ride time nor as a stop. “Resume” picks it up again. It is also the button that saves the most battery during a ride.",
"Stehst du lange an derselben Stelle und ist dort keine Ampel, beendet sich die Aufzeichnung von selbst und zählt bis zum Anfang des Stillstands — der Fall „angekommen und vergessen, auf beenden zu tippen“. Ab wann, steht in den Einstellungen; „aus“ schaltet es ab.":
    "If you stand in the same spot for a long time and there is no traffic light there, the recording ends by itself and counts up to the start of that standstill — the “arrived and forgot to tap end” case. After how long is in the settings; “off” switches it off.",
"Eine Fahrt beginnt quer. Stellst du es während der Fahrt um, gilt das ab dann für jede.":
    "A ride starts in landscape. Change it during a ride and that is how every ride starts from then on.",
"Die Ortung läuft nur zwischen „Fahrt“ und „Fahrt beenden“, auch in der Tasche (iOS zeigt dabei die blaue Leiste). Danach hört sie auf.":
    "Location tracking runs only between “Ride” and “End ride”, including in your pocket (iOS shows the blue bar meanwhile). Afterwards it stops.",
"Menü → Fahrten: alle Aufzeichnungen, nach Jahren und Monaten. Die Überschrift eines Monats zeigt Kilometer, Schnitt und Ampelhalts dieses Monats.":
    "Menu → Rides: every recording, by year and month. A month heading shows that month's kilometres, average and stops at lights.",
"Eine Fahrt antippen zeigt die gefahrene Linie, jede Zahl dazu und die längsten Halte. Die geplante Route liegt dünn und grau daneben — der Unterschied ist die eigentliche Auskunft.":
    "Tapping a ride shows the track, every number belonging to it and the longest stops. The planned route lies thin and grey beside it — the difference is the real answer.",
"Darunter: das Höhenprofil der Fahrt, und was angekündigt war — Ampeln und Schnitt gegen das, was daraus wurde.":
    "Below that: the elevation profile of the ride, and what was announced — lights and average against what came of it.",
"Die Zahlen jeder Fahrt gehen über deine eigene iCloud auf deine anderen Geräte, die gefahrene Linie seit 1.3 ebenfalls — in deine private CloudKit-Datenbank, die außer dir niemand lesen kann. Nach links wischen löscht eine Fahrt — auf diesem Gerät.":
    "The numbers of every ride travel to your other devices through your own iCloud, and since 1.3 the track does too — into your private CloudKit database, which nobody but you can read. Swipe left to delete a ride — on this device.",
"Seite nach unten ziehen und loslassen. Einen Knopf dafür gibt es nicht mehr.":
    "Pull the page down and let go. There is no button for it any more.",
"Das plant alles neu — auch die Warnungen werden auf den neuen Fahrplan gesetzt. Findet die Suche nichts, bleiben die alten Warnungen scharf.":
    "That plans everything again — the warnings are set to the new timetable as well. If the search finds nothing, the old warnings stay armed.",
"Unten steht, von wann der Stand ist.": "At the bottom it says how old the result is.",
"Fahrzeiten mit dem Rad rechnen sich aus der rollenden Geschwindigkeit plus Wartezeit je Ampelkreuzung plus fünf Sekunden je Höhenmeter — Tempo und Wartezeit stehen in den Einstellungen. Wo eigene Fahrten eine Kreuzung schon kennen, gilt deren gemessene Zeit statt der eingestellten.":
    "Bike times come from the rolling speed plus the waiting time per signalised junction plus five seconds per metre of climb — speed and waiting time are in the settings. Where your own rides already know a junction, its measured time counts instead of the configured one.",
"Beide Werte schreibt die App nach jeder Fahrt selbst fort, aus dem Median der letzten Fahrten. Und sobald es genug Fahrten gibt, gilt für die angezeigte Radzeit dein gemessener Tür-zu-Tür-Schnitt — ob er langsamer oder schneller ist als die Rechnung. Welche der Linien die schnellste ist, entscheidet weiter die Rechnung: nur sie kennt den Unterschied zwischen zwei und dreißig Ampeln.":
    "The app keeps both values up to date after every ride, from the median of the recent ones. And as soon as there are enough rides, the bike time shown comes from your measured door-to-door average — whether it is slower or faster than the calculation. Which of the routes is the fastest is still decided by the calculation: only it knows the difference between two and thirty traffic lights.",
"Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet; S-Bahn und Regionalzug zuerst, U-Bahn und Tram nur als markierte Alternative.":
    "Bike + rail only takes trains the VBB service says carry bikes; suburban and regional trains first, metro and tram only as a marked alternative.",
"Fixpunkte (Einstellungen) sind Orte, über die die Strecke führen soll; Verbindungen ohne sie werden ausgegraut und nie empfohlen.":
    "Fixed points (Settings) are places the route should pass; connections without them are greyed out and never recommended.",
"Im Detail einer Radroute zeigt ein Balken, wie viele Kilometer auf Hauptstraße, Nebenstraße, Radweg, Weg und Fußweg liegen. Derselbe Balken steht bei jeder aufgezeichneten Fahrt — dort für die Strecke, die du wirklich gefahren bist.":
    "In the detail of a bike route a bar shows how many kilometres run on main roads, side streets, bike paths, tracks and footpaths. The same bar appears for every recorded ride — there for the way you actually rode.",
"Die Ampelzeile zählt „gehalten von geplant“ und läuft sekündlich mit, solange du stehst; die gelben Punkte auf der Karte sind die Ampeln, die die Planung kennt.":
    "The traffic-light line counts “stopped of planned” and ticks along by the second while you stand; the yellow dots on the map are the lights the plan knows about.",
"Die Ausrichtung, die du im Fahrtmodus wählst, gilt ab dann für jede Fahrt. Nach „Fahrt beenden“ dreht sich die App wieder wie jede andere.":
    "The orientation you pick while riding applies to every ride from then on. After “End ride” the app turns like any other again.",
})

T.update({
"aus": "off",
"Süden": "south",
"Südosten": "south-east",
"Südwesten": "south-west",
"Norden": "north",
"Nordosten": "north-east",
"Osten": "east",
"Westen": "west",
"Nordwesten": "north-west",
"neben der Route": "off the route",
"neben der Route — wird neu geplant": "off the route — recalculating",
"vor %d:%02d h": "%d:%02d h ago",
"die kürzeste Strecke, ganz gleich worüber": "the shortest way, whatever it runs on",
"die wenigsten Meter neben fahrenden Autos": "the fewest metres beside moving cars",
"die Mischung: zügig, wenig neben Autos, wenig Halts": "the mix: quick, little traffic beside you, few stops",
"kürzeste Fahrzeit, Ampeln und Höhenmeter eingerechnet": "shortest time, traffic lights and climbing included",
") — Rad in die Bahn": ") — bike goes on the train",
")) — in den Einstellungen unter „Fahrradmitnahme“ festlegen": ")) — set it under “Bike carriage” in the settings",
"Farbskala der Geschwindigkeit, rot unter 8 bis grün über 26 km/h": "Speed scale, red below 8 to green above 26 km/h",
"Für Linien, die noch in keiner Verbindung vorkamen.": "For lines that have not appeared in a connection yet.",
"Zeit vom Planen bis zum Losgehen. Gilt für jedes Verkehrsmittel.": "Time between planning and walking out. Applies to every mode.",
"Wird einmal abgefragt und in eine Adresse übersetzt. Die App folgt dir nicht.":
    "Asked once and turned into an address. The app does not follow you.",
"Noch keine Linie. Sobald die App eine Verbindung mit Bahn oder Bus findet, stehen deren Linien hier.":
    "No lines yet. As soon as the app finds a connection by train or bus, its lines appear here.",
"Tippen, um zu suchen. Was einmal gewählt wurde, steht beim nächsten Mal oben — je öfter benutzt, desto weiter oben.":
    "Tap to search. Whatever you picked once is at the top next time — the more often used, the further up.",
"Fahrplan und Echtzeit: VBB Verkehrsverbund Berlin-Brandenburg (HAFAS-Fahrinfo).":
    "Timetable and real time: VBB Verkehrsverbund Berlin-Brandenburg (HAFAS Fahrinfo).",
"Karten, Adresssuche und Autorouten: Apple Karten. © Apple Inc. und Mitwirkende.":
    "Maps, address search and car routes: Apple Maps. © Apple Inc. and contributors.",
"Radrouten: BRouter (brouter.de), auf Basis von OpenStreetMap.": "Bike routes: BRouter (brouter.de), based on OpenStreetMap.",
"Ampeln, Straßen und Kartendaten: © OpenStreetMap-Mitwirkende, ODbL 1.0, abgefragt über die Overpass API.":
    "Traffic lights, roads and map data: © OpenStreetMap contributors, ODbL 1.0, queried through the Overpass API.",
"Regenradar und Niederschlagsvorhersage: Deutscher Wetterdienst (DWD), Datenlizenz Deutschland – Namensnennung 2.0.":
    "Rain radar and precipitation forecast: Deutscher Wetterdienst (DWD), Datenlizenz Deutschland – Namensnennung 2.0.",
"Regen entlang der Strecke: Open-Meteo.com, CC BY 4.0, auf Basis von DWD ICON-D2.":
    "Rain along the route: Open-Meteo.com, CC BY 4.0, based on DWD ICON-D2.",
"Dasselbe fürs Auto. Apple Karten liefert meist zwei oder drei Linien; welche davon oben steht, entscheidet diese Liste.":
    "The same for the car. Apple Maps usually offers two or three routes; this list decides which one comes first.",
"Diese Vorschläge stehen oben neben „Jetzt“ zur Wahl — relativ („in 15 min“) oder als Uhrzeit („um 8 Uhr“, heute oder morgen).":
    "These choices sit next to “Now” at the top — relative (“in 15 min”) or as a clock time (“at 8”, today or tomorrow).",
"Fragen, Fehler und Vorschläge gehen über die Support-Seite. Dort steht auch, was dabei hilft: Gerät, Version, Strecke und was die App gezeigt hat.":
    "Questions, bugs and ideas go through the support page. It also says what helps: device, version, route and what the app showed.",
"Der Abfahrtspuffer verschiebt das Losgehen nach vorn, der Ankunftspuffer lässt die Verbindung früher ankommen. Beide zählen nicht zur angezeigten Fahrzeit.":
    "The departure buffer moves setting off earlier, the arrival buffer makes the trip arrive earlier. Neither counts towards the travel time shown.",
"„offen“ heißt: die Verbindung wird weiter vorgeschlagen, aber mit dem Hinweis, dass die Mitnahme ungeklärt ist. „Rad nein“ nimmt sie aus den Rad + Bahn-Vorschlägen heraus.":
    "“Open” means the connection is still suggested, but with the note that bike carriage is unclear. “Bike no” takes it out of the bike + rail suggestions.",
"Die App wird ohne Adressen ausgeliefert. Start und Ziel bleiben nur auf diesem Gerät gespeichert. Mit einem angemeldeten iCloud-Konto gleichen sie sich mit deinen anderen Geräten ab.":
    "The app ships without addresses. Start and destination stay on this device only. With an iCloud account signed in they sync with your other devices.",
"Beim Sortieren und Empfehlen wird jeder Umstieg wie so viele Minuten längere Fahrt gewertet. Eine direkte Verbindung gewinnt also, solange die mit Umstieg nicht mehr als diese Zeit früher ankommt.":
    "When sorting and recommending, every change counts as this many extra minutes of travel. A direct connection therefore wins unless the one with a change arrives more than that earlier.",
"Womit die App plant, wenn sie die Wahl hat. Ab dem gewählten Regen wird nicht mehr die ganze Strecke geradelt, sondern das Rad in die Bahn gestellt — „starker Regen“ heißt also praktisch immer fahren.":
    "What the app plans with when it has a choice. From the selected rain level on, the bike goes on the train instead of riding the whole way — “heavy rain” therefore means riding almost always.",
"Der Countdown oben rechts zählt bis zum Losgehen für Bahn und Bus — und bei „Ankunft um …“ für jede Fahrt. Warnungen kommen als Mitteilung, auch wenn die App zu ist; bei offener App zusätzlich als Ton.":
    "The countdown at the top right counts down to setting off for trains and buses — and with “arrive by …” for every trip. Warnings arrive as notifications even when the app is closed; with the app open there is a sound as well.",
"Punkte, über die die Strecke führen soll, z. B. „S Ostkreuz“ oder „Berlin Hauptbahnhof“. Verbindungen, die nicht daran vorbeikommen, werden ausgegraut ans Ende gestellt und nie empfohlen. Ohne Fixpunkte gilt keine Einschränkung.":
    "Places the route should pass, e.g. “S Ostkreuz” or “Berlin Hauptbahnhof”. Connections that miss them are greyed out at the end and never recommended. Without fixed points nothing is restricted.",
"Diese zwei bekommen überall ein Zeichen — in der Adresssuche, in der Liste der benutzten Adressen und oben auf der Hauptseite — und stehen in der Suche ganz oben. Fahrten zur Arbeit starten mit „Ankunft um …“, Fahrten nach Hause mit „Abfahrt jetzt“; von Hand umschaltbar.":
    "These two are marked everywhere — in the address search, in the list of used addresses and at the top of the main screen — and appear first in the search. Trips to work start with “arrive by …”, trips home with “leave now”; switchable by hand.",
"Von oben nach unten: was gewinnt, wenn zwei Fahrten fast gleichzeitig ankommen. Dieselbe Reihenfolge ordnet die vier Kästen auf der Hauptseite, entscheidet, welcher nach einer Suche geöffnet ist, und in welcher Folge sie sich füllen — das Oberste steht zuerst da, der Rest kommt nach.":
    "Top to bottom: what wins when two trips arrive at nearly the same time. The same order arranges the four boxes on the main screen, decides which one is open after a search, and in which order they fill — the top one is there first, the rest follow.",
"Welche Linien das Rad mitnehmen, weißt du besser als jeder Fahrplan. Die Liste füllt sich mit den Linien, die in gefundenen Verbindungen vorkommen; was die Auskunft selbst zusichert, steht schon auf „ja“. Solange eine Linie offen ist, wird die Fahrt trotzdem vorgeschlagen — mit dem Hinweis, dass die Mitnahme ungeklärt ist.":
    "You know better than any timetable which lines take bikes. The list fills with the lines that appear in the connections found; whatever the service itself guarantees is already set to “yes”. While a line is open the trip is still suggested — with the note that bike carriage is unclear.",
"Die App wird ohne Adressen ausgeliefert. Start, Ziel, die benutzten Adressen und alle Einstellungen gleichen sich über deine iCloud mit deinen anderen Geräten ab. Zum Planen gehen die Koordinaten von Start und Ziel an die Dienste, die die Strecke rechnen (VBB, Transitous, BRouter, Apple Karten, Open-Meteo) — ohne Namen und ohne Adresstext. Sonst verlässt nichts davon deine Geräte und deine iCloud.":
    "The app ships without addresses. Start, destination, the addresses you have used and all settings sync with your other devices through your own iCloud. For planning, the coordinates of start and destination go to the services that compute the route (VBB, Transitous, BRouter, Apple Maps, Open-Meteo) — without any name or address text. Nothing else leaves your devices and your iCloud.",
"„Automatisch“ fragt den VBB, solange Start und Ziel in Berlin/Brandenburg liegen — dort ist er genauer und sagt als Einziger, welcher Zug Räder mitnimmt. Alles darüber hinaus beantwortet Transitous, eine von Freiwilligen betriebene MOTIS-Instanz auf dem bundesweiten DELFI-Datensatz. Transitous plant Rad und Bahn in einem Zug und sucht sich die Bahnhöfe selbst. Woher deren Daten kommen, steht hinter dem Link.":
    "“Automatic” asks the VBB as long as start and destination lie in Berlin/Brandenburg — it is more accurate there and the only one that says which train takes bikes. Everything beyond that is answered by Transitous, a volunteer-run MOTIS instance on the nationwide DELFI dataset. Transitous plans bike and rail in one go and picks the stations itself. Where its data comes from is behind the link.",
"Die obersten so vieler, wie oben eingestellt — die erste wird vorgeschlagen, die anderen erreicht ein Tipp auf den Kasten. Was weiter unten steht, wird gar nicht erst berechnet und spart die Anfrage.\n\n„wenig Autos“ und „wenig Halts“ beantworten zwei verschiedene Fragen: die erste, wie lange man neben fahrenden Autos fährt, die zweite, wie oft man ihretwegen anhalten muss. Die kürzeste Strecke ist selten beides.":
    "The top however many you set above — the first is suggested, the others are one tap on the box away. Whatever sits further down is not computed at all and saves the request.\n\n“Low traffic” and “few stops” answer two different questions: the first how long you ride beside moving cars, the second how often they make you stop. The shortest route is rarely both.",
"Zwei verschiedene Geschwindigkeiten, und sie tun Verschiedenes. Das Rolltempo ist das Tempo beim Fahren, ohne Halte: daraus plus der Wartezeit je Ampelkreuzung und den Höhenmetern rechnet die App jede Linie durch — es entscheidet also, welche Linie die schnellste ist. Der Gesamtschnitt ist die Messung deiner eigenen Fahrten, Tür zu Tür, mit allen Ampeln und Halten darin — er entscheidet, wie lange es dauert. Wäre die Rechnung schneller als dein gemessener Gesamtschnitt, gilt der Gesamtschnitt; auch bei den Zubringern zum Bahnhof, dort aber nur, wenn er die vorsichtigere Zahl ist. Beide Werte schreibt die App nach jeder aufgezeichneten Fahrt selbst fort, aus dem Median der letzten Fahrten, sobald es genug davon gibt; von Hand gestellt gelten sie bis zur nächsten Fahrt. Die Ampelwartezeit ist ein Mittelwert (etwa jede zweite ist grün) und wird je Ampelkreuzung addiert — außer an den Kreuzungen, die deine eigenen Fahrten schon kennen: die kosten, was dort gemessen wurde. Der Puffer gilt je Bahnhof für Rad schieben, Aufzug und Bahnsteig. Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet.":
    "Two different speeds, and they do different things. The rolling speed is your speed while riding, without stops: from it, plus the waiting time per signalised junction and the metres of climb, the app works out every route — so it decides which route is the fastest. The overall average is the measurement of your own rides, door to door, with every light and stop in it — it decides how long it takes. If the calculation were faster than your measured overall average, the average wins; for the legs to the station too, but there only when it is the more cautious number. The app keeps both values up to date after every recorded ride, from the median of the recent ones, as soon as there are enough; set by hand they hold until the next ride. The waiting time per light is an average (roughly every second one is green) and is added per signalised junction — except at the junctions your own rides already know: those cost what was measured there. The buffer applies per station for pushing the bike, the lift and the platform. Bike + rail only takes trains the VBB service says carry bikes.",
"„Automatisch“ lässt den Bildschirm mitdrehen; am Lenker ist das oft im Weg. — Eine Fahrt beginnt quer, oder so, wie du es während der letzten Fahrt zuletzt eingestellt hast; der Knopf dafür steht oben links auf dem Fahrtbildschirm. — Steht die Aufzeichnung länger als eingestellt an derselben Stelle und ist dort keine bekannte Ampel, beendet sie sich selbst und zählt bis zum Anfang des Stillstands; das ist der Fall „angekommen und vergessen, auf beenden zu tippen“. Eine gewollte Unterbrechung ist der Knopf „Pause“ auf dem Fahrtbildschirm: er hält die Uhr an und schaltet die Ortung so lange ab, und die Pause zählt weder zur Fahrzeit noch als Halt. — Während einer Aufzeichnung bleibt der Bildschirm an, bis du die Fahrt beendest; das kostet Strom und ist so gewollt. Er wird aber dunkel, solange du ihn nicht anfasst — und beim ersten Antippen wieder hell, ebenso wenn eine Abbiegung ansteht oder du neben der Route bist. Das ist während einer Fahrt der größte Posten auf der Stromrechnung, größer als die Ortung. — Verlässt du die Route, zeigt ein Pfeil zurück. Neu berechnet wird, was zuerst eintritt: die eingestellte Entfernung (und dann erst nach ein paar Sekunden am Stück, damit ein Bogen um eine Baustelle keine Neuplanung auslöst) oder die eingestellte Zeit, egal wie weit — wer im Kreis um einen gesperrten Weg fährt, kommt nie weit genug weg. Beides „aus“ lässt es beim Pfeil. — Wer länger als die eingestellte Zeit steht, stand an einer Ampel, auch wenn keine Karte dort eine kennt — nur das Stehen vor dem Losfahren und nach dem Ankommen zählt nie, das ist die eigene Haustür. Solche Stellen merkt sich die App und rechnet sie beim nächsten Mal mit ein. Mitgezählt wird auch, wo eine Aufzeichnung ohne Halt durchkam: eine gelernte Kreuzung kostet beim Planen ihre gemessene Zeit über alle Vorbeifahrten, nicht den eingestellten Mittelwert. Sie bleiben auf deinen Geräten und in deiner iCloud.":
    "“Automatic” lets the screen turn with the phone; on a handlebar that is often in the way. — A ride starts in landscape, or however you last set it during a ride; the button for it is at the top left of the ride screen. — If the recording stands in the same spot for longer than set and there is no known traffic light there, it ends by itself and counts up to the start of that standstill; that is the “arrived and forgot to tap end” case. A deliberate break is the “Pause” button on the ride screen: it stops the clock and switches location tracking off meanwhile, and the break counts neither as ride time nor as a stop. — While recording, the screen stays on until you end the ride; that costs battery and is meant to. It does go dark while you are not touching it — and bright again at the first tap, and likewise when a turn is coming up or you are off the route. During a ride that is the largest item on the battery bill, larger than location tracking. — If you leave the route, an arrow points back. It recalculates at whichever comes first: the distance you set (and then only after a few seconds in a row, so that a detour around road works does not trigger a replan) or the time you set, however far away — riding in circles around a closed path never gets you far enough away. Both “off” leaves it at the arrow. — Anyone standing longer than the time set was standing at a traffic light, even where no map knows one — only standing before setting off and after arriving never counts, that is your own front door. The app remembers such places and counts them in next time. It also counts where a recording got through without stopping: a learned junction costs the plan its measured time across every pass, not the configured average. They stay on your devices and in your iCloud.",
})

T.update({
# --- Sätze mit Zahlen: der Schlüssel ist die Form, nicht das Ergebnis
"Rüstzeit: %d min": "Preparation: %d min",
"Umstieg zählt wie %d min": "A change counts as %d min",
"Puffer vor der Abfahrt: %d min": "Buffer before departure: %d min",
"Puffer vor der Ankunft: %d min": "Buffer before arrival: %d min",
"Parkplatzsuche: %d min": "Finding a parking space: %d min",
"Rolltempo ohne Ampeln: %d km/h": "Rolling speed without lights: %d km/h",
"Puffer am Bahnhof: %d min": "Buffer at the station: %d min",
"Wartezeit je Ampel: %d s": "Waiting time per light: %d s",
"Radweg zum Bahnhof: bis %@ km": "Ride to the station: up to %@ km",
"%d m neben der Route": "%d m off the route",
"%d min daneben": "%d min off the route",
"Ampelhalt ab %d s": "Counts as a light from %d s",
"%d s ohne Berührung": "%d s without a touch",
"%d min Halt": "%d min standing",
"Gemessen aus %d Fahrten": "Measured from %d rides",
"An %d %% der Ampeln gehalten": "Stopped at %d %% of the lights",
"Ø %@ je Halt · Ø %@ je Ampel · %d Vorbeifahrten": "avg %@ per stop · avg %@ per light · %d passes",
"%@ neben der Route, Richtung %@": "%@ off the route, heading %@",
"Nächste Abbiegung %@ in %@": "Next turn %@ in %@",
"Fahrzeit %@": "Ride time %@",
"Schnitt %@, geplant %@": "Average %@, planned %@",
"Schnitt %@": "Average %@",
"noch %@": "%@ to go",
"Noch %@, Ankunft %@": "%@ to go, arriving %@",
"%@ länger als geplant": "%@ longer than planned",
"%@ schneller als geplant": "%@ faster than planned",
"Höhenprofil, %d Höhenmeter bergauf": "Elevation profile, %d metres of climbing",
"%@ ab": "from %@",
"%d von %d": "%d of %d",
"Ø %d km/h": "avg %d km/h",
"Radroute: %@": "Bike route: %@",
"%@ an Hauptstraßen": "%@ on main roads",
"%d Hauptstraßen queren": "%d main roads to cross",
"Route von BRouter (%@)": "Route from BRouter (%@)",
"Autoroute: %@": "Car route: %@",
"Gl. %@": "Pl. %@",
"Nochmal tippen für die nächste von %d Möglichkeiten, lang drücken für die beste":
    "Tap again for the next of %d options, press and hold for the best one",
"ab %@": "from %@",
"%d min Rüstzeit": "%d min preparation",
"Ausrichtung: %@. Tippen für %@.": "Orientation: %@. Tap for %@.",
"Losgehen in %@": "Leave in %@",
"Regenradar %@, %@. Tippen für jetzt.": "Rain radar %@, %@. Tap for now.",
"vor %d h": "%d h ago",
"vor %d min": "%d min ago",
"in %d min": "in %d min",
"in %d h": "in %d h",
"in %d h %d min": "in %d h %d min",
"Berechnet %@. Tippen für neu berechnen.": "Computed %@. Tap to plan again.",
"Stand %@ · %@": "As of %@ · %@",
"Stand %@": "As of %@",
"gerade eben": "just now",
"In %d min los": "Leave in %d min",
"Du standst länger als %d Minuten an derselben Stelle — die Aufzeichnung ist gespeichert.":
    "You stood in the same spot for more than %d minutes — the recording has been saved.",
"Regenvorhersage nicht verfügbar: %@": "Rain forecast unavailable: %@",
"Kein Bahnhof mit Radmitnahme im Umkreis von %d km": "No station that takes bikes within %d km",
"%d min Puffer je Bahnhof fürs Rad": "%d min buffer per station for the bike",
"Schauer möglich (%d %%)": "Showers possible (%d %%)",
"Die Linien reisen gerade nicht in deine iCloud (%@).": "Your tracks are not reaching iCloud right now (%@).",
"Pause · %@": "Paused · %@",
"Fahrradmitnahme ungeklärt: %@ — in den Einstellungen unter „Fahrradmitnahme“ festlegen":
    "Bike carriage unclear: %@ — set it under “Bike carriage” in the settings",
"Regen auf der Radstrecke%@ — Rad in die Bahn": "Rain on the bike route%@ — bike goes on the train",
})

T.update({
"Rad": "Bike",
"Rad+Bahn": "Bike+rail",
"wenig Autos": "few cars",
"wenig Halts": "few stops",
"wenig Ampeln": "few lights",
"am seltensten wegen des Verkehrs anhalten": "stopping for traffic least often",
"%@ — und zugleich %@": "%@ — and at the same time %@",
"direkt": "direct",
"%d× umsteigen": "%d changes",
"trocken": "dry",
"leichter Regen": "light rain",
"Regen": "rain",
"starker Regen": "heavy rain",
"scharf links": "sharp left",
"links": "left",
"halb links": "bear left",
"geradeaus": "straight on",
"halb rechts": "bear right",
"rechts": "right",
"scharf rechts": "sharp right",
"Ziel": "Destination",
"Start": "Start",
"inkl. %d min Parkplatzsuche": "incl. %d min to park",
"sucht …": "searching …",
"los %@": "leave %@",
"%d hm": "%d m climb",
"U-Bahn/Tram": "Metro/tram",
"%@ · %d×": "%@ · %d×",
"%@ → %@": "%@ → %@",
"%d/%d Ampeln": "%d/%d lights",
"%d Ampelhalts": "%d stops at lights",
"%@ gewartet · Ø %@": "%@ waiting · avg %@",
"gestanden · %d sonst": "standing · %d other",
"fertig machen %@": "get ready %@",
"%d Ampeln · %@": "%d lights · %@",
"%d× quer": "%d crossings",
"%d Ampeln": "%d lights",
"→ %@": "→ %@",
"%d min vorher": "%d min before",
"Fahrradmitnahme": "Bike carriage",
"%d offen": "%d open",
"Vorschlag": "Suggestion",
"Vergessen": "Forget",
"Zeit": "Time",
"Karte": "Map",
"Aktualisieren": "Refreshing",
"Version %@": "Version %@",
"%@ · direkt": "%@ · direct",
"neu berechnen": "plan again",
"umsteigen": "change",
"unterwegs · %@": "under way · %@",
"angekommen · %@": "arrived · %@",
"rollend": "rolling",
"andere Halte": "other stops",
"%@ · Ø %@": "%@ · avg %@",
"%@ · %d Wege": "%@ · %d routes",
"los %@ · %@": "leave %@ · %@",
"ABGEFAHREN": "DEPARTED",
"Fehler": "Error",
"nichts": "nothing",
})

T.update({
"um %d Uhr": "at %d",
"um %d:%02d": "at %d:%02d",
"%@ · %d× um": "%@ · %d×",
"%@ · %d Fahrt · Ø %@": "%@ · %d ride · avg %@",
"%@ · %d Fahrten · Ø %@": "%@ · %d rides · avg %@",
"%d× · %@ · Ø %@ · %d Ampeln": "%d× · %@ · avg %@ · %d lights",
"1× umsteigen": "1 change",
"%d Ampelhalt": "%d stop at a light",
"Route": "Route",
})
