#!/bin/bash
# AIRTS determinism check: run one start script twice with the same spring-headless and require
# the same GameOver frame, the same AIRTS_CENSUS lines, exit code 0 and no error or sync lines.
# usage: airts/scripts/determinism.sh <spring-headless> <work dir> [<data dir> <start script>]
# Defaults: the committed fixture in airts/fixtures/determinism.
# AIRTS_DET_THREADS: WorkerThreadCount for both runs; "1" (the default) or "default" (engine default,
#   all cores). Stock Recoil at ff8e2a1 is NOT deterministic across runs with more than one worker
#   thread (PATCHES.md, "Known engine issues"), so the gating check is single-threaded.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
BIN=$(readlink -f "$1")
WORK=$(readlink -f -m "$2")
DATA=$(readlink -f "${3:-$HERE/fixtures/determinism/data}")
SCRIPT=$(readlink -f "${4:-$HERE/fixtures/determinism/det.txt}")
TIMEOUT_S=${AIRTS_DET_TIMEOUT_S:-1800}
THREADS=${AIRTS_DET_THREADS:-1}
ERR='Error: \[LuaRules|\[unit_script.lua\] Error|LUA_ERR|\[FATAL ERROR\]|Failed to load|could not load|Couldn.t find|Missing required tag|Error in modinfo|Dependent archive|Neither AimFromWeapon|piece not found|invalid leader|missing AI\.|invalid AI\.|setup-script error'
SYNC='Sync error for|did not send sync checksum|Desync detected|DESYNC WARNING|lost connection to server'
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }

echo "binary:  $BIN"
echo "version: $("$BIN" --sync-version 2>/dev/null | tail -1)"
echo "data:    $DATA"
echo "script:  $SCRIPT"
echo "threads: $THREADS"
mkdir -p "$WORK"
for r in a b; do
  W="$WORK/run-$r"
  rm -rf "$W"; mkdir -p "$W"
  if [ "$THREADS" != default ]; then echo "WorkerThreadCount = $THREADS" > "$W/springsettings.cfg"; fi
  T0=$(date +%s.%N)
  # /usr/bin/time records the engine's peak RSS; AIRTS_DET_WRAP prefixes each launch (on Tokyo:
  # ~/recoil-spike/tools/engine-slot.sh, the host-wide engine slot limiter)
  TIMECMD=(); [ -x /usr/bin/time ] && TIMECMD=(/usr/bin/time -f "maxrss_kb=%M" -o "$W/time.txt")
  SPRING_DATADIR="$DATA" ${AIRTS_DET_WRAP:-} "${TIMECMD[@]}" timeout "$TIMEOUT_S" "$BIN" --isolation --write-dir "$W" "$SCRIPT" > "$W/stdout.log" 2>&1
  RC=$?
  T1=$(date +%s.%N)
  LOG="$W/stdout.log"
  grep -o 'AIRTS_CENSUS .*' "$LOG" > "$W/census.txt"
  GO=$(grep -o 'AIRTS_GAMEOVER .*' "$LOG" | head -1)
  NERR=$(grep -cE "$ERR" "$LOG"); NSYNC=$(grep -cE "$SYNC" "$LOG")
  printf 'run-%s rc=%s wall=%.1fs gameover="%s" census_lines=%s errors=%s sync=%s timeout_lines=%s %s\n' \
    "$r" "$RC" "$(echo "$T1 - $T0" | bc)" "$GO" "$(wc -l < "$W/census.txt")" "$NERR" "$NSYNC" "$(grep -c AIRTS_TIMEOUT "$LOG")" \
    "$(grep -o 'maxrss_kb=[0-9]*' "$W/time.txt" 2>/dev/null)"
  [ "$RC" = 0 ] || fail "run-$r exit code $RC"
  [ -n "$GO" ] || fail "run-$r has no AIRTS_GAMEOVER line"
  [ "$NERR" = 0 ] || { fail "run-$r has $NERR error lines"; grep -E "$ERR" "$LOG" | head -5; }
  [ "$NSYNC" = 0 ] || { fail "run-$r has $NSYNC sync lines"; grep -E "$SYNC" "$LOG" | head -5; }
  echo "$GO" > "$W/gameover.txt"
done
cmp -s "$WORK/run-a/gameover.txt" "$WORK/run-b/gameover.txt" || fail "GameOver lines differ"
if [ -s "$WORK/run-a/census.txt" ] || [ -s "$WORK/run-b/census.txt" ]; then
  diff "$WORK/run-a/census.txt" "$WORK/run-b/census.txt" > "$WORK/census.diff" || { fail "census lines differ"; head -5 "$WORK/census.diff"; }
fi
tail -1 "$WORK/run-a/census.txt" 2>/dev/null | sed 's/^/last census: /'
[ "$FAIL" = 0 ] && echo "DETERMINISM PASS" || echo "DETERMINISM FAIL"
exit $FAIL
