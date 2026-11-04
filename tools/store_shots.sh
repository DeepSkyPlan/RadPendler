#!/bin/zsh
# ./dev shots — die Store-Bilder auf eigenen Simulatoren (RP-…), damit keine andere Sitzung
# dazwischenfunkt: iPhone 6,3″ (1206 × 2622), 6,9″ (1320 × 2868), iPad 13″ (2064 × 2752).
# Getippt wird von RadPendlerUITests/ScreenshotTests (Schema RadPendlerShots); dieses Skript
# setzt die Adressen (Alexanderplatz → Potsdam Hbf, nie echte), fährt die Ortung für den
# Fahrtmodus und holt die Bilder aus dem Testergebnis. Jedes Gerät läuft zweimal: der erste
# Lauf füllt Kartenkacheln und Ampeldaten, der zweite gibt die Bilder (metadata.md, „Neu aufnehmen“).
# Die Uhr (watch-46) hat keinen UI-Test und bleibt hier außen vor.
#   ./dev shots [iphone-6.3|iphone-6.9|ipad-13 …]
set -eu
cd "${0:A:h}/.."
OUT=appstore/screenshots
PROJ=RadPendler.xcodeproj
BUNDLE=de.keese.radpendler
"./dev" generate >/dev/null

device() {   # Name, Gerätetyp → UDID, angelegt falls nötig, gebootet
  local id
  id=$(xcrun simctl list devices | grep -F "$1 (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
  [ -n "$id" ] || id=$(xcrun simctl create "$1" "$2")
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 --operatorName ""
  echo "$id"
}

hex() { python3 -c "import sys,json;print(json.dumps(json.loads(sys.argv[1]),ensure_ascii=False).encode().hex())" "$1"; }
ORIGIN='{"name":"Alexanderplatz, 10178 Berlin","latitude":52.5210,"longitude":13.4130,"postalCode":"10178","locality":"Berlin"}'
DEST='{"name":"Potsdam Hauptbahnhof, 14473 Potsdam","latitude":52.3914,"longitude":13.0672,"postalCode":"14473","locality":"Potsdam"}'
# Die ersten anderthalb Kilometer der ersten Radlinie ab Alexanderplatz (siehe metadata.md).
WP=(52.521027,13.412965 52.521108,13.412526 52.521076,13.412018 52.521101,13.411436
    52.520846,13.411566 52.520166,13.410798 52.519841,13.410121 52.519567,13.409550
    52.519224,13.408836 52.519027,13.408223 52.518693,13.407425 52.518458,13.406948
    52.518204,13.406692 52.517692,13.405480 52.517319,13.404595 52.516988,13.403797
    52.516733,13.403178 52.516530,13.402679 52.516298,13.402026 52.516070,13.401468
    52.516217,13.400939 52.515984,13.400120 52.515800,13.399593 52.515618,13.398845
    52.515474,13.398208 52.515324,13.397421 52.515241,13.396833 52.515170,13.395714)

echo "Baue für den Test …"
xcodebuild build-for-testing -project "$PROJ" -scheme RadPendlerShots \
  -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|BUILD|TEST BUILD" | tail -3
APP=$(xcodebuild -project "$PROJ" -scheme RadPendler -destination 'generic/platform=iOS Simulator' \
      -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')

capture() {   # UDID, Ordner → ein Testlauf, Bilder nach $OUT/<ordner>
  local id=$1 folder=$2 res=/tmp/rp-shots-$folder.xcresult tmp=/tmp/rp-shots-$folder
  rm -rf "$res" "$tmp"
  xcrun simctl location "$id" clear 2>/dev/null || true
  xcrun simctl location "$id" start --speed=6 --interval=1 $WP &
  local loc=$!
  # xcodebuild sammelt nach dem letzten Test bis zu zehn Minuten Diagnosen — nicht abwarten.
  ( xcodebuild test-without-building -project "$PROJ" -scheme RadPendlerShots \
      -destination "platform=iOS Simulator,id=$id" -resultBundlePath "$res" > "$tmp.log" 2>&1 ) &
  local xb=$!
  until grep -qE "Executed [0-9]+ tests?, with|TEST EXECUTE (SUCCEEDED|FAILED)" "$tmp.log" 2>/dev/null \
        || ! kill -0 $xb 2>/dev/null; do sleep 5; done
  pkill -f 'simctl diagnos' 2>/dev/null || true
  wait $xb 2>/dev/null || true
  kill $loc 2>/dev/null || true
  xcrun xcresulttool export attachments --path "$res" --output-path "$tmp" >/dev/null
  rm -rf "$OUT/$folder"; mkdir -p "$OUT/$folder"
  python3 - "$tmp" "$OUT/$folder" <<'PY'
import json, sys
from pathlib import Path
from PIL import Image
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
for test in json.loads((src / "manifest.json").read_text()):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "").split("_")[0].removesuffix(".png")
        if name:   # „1-hauptseite_0_<uuid>.png“ → 1-hauptseite.png, ohne Alphakanal
            Image.open(src / a["exportedFileName"]).convert("RGB").save(dst / f"{name}.png", optimize=True)
PY
  echo "$folder: $(ls "$OUT/$folder" | wc -l | tr -d ' ') Bilder"
}

all=("RP iPhone 17 Pro|iPhone 17 Pro|iphone-6.3" "RP iPhone 17 Pro Max|iPhone 17 Pro Max|iphone-6.9"
     "RP iPad Pro 13|iPad Pro 13-inch (M5)|ipad-13")
for spec in "${all[@]}"; do
  name=${spec%%|*}; rest=${spec#*|}; type=${rest%%|*}; folder=${rest#*|}
  [ $# -eq 0 ] || (( ${@[(Ie)$folder]} )) || continue
  id=$(device "$name" "$type")
  xcrun simctl terminate "$id" $BUNDLE 2>/dev/null || true
  xcrun simctl install "$id" "$APP"
  xcrun simctl spawn "$id" defaults write $BUNDLE origin -data "$(hex "$ORIGIN")"
  xcrun simctl spawn "$id" defaults write $BUNDLE destination -data "$(hex "$DEST")"
  xcrun simctl spawn "$id" defaults write $BUNDLE alertsOn -bool NO
  xcrun simctl spawn "$id" defaults write $BUNDLE rideOrientationLock -string portrait
  xcrun simctl privacy "$id" grant location-always $BUNDLE
  capture "$id" "$folder"   # wärmt Kacheln und Ampeldaten
  capture "$id" "$folder"
  xcrun simctl shutdown "$id"   # drei gebootete Geräte zusätzlich sind dem Mac zu viel
done
