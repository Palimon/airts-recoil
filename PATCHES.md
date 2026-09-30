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

## For patch authors: exact commands

On Tokyo, any clone owned by `palimon` can push to this fork: the deploy key is the SSH host
alias `github-airts-recoil` in `~/.ssh/config` (write access to this repository only). The
fork's working clone is `~/recoil-spike/airts-recoil`; `~/recoil-spike/RecoilEngine` is the
spike's upstream clone.

```bash
# 1. Remote and base (in whichever clone holds your work)
git remote add fork git@github-airts-recoil:Palimon/airts-recoil.git 2>/dev/null || true
git fetch fork
# 2. Start from airts/main, or move a branch started from ff8e2a1 onto it
git checkout -b patch/<name> fork/airts/main
git rebase --onto fork/airts/main ff8e2a171613321c8dadca995fd74583d25f4c3e patch/<name>
# 3. Commits: messages start with "[<name>] "; the last one adds the flag
#    (LuaPushNamedBool(L, "airts<Name>", true) next to the other airts keys in
#    rts/Lua/LuaConstEngine.cpp, plus its @field doc line), bumps airts/PATCH_LEVEL by one
#    and adds the entry at the end of this file.
# 4. Push: CI (.github/workflows/airts-ci.yml) runs on every push to patch/**
git push fork patch/<name>        # push a new patch branch on its own: when patch/skinning-gl4 was
                                  # created in the same push as airts/main, no run started for it
gh run list -R Palimon/airts-recoil --branch patch/<name>      # from the Windows box
# 5. Local gate on Tokyo: every engine launch goes through the host-wide slot limiter
export AIRTS_DET_WRAP=~/recoil-spike/tools/engine-slot.sh
airts/scripts/determinism.sh <build>/spring-headless /tmp/det-<name>                 # fixture, 1 thread
AIRTS_DET_THREADS=default airts/scripts/determinism.sh <build>/spring-headless /tmp/cog-<name>   ~/recoil-spike/data ~/recoil-spike/w-cog/host.txt                                    # Cogwright match
# 6. Merge after the gate (the orchestrator lands it)
git checkout airts/main && git merge --no-ff patch/<name> && git push fork airts/main
```

Builds: `RELEASING.md` (Zeus WSL: docker-build-v2 for Windows, native for Linux). A native Linux build that
matches CI: `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DAI_TYPES=NONE
-DPLUTOVG_BUILD_EXAMPLES=OFF -DLUNASVG_BUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
-DCMAKE_INSTALL_PREFIX=$PWD/install && cmake --build build && cmake --install build` (needs
`binutils-gold`; the checkout needs the upstream version tags).

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
| `airtsGltfLoader` | boolean | `patch/gltf-loader` |
| `airtsUnitTempo` | boolean | `patch/unit-tempo` (tempo series) |
| `airtsUnitSpeedMult` | boolean | `patch/unit-tempo` (speed-multiplier series) |

`patch/creg-mtdrawsafe` adds no key: it changes nothing Lua can observe.

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

- `build`: Ubuntu 24.04, gold linker, `-DAI_TYPES=NONE -DPLUTOVG_BUILD_EXAMPLES=OFF
  -DLUNASVG_BUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF`, `-O3` without debug info, ccache kept
  between runs. It builds the whole tree (engine-headless is made from the legacy client's
  `Game` library target, so `-DBUILD_spring-legacy=OFF` fails to configure, and building only
  the engine targets leaves `cmake --install` without the mimalloc objects); installs, checks
  that `--sync-version` ends in `airts-<n>` and names HEAD, and uploads the install tree.
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
  hash 56095). The GitHub runner (4 cores) reproduced it in CI run 36664421989: GameOver frames
  2272 and 2108 with default threads, 2108 and 2108 single-threaded. The divergence is in movement, so the likely sources are the multi-threaded
  ground-move and path systems (`rts/Sim/MoveTypes/Systems/GroundMoveSystem.cpp`,
  `rts/Sim/Path/HAPFS/PathManager.cpp`, `PathingState.cpp`, `rts/Sim/Units/UnitHandler.cpp`).
  Not yet bisected, not yet reported upstream. The Cogwright match did not show it (GameOver
  frame 32465 on every run) and the spike's networked runs had zero sync errors, but a
  multiplayer desync is the risk. The CI gate runs single-threaded until this is understood.
  Triage 2026-09-30 (fixture, 6 concurrent runs per engine, default threads, through
  `engine-slot.sh` on Tokyo): upstream's prebuilt Linux releases 2026.06.12, 2026.07.03,
  2026.07.04 and 2026.09.01 are all non-deterministic (4 distinct end states each out of 6), as is
  ff8e2a1 (3 of 6). No upstream release exists after ff8e2a1. So it is not a recent regression:
  it predates 2026.06.12. The frame-300 census hash changed between 2026.07.04 (3770) and
  2026.09.01 (44603), so the movement code itself changed in that window. Arena matches did repeat:
  the Cogwright 0.3 arena match cog versus teph, seed 2003, ran 4 times with default threads
  and ended at GameOver frame 27805 with sync checksum `1a62d337` every time, the same as the
  arena round's original run.
- **QTPFS crashes in background path searches with more than one worker thread.** Rules 0.5
  switched to QTPFS (`pathFinderSystem = 1`); 5 of 36 arena games segfaulted on ff8e2a1 in
  `SharedFinalize`/`IPath::SetSourcePoint`, `SmoothPathIter`, `LoadPartialPath` and
  `IPath::SetPoint`, always on a worker inside `PathManager::ExecuteQueuedSearches`'
  `for_mt_background` task (`rts/Sim/Path/QTPFS/PathManager.cpp:1096`). One crashed start script
  run 4 times: QTPFS with default threads crashed 3 times at 3 different frames; QTPFS with
  `WorkerThreadCount = 1` finished 4 times at the same frame (51345); HAPFS finished 4 times at the
  same frame (14850). Upstream master is still ff8e2a1, so there is no upstream fix to take.
  Games ship HAPFS (`pathFinderSystem = 0`) until this is fixed. Upstream issue draft:
  `airts/upstream/qtpfs-background-search-crash.md` (not filed).
- **No stack trace when core dumps are enabled.** `CrashHandler::Install`
  (`rts/System/Platform/Linux/CrashHandler.cpp:1039-1045`) installs no signal handler when
  `RLIMIT_CORE` is above 0 and logs `Core dumps enabled, not installing signal handler`; a crash
  then exits 139 with no trace (arena game cog-quiet-s2-0 on the docker host 192.168.1.175).
  Setting: launch every engine with a core limit of 0 (`ulimit -c 0` in the launching shell, or
  `docker run --ulimit core=0` for a container), and the handler is installed and prints the
  trace. Tokyo's shells have `ulimit -c 0` already.

- **testCreg fails at the base commit.** Upstream a53282a (2026-09-07, "Particle draw
  optimizations") added `bool mtDrawSafe` to `CProjectile` without a creg entry, so
  `spring-headless --test-creg` reports 37 of 216 classes with a missing byte between
  `drawSorted` and `blockPreciseCol`. Fixed in this fork by `patch/creg-mtdrawsafe` (entry 005),
  after which CI gates on testCreg again.

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

### 001 skinning-gl4 (`patch/skinning-gl4`, 2026-09-30)

- Flag: `Engine.FeatureSupport.airtsSkinningFix`. Patch level 2.
- Symptom: thin slivers from skinned units to the screen centre on real GPUs (first watched
  match on Zeus).
- Cause: `ModelUtils.cpp` `ReparentMeshesTrianglesToBones` moves a vertex's heaviest influence
  into slot 3 when the triangle's bone is missing from the vertex (lines 106-111);
  `ModelVertProgGL4.glsl` then multiplies by slot 0 and reads only slots 1 and 2 (lines 301-307),
  so a single-influence vertex becomes (0,0,0,0) and lands at the screen centre.
  `ShadowGenVertProgGL4.glsl` divides by a weight sum that can be zero (NaN shadows).
- Fix: shader-only. Both vertex programs read all four influences, sum the weights used, and
  divide position and normal by the sum when it is above zero.
- Files: `cont/base/springcontent/shaders/GLSL/ModelVertProgGL4.glsl`,
  `cont/base/springcontent/shaders/GLSL/ShadowGenVertProgGL4.glsl` (built into
  `base/springcontent.sdz`); the flag in `rts/Lua/LuaConstEngine.cpp`; `airts/PATCH_LEVEL`.
- Proof: under Xvfb with a diagnostic line that draws (0,0,0,0) at the screen centre (as a
  desktop GPU does), lines appear from tinker_s_crank and grandfather_tread before the patch and
  not after; a gadget bending three leg joints shows smooth deformation after the patch
  (evidence in the showcase handoff folder, `engine-patches/001-gl4-skinning-influences/evidence/`).
  The orchestrator reports it verified on a real GPU. spring-headless runs the full game
  unchanged (no C++ simulation code changed); the gate result is below.
- Shipping without an engine rebuild: copy the two `.glsl` files into the game archive under
  `shaders/GLSL/` (the engine reads game-archive shaders before base content). The fork build
  carries them in `springcontent.sdz`. Whether a patched base archive changes the game checksum
  in networked games is untested; our Windows and Linux builds of one commit carry the same
  files.
- Upstream: worth a pull request to RecoilEngine (skinned glTF is untested upstream); offer the
  first commit of this branch alone. Not yet offered.
- Also noted for later: `GLTFParser` ignores `inverseBindMatrices`;
  `ReparentCompleteMeshesToBones` indexes a cleared vector (`ModelUtils.cpp:177-180`); joint
  lookups have no bounds check (`GLTFParser.cpp:150-153`); hiding a joint piece by zero scale
  zeroes its weights and reintroduces slivers; model load is quadratic in vertex count
  (`ModelUtils.cpp:128`).

#### Gate result for skinning-gl4 (2026-09-30)

Build: `airts/main` at `dc05e27162` (the merge of this patch), `docker-build-v2/build.sh linux` on
Tokyo, stored in `~/recoil-spike/builds/airts-main-dc05e27162/linux/`; sync version
`2026.09.01-13-gdc05e27 airts-2` (stock: `2026.09.01-5-gff8e2a1 HEAD`).

1. CI: run 36666837840 on `2c26a34` (same engine source as `dc05e27`, later commits change only
   CI, docs and the determinism script) passed: build, 27 of 27 gating unit tests (testCreg
   fails as upstream, see above), determinism 2108/2108 single-threaded, Lua read
   `airtsFork=true airtsPatchLevel=2 airtsSkinningFix=true`.
2. Fixture on Tokyo, single-threaded, two runs: GameOver frame 2108 both, 8 identical census lines,
   last `AIRTS_CENSUS frame=2100 units=6/1 hp=1585 hash=56095`, the same as the stock engine.
3. Cogwright single-process match (`~/recoil-spike/w-cog/host.txt`, data `~/recoil-spike/data`,
   default threads, as the spike ran it), two runs through `engine-slot.sh`: exit 0, GameOver
   `winners=0 frame=32465` both (stock: 32465), quit at 32495, 65 markers, 68 burn-unit lines
   (34 burning, 17 ended, 17 died burning), 20 AI waves, 7 unitdefs, zero error and zero sync
   lines (fact sheet section 12 patterns). Every count equals the stock run in the spike's
   `evidence/cogwright/cog-checks.txt`. Wall 78.4 s and 77.4 s.
4. Cross-platform run: not needed (no simulation code changed).
5. Watched check on Zeus: pending with this build; the shader fix itself was checked on a real
   GPU before it entered the fork.

### 002 gltf-loader (`patch/gltf-loader`, 2026-09-30)

- Flag: `Engine.FeatureSupport.airtsGltfLoader`. Patch level 3.
- Symptoms and causes, in `rts/Rendering/Models` at the base commit:
  1. `GLTFParser` never reads `skin.inverseBindMatrices`, so the rest pose is always the bind
     pose and converters had to rewrite the matrices to match it.
  2. `skinPtr->joints[val.x()]` has no bounds check (`GLTFParser.cpp:150-153`, `160-163`), and a
     joint that is not a piece dereferences `end()` (`ReplaceNodeIndexWithPieceIndex`).
  3. `ReparentCompleteMeshesToBones` clears `boneWeights` and then indexes it
     (`ModelUtils.cpp:177-180`).
  4. Vertex de-duplication in `ReparentMeshesTrianglesToBones` is a linear search per vertex
     (`ModelUtils.cpp:128`), quadratic per piece, and its key ignores UVs.
  5. The slot swap (`ModelUtils.cpp:106-111`, `219-224`) can move a vertex's heaviest influence
     into slot 3, which the stock GL4 shaders do not read, and overwrites the fourth influence;
     this is the cause behind patch 001.
- Fix:
  1. A skin joint whose bind pose (mesh node global transform times the inverse of its inverse
     bind matrix, in engine axes) differs from its rest pose gets
     `S3DModelPiece::bindPoseOverride`, which `SetPieceTransform` uses for `bposeTransform`.
     Joints that agree keep the rest pose bit for bit; non-uniform or zero scale is rejected
     with a warning.
  2. An out-of-range joint index drops that influence with a warning; a joint that is not a
     piece binds to the root piece with a warning.
  3. `ReparentCompleteMeshesToBones` sums weights into a table sized to the piece count.
  4. De-duplication uses a hash map per piece keyed on the exact position, normal, both UV sets
     and the influences; the first occurrence wins, so vertex order is unchanged.
  5. Slot order: slot 0 holds the triangle's bone (weight 0 if the vertex lacks it) and the
     vertex's other influences keep their descending order in slots 1-3; only the lightest is
     dropped, and the rest are renormalised to 255.
- Deviation from the request "heaviest influence in slot 0": slot 0 must be the bone of the
  piece the triangle is stored in, because the vertex positions are stored in that bone's bind
  space and the vertex programs treat slot 0 as the vertex's own space. The heaviest other
  influences therefore go to slots 1-2, which even the stock three-slot shader reads, so a
  single-influence vertex can no longer become (0,0,0,0); patch 001 stays as a safety net.
- Sync: only model loading changes (`3DModelPiece.hpp`, `3DModelPiece.cpp`, `GLTFParser.cpp`,
  `ModelUtils.cpp`). Model data reaches the simulation through piece vertices 0 and 1 (emit
  position and direction) and piece bounds. These change only for third-party files whose
  inverse bind matrices differ from the rest pose; all 22 skinned models in our four faction
  archives match their rest pose to 7e-7, so no override triggers, de-duplication keeps the
  vertex order, and bone slots and weights are GPU-only.
- Proof (Tokyo, Xvfb llvmpipe GL4, evidence in the showcase handoff folder,
  `engine-patches/002-gltf-loader/evidence/`): the posed tinker_s_crank renders the same as with
  the stock engine (0 pixels differ by more than 24/255); a test copy whose bone_6 has a 0.9 rad
  rest rotation but its original inverse bind matrix shows the limb bent at rest, as the glTF
  spec requires, where stock shows it straight. "Finalizing Models" (spring-headless, faction
  archives v0.2, from that log line to the next, two runs each):

  | Archive | Stock | Patched |
  |---|---|---|
  | cog | 10.5 s, 10.3 s | 0.20 s, 0.20 s |
  | kaet | 13.7 s, 14.3 s | 0.30 s, 0.20 s |
  | quiet | 14.1 s, 13.3 s | 0.31 s, 0.20 s |
  | teph | 23.5 s, 19.8 s | 0.31 s, 0.20 s |

- Files: the four model files above; the flag in `rts/Lua/LuaConstEngine.cpp`;
  `airts/PATCH_LEVEL`.
- Upstream: worth a pull request to RecoilEngine in three parts (inverse bind matrices; the
  undefined-behaviour fixes 2 and 3; de-duplication and slot order). Not yet offered. Left as
  upstream has it: the skinned mesh node's own transform is still applied to its vertices (the
  spec says to ignore it; the bind pose composes it, so the result matches the spec), and the
  bone-space loop in both reparent functions also transforms pieces that were already local in
  files that mix skinned and unskinned meshes.

#### Gate result for gltf-loader on the merge (2026-09-30)

Merge `767814c5fe` (`--no-ff`, patch level 3). Build: Zeus WSL, `airts/scripts/build-release-zeus.sh`, Linux copy on
Tokyo `~/recoil-spike/builds/airts-main-767814c5fe/linux`; sync version `2026.09.01-21-g767814c airts-3` on Linux and
Windows. Branch CI: run 36676111515 green (build, 27 of 27 gating unit tests, determinism 2108/2108).

1. Fixture on Tokyo, single-threaded, through `engine-slot.sh`: GameOver 2108 on both runs, identical census, last
   `AIRTS_CENSUS frame=2100 units=6/1 hp=1585 hash=56095`, as stock.
2. Cogwright single-process match, default threads, two runs: exit 0, `AIRTS_GAMEOVER winners=0 frame=32465` both
   (stock 32465), 65 markers, 68 burn-unit lines (34, 17, 17), 20 AI waves, zero error and sync lines; every count
   equals stock. Peak RSS 4.10 GB.
3. The patch author's own gate on the branch build `2026.09.01-19-g4953050 airts-3` gave the same frames.
4. Watched check on Zeus: the tester's GPU gate with this build (pending).

### 003 unit-tempo (`patch/unit-tempo`, merged 2026-09-30)

- Flag: `Engine.FeatureSupport.airtsUnitTempo`. Patch level 4.
- API: `Spring.SetUnitTempo(unitID, tempo)` (synced), `Spring.GetUnitTempo(unitID)`. Tempo is the rate
  of the unit's local time: 1 normal, 0 frozen, no upper bound; a negative or non-finite value is
  a Lua error.
- What it scales, and how:
  1. Movement: the ground movetype's final speed target (after turn, terrain, braking and wanted
     speed limits), its acceleration, deceleration and turn rate; the hover-air speed target;
     MoveCtrl motion (velocity, gravity, wind, relative velocity, drag and rotation). `maxSpeed`
     itself is never written, so nothing divides by a scaled 0.
  2. Weapons: a reload or salvo delay in progress is consumed at the tempo (its ready frame moves
     by the frames the unit's time did not advance, through `CUnit::UpdateTempoTimers`); a loaded
     weapon stays loaded.
  3. Shots: speed times the tempo and lifetime divided by it at creation, so range is kept.
     Missiles and starburst weapons still accelerate towards their def speed; a ballistic shot at
     a lower speed falls shorter than its aim.
  4. Build and repair power of builders and factories. Reclaim, resurrect, capture and
     terraform are not scaled.
  5. Script animations (Turn, Move, Spin, scale) of COB and Lua unit scripts. Script sleeps and
     waits are not scaled (COB threads, and Lua unit-script coroutines run by the game's gadget).
  6. Autoheal, idle autoheal, stun (paralysis) decay and the self-destruct countdown.
  7. The engine has no cloak timer (cloak state is checked each slow update), so there is none
     to scale.
- Tempo 0: the ground movetype and its path following do not run and the unit's velocity is 0;
  air, MoveCtrl and static movetypes do not run; the unit does not aim or fire
  (`CUnit::CanUpdateWeapons`); its animations stop; build power, heal and stun decay are 0.
  Strafe-air (plane) speed is not scaled at tempos between 0 and 1.
- Files: `rts/Sim/Units/Unit.h`, `Unit.cpp` (new `CR_MEMBER` state `tempo`, `tempoFrameLag`,
  `selfDTempoAccum`), `rts/Sim/Units/Scripts/UnitScript.h`, `UnitScript.cpp`,
  `rts/Sim/MoveTypes/GroundMoveType.cpp`, `HoverAirMoveType.cpp`, `ScriptMoveType.cpp`,
  `Systems/GroundMoveSystem.cpp`, `Systems/GeneralMoveSystem.cpp`, `rts/Sim/Weapons/Weapon.cpp`,
  `rts/Sim/Projectiles/ProjectileParams.h`, `WeaponProjectiles/WeaponProjectileFactory.cpp`,
  `rts/Sim/Units/UnitTypes/Builder.cpp`, `Factory.cpp`, `rts/Lua/LuaSyncedCtrl.*`,
  `LuaSyncedRead.*`, `LuaConstEngine.cpp`; tests in `airts/fixtures/` and
  `airts/scripts/feature-tests.sh`.
- Why Lua cannot do it: Lua cannot reach reload in progress, animation time, stun decay or the
  other engine timers, and cannot write `maxSpeed` while a unit is under MoveCtrl.
- Known limits: strafe-air (plane) speed is not scaled between tempo 0 and 1; script sleeps and
  waits are not scaled (COB threads and Lua unit-script coroutines); missiles and starburst
  weapons accelerate back towards their def speed after launch; reclaim, resurrect, capture and
  terraform power are not scaled.
- Upstream: offer as a pull request (plan decision 11). Not yet offered.

### 004 unit-speedmult (`patch/unit-tempo`, speed-multiplier series, merged 2026-09-30)

- Flag: `Engine.FeatureSupport.airtsUnitSpeedMult`. Patch level 5.
- API: `Spring.SetUnitSpeedMult(unitID, mult)` (synced), `Spring.GetUnitSpeedMult(unitID)`. It
  multiplies movement speed only (not acceleration, turn rate, weapons or timers) and composes
  with tempo (`CUnit::GetMoveSpeedMult`). 1 normal, no upper bound; negative or non-finite is a
  Lua error.
- It applies to the ground speed target, the hover-air speed target and MoveCtrl motion, also
  while the unit is under MoveCtrl (which `MoveCtrl.Set*MoveTypeData` cannot do). 0 holds the
  unit with no 0.001 floor: a MoveCtrl unit does not move at all; a ground unit decelerates to 0
  and can still turn in place.
- Files: `rts/Sim/Units/Unit.h`, `Unit.cpp` (`CR_MEMBER` `speedMult`), `rts/Lua/LuaSyncedCtrl.*`,
  `LuaSyncedRead.*`, `LuaConstEngine.cpp`.
- Upstream: offer together with 003. Not yet offered.

#### Gate result for 003 and 004 (2026-09-30)

Build: Zeus WSL native `engine-headless` of this branch (`2026.09.01-25-g4b44785 airts-5`, the same
source as the branch head apart from commit metadata), run on Tokyo from
`~/recoil-spike/builds/tempo-dev/linux` through `engine-slot.sh`.

1. Feature tests (`airts/scripts/feature-tests.sh`, single-threaded), 6 of 6 PASS, identical on
   two runs: tempo 0 turret spin frozen (0 rad against 2.094 rad at tempo 1 in 120 frames); ground
   move at tempo 0.5 covered 77.19 elmos against 161.59 (ratio 0.478), tempo 0 covered 0;
   MoveCtrl at tempo 0.5 60.00 against 120.00; a reload in progress at tempo 0.5 ended 60 frames
   later after 120 frames; MoveCtrl at speed multiplier 0 moved 0 and at 3 moved 360.00 against
   120.00; a ground order at multiplier 0 moved 0 and at 3 moved 445.60 against 161.59. The base
   build (`767814c`) prints SKIP for all six.
2. Fixture determinism, single-threaded: GameOver 2108 on both runs, census identical and equal to
   stock (last hash 56095): at tempo 1 and multiplier 1 the patched code computes the same values.
3. Cogwright match, default threads: GameOver 32465 on both runs, 65 markers, 68/34/17/17 burn
   lines, 20 AI waves, zero error and sync lines; every count equals stock.
4. Rides on the tester's next gate: the cross-platform run with the Windows client sending
   orders (V4 topology) and a watched check on Zeus of a tempo field and a frozen unit.

### 005 creg-mtdrawsafe (`patch/creg-mtdrawsafe`, merged 2026-09-30)

- Flag: none (no Lua-visible behaviour). Patch level 6.
- Symptom: testCreg (`spring-headless --test-creg`) fails at the base commit: 37 of 216
  projectile classes report a missing byte between `drawSorted` and `blockPreciseCol`.
- Cause: upstream a53282a (2026-09-07, "Particle draw optimizations", #3232) added
  `bool mtDrawSafe` to `CProjectile` (`rts/Sim/Projectiles/Projectile.h:122`) without a creg
  entry. Save games do not store it; `ShieldSegmentProjectile` and `TracerProjectile` set it per
  instance.
- Fix: `CR_MEMBER(mtDrawSafe)` in `rts/Sim/Projectiles/Projectile.cpp`, next to `drawSorted`.
  CI's unit-test job gates on testCreg again.
- Files: `rts/Sim/Projectiles/Projectile.cpp`; `airts/PATCH_LEVEL`;
  `.github/workflows/airts-ci.yml`; `airts/upstream/creg-mtdrawsafe.md`.
- Proof: the CI run of this branch (testCreg passes, determinism unchanged).
- Upstream: pull request text ready in `airts/upstream/creg-mtdrawsafe.md` (first commit of this
  branch only). Not opened; Jonathan decides.
