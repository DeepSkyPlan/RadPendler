# -*- coding: utf-8 -*-
"""Schreibt den Katalog aus dem, was im Quelltext wirklich in `L(…)` steht.

Ausgabe: wie viele Schlüssel im Code stehen, wie viele davon übersetzt sind
und welche fehlen. Der Katalog bekommt nur, was beides hat.
"""
import io, json, re, sys, glob, os
sys.path.insert(0, os.path.dirname(__file__))
from de_en import T

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CALL = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')

def unescape(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')

def keys():
    found = {}
    for f in (glob.glob(os.path.join(ROOT, 'RadPendler/**/*.swift'), recursive=True)
              + glob.glob(os.path.join(ROOT, 'RadPendlerWatch/*.swift'))
              + glob.glob(os.path.join(ROOT, 'Shared/*.swift'))):
        for line in io.open(f, encoding='utf-8'):
            if line.strip().startswith('//'): continue
            for m in CALL.finditer(line):
                found.setdefault(m.group(1), set()).add(os.path.relpath(f, ROOT))
    return found

def write(found, path):
    d = {'sourceLanguage': 'de', 'strings': {}, 'version': '1.0'}
    if os.path.exists(path):
        d = json.load(io.open(path, encoding='utf-8'))
    # Wir schreiben den Katalog neu aus dem Code: was nicht mehr aufgerufen
    # wird, hat darin nichts mehr verloren.
    strings = {}
    missing = []
    for raw in sorted(found):
        key = unescape(raw)
        if raw in T:
            strings[key] = {'extractionState': 'manual',
                            'localizations': {'en': {'stringUnit': {'state': 'translated',
                                                                    'value': unescape(T[raw])}}}}
        else:
            missing.append(raw)
            strings[key] = {'extractionState': 'manual', 'localizations': {}}
    d['strings'] = strings
    json.dump(d, io.open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    return missing

if __name__ == '__main__':
    found = keys()
    missing = write(found, os.path.join(ROOT, 'RadPendler/Resources/Localizable.xcstrings'))
    print(f"{len(found)} Schlüssel im Quelltext, {len(found) - len(missing)} übersetzt, {len(missing)} offen")
    for m in missing: print("  OFFEN:", m[:90])
