#!/bin/bash
# AIRTS feature tests: runs the fixture game with airts_test=features once and checks the
# AIRTS_TEST lines printed by airts_feature_tests.lua (one per Lua-visible engine patch).
# usage: airts/scripts/feature-tests.sh <spring-headless> <work dir>
# AIRTS_TEST_REQUIRE_ALL=1 also fails on SKIP (a flag the build should have is absent).
# AIRTS_DET_WRAP prefixes the launch (Tokyo: ~/recoil-spike/tools/engine-slot.sh).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
BIN=$(readlink -f "$1")
W=$(readlink -f -m "$2")
rm -rf "$W"; mkdir -p "$W"
echo "WorkerThreadCount = 1" > "$W/springsettings.cfg"
echo "version: $("$BIN" --sync-version 2>/dev/null | tail -1)"
SPRING_DATADIR="$HERE/fixtures/determinism/data" ${AIRTS_DET_WRAP:-} timeout 600 "$BIN" --isolation --write-dir "$W" "$HERE/fixtures/feature-tests.txt" > "$W/stdout.log" 2>&1
RC=$?
grep -o 'AIRTS_TEST.*' "$W/stdout.log"
DONE=$(grep -o 'AIRTS_TEST_DONE.*' "$W/stdout.log" | head -1)
ERRS=$(grep -cE 'Error: \[LuaRules|LUA_ERR|\[FATAL ERROR\]|Failed to load' "$W/stdout.log")
FAIL=0
[ "$RC" = 0 ] || { echo "FAIL: exit code $RC"; FAIL=1; }
[ -n "$DONE" ] || { echo "FAIL: no AIRTS_TEST_DONE line"; FAIL=1; }
[ "$ERRS" = 0 ] || { echo "FAIL: $ERRS Lua or fatal error lines"; grep -E 'Error: \[LuaRules|LUA_ERR|\[FATAL ERROR\]|Failed to load' "$W/stdout.log" | head -5; FAIL=1; }
echo "$DONE" | grep -q ' fail=0 ' || { echo "FAIL: a test failed"; FAIL=1; }
if [ "${AIRTS_TEST_REQUIRE_ALL:-0}" = 1 ]; then echo "$DONE" | grep -q ' skip=0' || { echo "FAIL: a test was skipped"; FAIL=1; }; fi
[ "$FAIL" = 0 ] && echo "FEATURE TESTS PASS" || echo "FEATURE TESTS FAIL"
exit $FAIL
