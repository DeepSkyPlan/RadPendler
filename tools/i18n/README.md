# Zweisprachig, und wie ein neuer Text dazukommt

Die App spricht Deutsch und Englisch; umgeschaltet wird im Burger-Menü, und die
Umstellung wirkt **sofort**. Der Weg dahin steht in `Shared/Language.swift` —
kurz: SwiftUI lässt sich die Sprache von innen nicht umstellen, also fragt die
App die Systemsprache gar nicht erst, sondern liest mit `L(…)` unmittelbar aus
dem Verzeichnis der gewählten Sprache.

**Für jeden neuen Text sind es zwei Handgriffe:**

1. Im Quelltext `L("Neuer Text")` schreiben statt `"Neuer Text"`. Mit Zahlen
   darin: `L("%d Ampeln", n)` — der Schlüssel ist die Form mit Platzhaltern,
   nie das fertige Ergebnis.
2. Die englische Fassung in `de_en.py` eintragen und `python3 tools/i18n/sync.py`
   laufen lassen. Das schreibt `RadPendler/Resources/Localizable.xcstrings` neu
   und meldet jeden Schlüssel, der noch keine Übersetzung hat.

`sync.py` liest den Quelltext, nicht den Katalog: was nicht mehr aufgerufen
wird, fliegt beim nächsten Lauf heraus. Fehlt eine Übersetzung, zeigt die App
den deutschen Schlüssel — besser als ein Platzhalter auf dem Bildschirm.

`apply.py` war das Werkzeug für die erste Umstellung: es packt `L(…)` um jedes
Literal, das in `de_en.py` steht. Für einzelne neue Texte braucht es das nicht.

**Was nicht übersetzt wird:** Vergleichsmuster fremder Dienste (die
Fahrradmitnahme-Texte der VBB-Auskunft), der User-Agent, JSON-Schlüssel,
SF-Symbole und alles, was in `UserDefaults` landet. `apply.py` überspringt
solche Zeilen; wer von Hand arbeitet, achtet selbst darauf.

Geprüft wird das Ganze von `RadPendlerTests/LanguageTests.swift`: ob das
Sprachverzeichnis im Paket liegt, ob Texte und Formate auf Englisch
herauskommen, und ob die Zahlen der gewählten Sprache folgen statt der des
Telefons („1.5 km" gegen „1,5 km").
