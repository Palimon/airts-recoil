#!/bin/bash
# Release build of the checked-out commit on Zeus WSL Ubuntu-24.04: Windows through docker-build-v2,
# Linux natively (ccache), both timed, install trees stored in ~/airts-builds/airts-main-<hash>/.
# usage: airts/scripts/build-release-zeus.sh [cold]   ("cold" empties both compiler caches first)
set -u
cd "$(dirname "$0")/../.." || exit 1
H=$(git rev-parse --short=10 HEAD)
OUT=~/airts-builds/airts-main-$H
LOGS=~/airts-builds/logs; mkdir -p "$LOGS"
export CCACHE_DIR=$HOME/.cache/ccache-airts-native CCACHE_MAXSIZE=20G
log(){ echo "[$(date -u +%FT%TZ)] $*"; }
if [ "${1:-}" = cold ]; then rm -rf .cache/ccache-amd64-windows "$CCACHE_DIR"; fi

T=$(date +%s); log "windows start $H"; rm -rf build-amd64-windows
docker-build-v2/build.sh windows > "$LOGS/$H-windows.log" 2>&1; RC=$?
log "windows done rc=$RC wall=$(( $(date +%s)-T ))s"; [ $RC = 0 ] || exit $RC

T=$(date +%s); log "linux start $H"; rm -rf build-native
cmake -S . -B build-native -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  "-DCMAKE_C_FLAGS_RELWITHDEBINFO=-O3 -g -DNDEBUG" "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O3 -g -DNDEBUG" \
  -DAI_TYPES=NATIVE '-DAI_EXCLUDE_REGEX=^CppTestAI$' -DBUILD_TESTING=OFF \
  -DPLUTOVG_BUILD_EXAMPLES=OFF -DLUNASVG_BUILD_EXAMPLES=OFF \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_INSTALL_PREFIX="$PWD/build-native/install" > "$LOGS/$H-linux.log" 2>&1 &&
cmake --build build-native >> "$LOGS/$H-linux.log" 2>&1 &&
cmake --install build-native >> "$LOGS/$H-linux.log" 2>&1; RC=$?
log "linux done rc=$RC wall=$(( $(date +%s)-T ))s"; [ $RC = 0 ] || exit $RC

rm -rf "$OUT"; mkdir -p "$OUT"
cp -a build-native/install "$OUT/linux" && cp -a build-amd64-windows/install "$OUT/windows"
V=$("$OUT/linux/spring-headless" --sync-version | tail -1)
W=$(strings -n 12 "$OUT/windows/spring.exe" | grep -m1 -E ' airts-[0-9]+$')
printf 'linux:   %s\nwindows: %s\n' "$V" "$W" | tee "$OUT/sync-version.txt"
[ "$V" = "$W" ] || { log "sync versions differ"; exit 1; }
log "stored $OUT"
