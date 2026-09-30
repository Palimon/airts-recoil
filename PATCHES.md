# AIRTS engine patches

`Palimon/airts-recoil` is a public fork of [beyond-all-reason/RecoilEngine](https://github.com/beyond-all-reason/RecoilEngine)
for the AIRTS game. This file lists every change we make to the engine or its base content, with
the reason, the proof, the Lua feature flag and the upstream status. The engine is GPL-2.0-or-later
(`LICENSE`); this public repository is how we meet the source obligation for every build we ship.

## Branches

| Branch or tag | What it is |
|---|---|
| `airts/base`, tag `airts-base-2026-09-29` | Upstream `ff8e2a171613321c8dadca995fd74583d25f4c3e`, never moved. Rebasing onto a new upstream release is a deliberate act that re-runs the whole gate. |
| `airts/main` | `airts/base` plus the fork plumbing plus every merged patch branch. All builds come from here. |
| `patch/<name>` | One branch per patch, started from `airts/main`, commit messages prefixed `[<name>]`, merged into `airts/main` with `--no-ff` after the gate below. |

## Version identity

The version string is `<git describe> airts-<n>`, for example `2026.09.01-8-gb41172b airts-1`,
where `<n>` is the patch level in `airts/PATCH_LEVEL` (`rts/build/cmake/ConfigureVersion.cmake`).
It replaces the branch name that upstream puts there, so:

- every build of one commit has the same sync version, from any branch, a detached HEAD or a
  docker build, on Linux and Windows;
- no stock Recoil build can have the same string, so the server's client-version check
  (`rts/Net/GameServer.cpp`, "client version ... mismatch") keeps stock clients out of our games,
  and a stock server rejects our clients;
- `--sync-version`, `Engine.version`, the infolog banner (`Spring Engine Version:`), demo headers
  and demo file names all show it.

Stock at the base commit reports `2026.09.01-5-gff8e2a1 HEAD`. A build needs the upstream version
tags and history (`git describe --match "[0-9]*"`); CMake stops with an error on a checkout that
has none. The patch level goes up by one with every patch merged into `airts/main`; the patch
branch's own flag commit makes the bump.

## Lua feature flags

Every patch adds one key to `Engine.FeatureSupport` (`rts/Lua/LuaConstEngine.cpp`). All keys are
nil on stock Recoil, so game code writes `if Engine.FeatureSupport.airtsX then ... else <gadget
fallback> end`.

| Key | Type | Added by |
|---|---|---|
| `airtsFork` | boolean | fork plumbing |
| `airtsPatchLevel` | integer, `airts/PATCH_LEVEL` | fork plumbing |
| `airtsSkinningFix` | boolean | `patch/skinning-gl4` |

## The gate every patch passes before it merges

1. CI on the patch branch (`.github/workflows/airts-ci.yml`): the Linux build of
   engine-headless and engine-dedicated, the engine's unit tests (`ctest`), and the determinism
   job.
2. Headless determinism on Tokyo: the same start script run twice ends on the same `GameOver`
   frame with the same census and no Lua or sync lines (`airts/scripts/determinism.sh`, which
   also takes another data dir and start script, for example the Cogwright match).
3. For patches that touch the simulation: the cross-platform run (a Linux dedicated server, a
   Linux headless client and the Windows client for 18000 frames, the Windows side sending
   orders, zero sync lines on all three logs).
4. A watched check on Zeus in the Windows client.

Upstream's `synctest.yml` downloads BAR content, which we do not want in CI; the determinism job
replaces it with our own fixture.

## CI

`.github/workflows/airts-ci.yml` runs on pushes to `airts/**` and `patch/**`, pull requests to
`airts/main`, and by hand:

- `build`: Ubuntu 24.04, gold linker, `-DAI_TYPES=NONE -DBUILD_spring-legacy=OFF
  -DPLUTOVG_BUILD_EXAMPLES=OFF -DLUNASVG_BUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF`, `-O3` without
  debug info, ccache kept between runs; installs, checks that `--sync-version` ends in
  `airts-<n>` and names HEAD, and uploads the install tree.
- `unit-tests`: the same toolchain with `-DBUILD_TESTING=ON`; builds the `tests` target and
  engine-headless (for `testCreg`) and runs `ctest`.
- `determinism`: runs `airts/fixtures/determinism` twice single-threaded (gating), checks that
  Lua reads `Engine.FeatureSupport.airtsFork`, then runs it twice with the engine's default
  thread count (reported, not gating; see below).

Upstream's workflows are still in `.github/workflows/`; they trigger only on `master`, on pull
requests that touch their paths, or by hand, so they stay quiet on our branches.

The fixture (`airts/fixtures/determinism/`, 1.6 MB) is the spike's skeleton game with
`airts_testend` replaced by `airts_census.lua`: two squads of 13 probes fight with synced random
fight orders, `AIRTS_CENSUS` lines log unit counts, total health and a position hash every 300
frames, and `game_end` declares the winner. It uses no BAR content.

## Known engine issues

- **Multi-threaded simulation is not deterministic at the base commit.** On Tokyo (24 threads)
  the stock ff8e2a1 spring-headless with the default `WorkerThreadCount` (all cores) ran the
  fixture 12 times concurrently (6 at speed 20, 6 at speed 100): 6 different end states, GameOver
  frames 2108, 2112, 2140, 2213, 2249 and 2272, and only 1 of the 12 matched the single-threaded
  result. Positions of one team already differ at frame 300, before any combat. Six more runs
  from a warm path cache gave 4 end states (2108, 2206, 2272, 2504). With
  `WorkerThreadCount = 1` six concurrent runs were identical (GameOver frame 2108, final census
  hash 56095). The divergence is in movement, so the likely sources are the multi-threaded
  ground-move and path systems (`rts/Sim/MoveTypes/Systems/GroundMoveSystem.cpp`,
  `rts/Sim/Path/HAPFS/PathManager.cpp`, `PathingState.cpp`, `rts/Sim/Units/UnitHandler.cpp`).
  Not yet bisected, not yet reported upstream. The Cogwright match did not show it (GameOver
  frame 32465 on every run) and the spike's networked runs had zero sync errors, but a
  multiplayer desync is the risk. The CI gate runs single-threaded until this is understood.

## Patches

### 000 fork-plumbing (in `airts/main`, 2026-09-30)

- What: version identity, `Engine.FeatureSupport.airtsFork` and `airtsPatchLevel`, the
  determinism fixture and script, CI, this file and `RELEASING.md`.
- Files: `airts/PATCH_LEVEL`, `rts/build/cmake/ConfigureVersion.cmake`,
  `rts/System/VersionGenerated.h.template`, `rts/Game/GameVersion.h`, `rts/Game/GameVersion.cpp`,
  `rts/Lua/LuaConstEngine.cpp`, `airts/fixtures/`, `airts/scripts/determinism.sh`,
  `.github/workflows/airts-ci.yml`, `PATCHES.md`, `RELEASING.md`.
- Why: lets Lua detect patched features, keeps stock clients out of our games, ships builds, and
  meets the GPL source obligation from the first tag.
- Upstream: not offered (fork-specific).
