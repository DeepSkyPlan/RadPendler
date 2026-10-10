#!/usr/bin/env python3
"""Das Paket für App Store Connect: jedes Feld als eigene Datei, die Screenshots daneben.

    ./dev store            # baut build/appstore-<version>/ und ein Zip daneben

Liest `appstore/metadata.md` — die eine Stelle, an der die Texte gepflegt werden — und
legt nichts in App Store Connect an. Bricht ab, wenn ein Feld über seiner Grenze liegt,
ein Screenshot die falsche Größe hat oder „Was ist neu" für die Fassung fehlt: am
08.10.2026 stand die deutsche Beschreibung zwei Tage lang bei 4094 von 4000 Zeichen.
"""
import re, shutil, struct, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = (ROOT / "appstore/metadata.md").read_text(encoding="utf-8")
LIMITS = {"name": 30, "untertitel": 30, "werbetext": 170, "beschreibung": 4000, "keywords": 100, "was-ist-neu": 4000}
SHOTS = {"iphone-6.3": (1206, 2622), "iphone-6.5": (1284, 2778), "ipad-13": (2064, 2752), "watch-46": (416, 496)}


def setting(key):
    return re.search(rf'^\s*{key}: "(.+?)"', (ROOT / "project.yml").read_text(), re.M).group(1)


def section(heading, start=0):
    """Der Text unter einer Überschrift, bis zur nächsten gleicher oder höherer Ebene."""
    m = re.search(rf"^{re.escape(heading)}.*$", META[start:], re.M)
    if not m:
        sys.exit(f"metadata.md: Abschnitt „{heading}“ fehlt")
    level = len(heading.split(" ")[0])
    rest = META[start + m.end():]
    end = re.search(rf"^#{{1,{level}}} ", rest, re.M)
    return rest[: end.start() if end else len(rest)]


def block(text, n=0):
    found = re.findall(r"```\n(.*?)```", text, re.S)
    return found[n].strip() if len(found) > n else None


def line(text):
    """Ein Feld ohne Kasten: der erste Absatz, ohne die Zeichenzahl in eckigen Klammern."""
    paragraph = text.strip().split("\n\n")[0]
    return re.sub(r"\s*\[\d+\]\s*$", "", " ".join(l.strip() for l in paragraph.split("\n"))).strip()


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def main():
    version, build = setting("MARKETING_VERSION"), setting("CURRENT_PROJECT_VERSION")
    english = META.index("## Englische Fassung")
    news = section(f"## Was ist neu ({version})")
    fields = {
        "de": {
            "name": line(section("## Name (max 30)")),
            "untertitel": line(section("## Untertitel (max 30)")),
            "werbetext": line(section("## Werbetext (max 170)")),
            "beschreibung": block(section("## Beschreibung (max 4000)")),
            "keywords": line(section("## Keywords (max 100")),
            "was-ist-neu": block(news, 0),
        },
        "en": {
            "name": line(section("### Name (max 30)", english)),
            "untertitel": line(section("### Subtitle (max 30)", english)),
            "werbetext": line(section("### Promotional text (max 170)", english)),
            "beschreibung": block(section("### Description", english)),
            "keywords": line(section("### Keywords (max 100)", english)),
            "was-ist-neu": block(news, 1),
        },
    }
    names = {"en": {"untertitel": "subtitle", "werbetext": "promotional-text", "beschreibung": "description",
                    "was-ist-neu": "whats-new"}}
    problems, table = [], []
    for lang, values in fields.items():
        for key, value in values.items():
            if not value:
                problems.append(f"{lang}/{key}: fehlt in metadata.md")
                continue
            n = len(value)
            table.append((lang, names.get(lang, {}).get(key, key), n, LIMITS[key]))
            if n > LIMITS[key]:
                problems.append(f"{lang}/{key}: {n} Zeichen, erlaubt {LIMITS[key]}")
    shots = {}
    for folder, size in SHOTS.items():
        files = sorted((ROOT / "appstore/screenshots" / folder).glob("*.png"))
        shots[folder] = files
        if not files:
            problems.append(f"screenshots/{folder}: keine Bilder")
        for f in files:
            if png_size(f) != size:
                problems.append(f"screenshots/{folder}/{f.name}: {png_size(f)[0]} × {png_size(f)[1]}, verlangt {size[0]} × {size[1]}")
    if problems:
        sys.exit("Store-Paket NICHT gebaut:\n  " + "\n  ".join(problems))

    review = re.search(r"\*“(Background modes.*?)”\*", META, re.S)
    urls = {k: line(section(f"## {k}")) for k in ("Support-URL", "Marketing-URL", "Datenschutz-URL", "Copyright")}
    out = ROOT / "build" / f"appstore-{version}"
    shutil.rmtree(out, ignore_errors=True)
    for lang, values in fields.items():
        (out / lang).mkdir(parents=True)
        for key, value in values.items():
            (out / lang / f"{names.get(lang, {}).get(key, key)}.txt").write_text(value + "\n", encoding="utf-8")
    for folder, files in shots.items():
        (out / "screenshots" / folder).mkdir(parents=True)
        for f in files:
            shutil.copy(f, out / "screenshots" / folder / f.name)
    (out / "pruefhinweis-en.txt").write_text(" ".join(review.group(1).split()) + "\n" if review else "", encoding="utf-8")
    rows = "\n".join(f"| {lang} | {key} | {n} | {limit} |" for lang, key, n, limit in table)
    counts = ", ".join(f"{folder}: {len(files)}" for folder, files in shots.items())
    (out / "LIESMICH.md").write_text(f"""# RadPendler {version} (Build {build}) — Paket für App Store Connect

Gebaut aus `appstore/metadata.md` mit `./dev store`. Hier wird nichts hochgeladen; jedes Feld
ist eine Datei zum Kopieren, die Bilder liegen in der Reihenfolge ihrer Dateinummern.

## In App Store Connect

1. Neue Version **{version}** anlegen, Build **{build}** auswählen.
2. Je Sprache (Deutsch, Englisch USA): Werbetext, Beschreibung, Keywords und „Neue Funktionen“
   aus `de/` bzw. `en/` einfügen. Name und Untertitel nur, wenn sie sich geändert haben.
3. Screenshots: die alten im Schacht löschen, dann `screenshots/iphone-6.3/` (1206 × 2622) in den
   Schacht „iPhone 6,1″ oder 6,3″“ — bietet App Store Connect stattdessen 6,5″ an, dorthin
   `screenshots/iphone-6.5/` (1284 × 2778). Ein Satz genügt, die Größe muss zum Schacht passen.
   `screenshots/ipad-13/` in den 13″-Schacht, `screenshots/watch-46/` zur Apple Watch.
   Bilder für das iPhone Duo sind erst für Einreichungen ab April 2027 Pflicht.
4. „Kopfzeile und Suchergebnisse“ leer lassen — freiwillige Werbeflächen.
5. App-Prüfung → Notizen: den Text aus `pruefhinweis-en.txt`.
6. Support-URL {urls['Support-URL']} · Marketing-URL {urls['Marketing-URL']} ·
   Datenschutz-URL {urls['Datenschutz-URL']} · Copyright {urls['Copyright']}
7. **Vorher** die Datenschutzseite veröffentlichen (`appstore/pages/radpendler-privacy/`), damit
   sie beschreibt, was diese Fassung tut.

## Längen

| Sprache | Feld | Zeichen | Grenze |
|---|---|---|---|
{rows}

Screenshots — {counts}.
""", encoding="utf-8")
    archive = ROOT / "build" / f"RadPendler-AppStore-{version}.zip"
    archive.unlink(missing_ok=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(out.rglob("*")):
            if f.is_file():
                z.write(f, Path(out.name) / f.relative_to(out))
    for lang, key, n, limit in table:
        print(f"  {lang}/{key}: {n} von {limit}")
    print(f"  Screenshots — {counts}")
    print(f"Store-Paket {version} ({build}): {out}\n{archive}")


if __name__ == "__main__":
    main()
