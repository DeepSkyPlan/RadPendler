#!/bin/bash
# ./dev testflight [version]  — eine Fassung zu TestFlight, in einem Zug:
#
#   1. Arbeitsbaum muss sauber sein (was hochgeht, steht danach als Commit da).
#   2. Buildnummer +1, auf Wunsch neue Version; „## Unveröffentlicht" im
#      CHANGELOG wird zu „## <version> (Build <n>)".
#   3. generate, alle Tests, clean archive, Export mit Upload (API-Schlüssel
#      aus ~/.appstoreconnect/ — liegt nicht im Repo).
#   4. Commit „<version> (<n>) an TestFlight" und push.
#
# Scheitert ein Schritt, werden project.yml und CHANGELOG zurückgesetzt.
# Nur auf Ansage des Nutzers benutzen. SKIP_TESTS=1 überspringt die Tests,
# DRY_RUN=1 baut nur das Archiv und setzt alles zurück.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -z "$(git status --porcelain)" ] || { echo "Arbeitsbaum nicht sauber — erst committen." >&2; exit 1; }

KEY_ID=PAGC3W2GBL
KEY=~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8
ISSUER=$(cat ~/.appstoreconnect/issuer_id.txt)
[ -r "$KEY" ] || { echo "API-Schlüssel fehlt: $KEY" >&2; exit 1; }

old_build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\([0-9]*\)"/\1/p' project.yml | head -1)
old_version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
build=$((old_build + 1))
version=${1:-$old_version}

restore() { git checkout -- project.yml CHANGELOG.md 2>/dev/null || true; }
trap 'echo "Abgebrochen — project.yml und CHANGELOG zurückgesetzt." >&2; restore' ERR

sed -i '' "s/CURRENT_PROJECT_VERSION: \"$old_build\"/CURRENT_PROJECT_VERSION: \"$build\"/; s/MARKETING_VERSION: \"$old_version\"/MARKETING_VERSION: \"$version\"/" project.yml
if grep -q '^## Unveröffentlicht' CHANGELOG.md; then
  sed -i '' "1,/^## Unveröffentlicht/s/^## Unveröffentlicht/## $version (Build $build)/" CHANGELOG.md
elif ! grep -q "^## $version " CHANGELOG.md; then
  echo "Warnung: kein CHANGELOG-Abschnitt für $version." >&2
fi
grep -q "Was ist neu ($version)" appstore/metadata.md 2>/dev/null \
  || echo "Hinweis: appstore/metadata.md hat kein „Was ist neu ($version)“ — erst zur Einreichung nötig." >&2

echo "→ $version ($build)"
xcodegen generate >/dev/null
if [ -z "${SKIP_TESTS:-}" ]; then
  xcodebuild -project RadPendler.xcodeproj -scheme RadPendler \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test 2>&1 | grep -E "error:|Executed [0-9]+ tests|TEST (SUCC|FAIL)" | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Tests rot." >&2; false; }
fi

WORK=$(mktemp -d)
xcodebuild -project RadPendler.xcodeproj -scheme RadPendler -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/RadPendler.xcarchive" clean archive 2>&1 \
  | grep -E "error:|ARCHIVE (SUCC|FAIL)" | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Archiv gescheitert." >&2; false; }

if [ -n "${DRY_RUN:-}" ]; then
  trap - ERR; restore; xcodegen generate >/dev/null; rm -rf "$WORK"
  echo "Probelauf: Archiv $version ($build) gebaut, nichts hochgeladen, nichts committet."; exit 0
fi
xcodebuild -exportArchive -archivePath "$WORK/RadPendler.xcarchive" \
  -exportOptionsPlist tools/ExportOptions.plist -exportPath "$WORK/export" \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" 2>&1 \
  | grep -E "error|Upload succeeded|EXPORT (SUCC|FAIL)" | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Upload gescheitert." >&2; false; }
# Das Archiv bleibt: ohne seine dSYMs ist ein Absturzbericht aus TestFlight
# nur eine Liste von Adressen (03.10.2026 — Build 49 musste nachgebaut werden).
# Dort, wo Xcodes Organizer es findet.
KEEP="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$KEEP"
mv "$WORK/RadPendler.xcarchive" "$KEEP/RadPendler $version ($build).xcarchive"
rm -rf "$WORK"
trap - ERR

git add project.yml CHANGELOG.md
git commit -q -m "$version ($build) an TestFlight"
git push -q
echo "✓ $version ($build) hochgeladen und als $(git rev-parse --short HEAD) gepusht. Apple verarbeitet 5–15 min."
