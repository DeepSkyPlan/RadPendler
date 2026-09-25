# -*- coding: utf-8 -*-
"""Setzt `L(…)` um jedes übersetzte Literal und schreibt den Katalog.

Ersetzt **nur**, was in `de_en.T` steht — alles andere bleibt unangetastet.
Zeilen, in denen ein Literal kein Anzeigetext sein kann (Schlüssel, Muster,
URLs), werden übersprungen.
"""
import io, json, re, sys, glob, os
sys.path.insert(0, os.path.dirname(__file__))
from de_en import T

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKIP = ('forKey:', 'URL(string:', 'hasPrefix', 'hasSuffix', '.contains(', 'queryItems',
        'JSONSerialization', 'UserDefaults', 'Notification.Name', '"client"',
        'range(of:', 'setValue(', 'addingPercentEncoding', 'User-Agent', 'httpHeaderField')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')

def unescape(s):
    return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')

def apply(dry=True):
    files = sorted(glob.glob(os.path.join(ROOT, 'RadPendler/**/*.swift'), recursive=True)
                   + glob.glob(os.path.join(ROOT, 'RadPendlerWatch/*.swift'))
                   + glob.glob(os.path.join(ROOT, 'Shared/*.swift')))
    hits, used = [], set()
    for f in files:
        if f.endswith('Language.swift'): continue
        src = io.open(f, encoding='utf-8').read().split('\n')
        out, changed = [], 0
        for n, line in enumerate(src, 1):
            stripped = line.strip()
            if stripped.startswith('//') or any(k in line for k in SKIP) or re.search(r'case\s+\w+\s*=\s*"', line):
                out.append(line); continue
            def repl(m):
                nonlocal changed
                lit = m.group(1)
                if lit not in T: return m.group(0)
                # Schon eingepackt? `L("…")` nicht doppelt umwickeln.
                before = line[:m.start()].rstrip()
                if before.endswith('L('): return m.group(0)
                changed += 1
                used.add(lit)
                hits.append((os.path.relpath(f, ROOT), n, lit))
                return 'L(' + m.group(0) + ')'
            new = LIT.sub(repl, line)
            out.append(new)
        if changed and not dry:
            io.open(f, 'w', encoding='utf-8').write('\n'.join(out))
    return hits, used

def catalog(used):
    path = os.path.join(ROOT, 'RadPendler/Resources/Localizable.xcstrings')
    d = json.load(io.open(path, encoding='utf-8'))
    d.setdefault('sourceLanguage', 'de')
    d.setdefault('version', '1.0')
    for lit in sorted(used):
        key = unescape(lit)
        en = unescape(T[lit])
        entry = d['strings'].setdefault(key, {})
        entry.setdefault('extractionState', 'manual')
        entry.setdefault('localizations', {})
        entry['localizations']['en'] = {'stringUnit': {'state': 'translated', 'value': en}}
    json.dump(d, io.open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    return len(d['strings'])

if __name__ == '__main__':
    dry = '--write' not in sys.argv
    hits, used = apply(dry=dry)
    print(('PROBE' if dry else 'GESCHRIEBEN') + f": {len(hits)} Stellen, {len(used)} verschiedene Texte")
    if not dry:
        print("Katalog:", catalog(used), "Einträge")
    from collections import Counter
    for f, n in Counter(h[0] for h in hits).most_common(): print(f"{n:4d}  {f}")
