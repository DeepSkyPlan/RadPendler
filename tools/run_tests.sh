#!/bin/bash
# xcodebuild test mit Wächter:  tools/run_tests.sh <Argumente für xcodebuild>
#
# Seit dem 11.10.2026 mehrfach beobachtet (Xcode mit iOS-27-Simulator, etwa
# jeder zweite bis dritte Lauf): die Tests laufen durch, „Test Suite 'All
# tests' passed" steht im Protokoll, die App im Simulator ist beendet — und
# xcodebuild kehrt nicht zurück. `./dev check` und `./dev testflight` blieben
# so stehen, bis jemand von Hand abbrach. Hier wartet nach dem Ende der Tests
# niemand länger als eine Minute: dann wird xcodebuild beendet, und es gilt,
# was die Tests selbst gemeldet haben. Die Ausgabe läuft wie gewohnt mit.
set -uo pipefail
LOG=$(mktemp)
xcodebuild "$@" test >"$LOG" 2>&1 &
PID=$!
tail -n +1 -f "$LOG" &
TAIL=$!
finished=0 hung=0
while kill -0 "$PID" 2>/dev/null; do
  sleep 2
  if [ "$finished" -eq 0 ] && grep -qE "Test Suite 'All tests' (passed|failed)" "$LOG"; then finished=$(date +%s); fi
  if [ "$finished" -ne 0 ] && [ $(( $(date +%s) - finished )) -gt "${TEST_GRACE:-60}" ]; then
    hung=1; kill "$PID" 2>/dev/null; break
  fi
done
wait "$PID" 2>/dev/null; code=$?
sleep 1; kill "$TAIL" 2>/dev/null; wait "$TAIL" 2>/dev/null
if [ "$hung" -eq 1 ]; then
  if grep -q "Test Suite 'All tests' passed" "$LOG"; then code=0; echo "** TEST SUCCEEDED ** (xcodebuild kehrte nicht zurück und wurde beendet)"
  else code=1; echo "** TEST FAILED ** (xcodebuild kehrte nicht zurück und wurde beendet)"; fi
fi
rm -f "$LOG"
exit "$code"
