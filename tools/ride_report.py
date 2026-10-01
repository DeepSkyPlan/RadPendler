#!/usr/bin/env python3
"""Eine geteilte Fahrt (RadPendler-Fahrt-*.json) als Karte und Befund.

Die App schreibt die Datei unter Fahrten → Fahrt → Teilen. Landet sie per
„In Dateien sichern" in iCloud Drive oder per AirDrop in ~/Downloads, findet
dieses Skript die jüngste von selbst:

    python3 tools/ride_report.py            # die jüngste
    python3 tools/ride_report.py <datei>    # eine bestimmte

Ergebnis: eine HTML-Seite unter ~/_claude.code/_reports/radpendler-fahrten/,
in Chrome geöffnet. Gefahrene Linie nach Genauigkeit gefärbt (grün ≤ 10 m,
gelb ≤ 30 m, rot darüber), geplante Linie blau gestrichelt, jede Neuplanung
grau, das Protokoll als Marker und Tabelle, dazu Lücken und Sprünge.
Bleibt auf dem Mac — die Datei enthält die Wohnadresse.
"""
import glob
import html
import json
import math
import os
import subprocess
import sys
from datetime import datetime

OUT = os.path.expanduser("~/_claude.code/_reports/radpendler-fahrten")
SEARCH = [os.path.expanduser("~/Downloads"),
          os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs")]


def newest():
    found = []
    for root in SEARCH:
        found += glob.glob(os.path.join(root, "**", "RadPendler-Fahrt-*.json"), recursive=True)
    if not found:
        sys.exit("Keine RadPendler-Fahrt-*.json in ~/Downloads oder iCloud Drive gefunden.")
    return max(found, key=os.path.getmtime)


def dist(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((a[0] - b[0]) * 111320, (a[1] - b[1]) * 111320 * k)


def t(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone()


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else newest()
    d = json.load(open(path))
    ride, track = d["ride"], d["track"]
    pts = track["points"]
    ev = track.get("events") or []

    # Befund: Genauigkeit, Lücken, Sprünge.
    acc = [p["a"] for p in pts if p.get("a") is not None]
    gaps, jumps = [], []
    for a, b in zip(pts, pts[1:]):
        dt = (t(b["t"]) - t(a["t"])).total_seconds()
        m = dist((a["lat"], a["lon"]), (b["lat"], b["lon"]))
        if dt > 15:
            gaps.append((t(a["t"]), dt, m))
        if dt > 0 and m / dt > 16.7 and ride["mode"] == "bike":
            jumps.append((t(a["t"]), m, m / dt * 3.6))
    counts = {}
    for e in ev:
        counts[e["kind"]] = counts.get(e["kind"], 0) + 1

    def pct(x):
        return f"{100 * x / len(acc):.0f} %" if acc else "–"

    facts = [
        ("Strecke", f"{ride['meters'] / 1000:.1f} km, {len(pts)} Punkte, App {d.get('app') or '?'}"),
        ("Genauigkeit", "nicht aufgezeichnet (vor 1.9.2)" if not acc else
         f"Median {sorted(acc)[len(acc) // 2]:.0f} m · ≤10 m {pct(sum(a <= 10 for a in acc))} · "
         f"> 30 m {pct(sum(a > 30 for a in acc))} · max {max(acc):.0f} m"),
        ("Lücken > 15 s", f"{len(gaps)}" + (": " + ", ".join(f"{g[0]:%H:%M:%S} {g[1]:.0f} s/{g[2]:.0f} m" for g in gaps[:8]) if gaps else "")),
        ("Sprünge > 60 km/h", f"{len(jumps)}" + (": " + ", ".join(f"{j[0]:%H:%M:%S} {j[2]:.0f} km/h" for j in jumps[:8]) if jumps else "")),
        ("Protokoll", ", ".join(f"{k} {v}" for k, v in counts.items()) or "keins (vor 1.9.2)"),
        ("Halte", f"{ride['signalStops']} an Ampeln, {ride['otherStops']} sonstige"),
    ]

    segs = []
    for a, b in zip(pts, pts[1:]):
        acc_b = b.get("a")
        color = "#888" if acc_b is None else "#1a9850" if acc_b <= 10 else "#fdae61" if acc_b <= 30 else "#d73027"
        segs.append([[a["lat"], a["lon"]], [b["lat"], b["lon"]], color])
    planned = [[p["lat"], p["lon"]] for p in track.get("planned", [])]
    routes = [[[p["lat"], p["lon"]] for p in r] for r in (track.get("routes") or [])]
    markers = [[e["lat"], e["lon"], f"{t(e['t']):%H:%M:%S} {e['kind']}" + (f" — {e['note']}" if e.get("note") else "")]
               for e in ev]

    rows = "".join(f"<tr><td>{t(e['t']):%H:%M:%S}</td><td>{html.escape(e['kind'])}</td>"
                   f"<td>{html.escape(e.get('note') or '')}</td></tr>" for e in ev)
    fact_rows = "".join(f"<tr><th>{k}</th><td>{html.escape(v)}</td></tr>" for k, v in facts)
    name = os.path.splitext(os.path.basename(path))[0]
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><title>{name}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>body{{font:14px -apple-system,sans-serif;margin:16px;max-width:1100px}}#map{{height:560px;border-radius:8px}}
table{{border-collapse:collapse;margin:10px 0}}td,th{{padding:3px 8px;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}}
th{{color:#555;font-weight:600}}.legend span{{display:inline-block;width:18px;height:4px;margin:0 4px 2px 10px}}</style></head><body>
<h2>{html.escape(ride['origin'])} → {html.escape(ride['destination'])}, {t(ride['started']):%d.%m.%Y %H:%M}</h2>
<div class="legend">Genauigkeit <span style="background:#1a9850"></span>≤10 m<span style="background:#fdae61"></span>≤30 m
<span style="background:#d73027"></span>&gt;30 m <span style="background:#2c7bb6"></span>geplant <span style="background:#999"></span>neu geplant</div>
<div id="map"></div><table>{fact_rows}</table><h3>Protokoll</h3><table>{rows}</table>
<script>
const map=L.map('map');L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png',{{maxZoom:19,attribution:'© OpenStreetMap'}}).addTo(map);
const planned={json.dumps(planned)}, routes={json.dumps(routes)}, segs={json.dumps(segs)}, marks={json.dumps(markers)};
routes.forEach((r,i)=>i>0&&L.polyline(r,{{color:'#999',weight:4,opacity:.7}}).addTo(map));
if(planned.length)L.polyline(planned,{{color:'#2c7bb6',weight:4,dashArray:'8 8'}}).addTo(map);
segs.forEach(s=>L.polyline([s[0],s[1]],{{color:s[2],weight:5}}).addTo(map));
marks.forEach(m=>L.circleMarker([m[0],m[1]],{{radius:6,color:'#000',fillColor:'#fff',fillOpacity:1}}).bindTooltip(m[2]).addTo(map));
const all=segs.flatMap(s=>[s[0],s[1]]).concat(planned);if(all.length)map.fitBounds(all);
</script></body></html>"""
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, name + ".html")
    open(out, "w").write(page)
    print(out)
    for k, v in facts:
        print(f"{k}: {v}")
    subprocess.run(["open", "-a", "Google Chrome", out])


if __name__ == "__main__":
    main()
