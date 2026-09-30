# Releasing AIRTS engine builds

Every release comes from a commit on `airts/main` that passed the gate in `PATCHES.md`. The
Windows and Linux builds of one commit share one sync version (`<git describe> airts-<n>`), so
they play together; builds of different commits do not.

## Where builds run

Both platforms build on Tokyo (Ubuntu 24.04, 24 threads) with upstream's container build,
`docker-build-v2/build.sh`, which pins the build images by digest
(`docker-build-v2/images_versions.sh`). Zeus is not used for cross-compiles.

Tokyo's working clone is `~/recoil-spike/airts-recoil` (origin is this fork through the deploy
key `github-airts-recoil` in `~/.ssh/config`; `upstream` is RecoilEngine). Submodules must be
initialised recursively.

```bash
cd ~/recoil-spike/airts-recoil
git fetch origin && git checkout --detach origin/airts/main
git submodule update --init --recursive
docker-build-v2/build.sh windows     # -> build-amd64-windows/install
docker-build-v2/build.sh linux       # -> build-amd64-linux/install
```

The container runs `cmake` with `-DCMAKE_BUILD_TYPE=RELWITHDEBINFO` and `-O3 -g -DNDEBUG`, then
`cmake --install`; the install tree is the release payload. `ccache` lives in
`.cache/ccache-amd64-<os>/`, so a rebuild after a small patch takes minutes. The source tree is
mounted read-only into the container: do not edit or check out files while a build runs.

Measured on Tokyo on 2026-09-30 for `dc05e27162`, both cold (empty ccache), `--jobs 12`, run one
after the other while other agents' engines and builds kept the load average between 60 and 260
and available memory at times near zero, so treat these as upper bounds:

| Build | Wall time |
|---|---|
| Windows (`build.sh --jobs 12 windows`) | 3189 s (53 min 9 s) |
| Linux (`build.sh --jobs 12 linux`) | 3533 s until the host's process watchdog killed the `spring-headless` link (05:05Z to 05:09Z it matched `g++` lines as engines), then 116 s for the remaining links (`build.sh --compile --jobs 1 linux`): about 61 min in all |

A warm rebuild (ccache filled, small patch) is not yet measured. `--jobs 12` leaves room for
engines on the shared host; an idle Tokyo can use `--jobs 22`.

For reference, the spike's Windows cross-compile on Zeus WSL took 16 min 15 s.

## Store the build

Copy both install trees to `~/recoil-spike/builds/airts-main-<short hash>/linux/` and
`.../windows/`, and log the sync version:

```bash
H=$(git rev-parse --short=10 HEAD); D=~/recoil-spike/builds/airts-main-$H
mkdir -p $D && cp -a build-amd64-linux/install $D/linux && cp -a build-amd64-windows/install $D/windows
$D/linux/spring-headless --sync-version | tee $D/sync-version.txt
```

The Windows `spring.exe` reports the same string (`spring.exe --sync-version` on Zeus;
`strings -n 12 spring.exe | grep airts-` checks it on Tokyo). `spring-dedicated` prints nothing
for `--sync-version`; its infolog banner shows the version.

## Before shipping

1. The gate in `PATCHES.md` passed for this commit, including the CI run on `airts/main`.
2. `--sync-version` of the Linux build ends in `airts-<n>` with `<n>` equal to
   `airts/PATCH_LEVEL`, and the Windows build prints the same string.
3. Tag the commit `airts-<yyyy>.<mm>.<n>` and push the tag to this fork. The tag does not change
   the version string (only upstream's numeric tags feed `git describe`).
4. GPL: ship the matching source archive (`git archive` of the tagged commit plus submodules) or
   a written offer pointing at the tag in this public repository, and the licence files from
   the install tree (`LICENSE`, `COPYING`, `gpl-2.0.txt`, the third-party licences under
   `share/`, if the packager keeps them).
5. The launcher ships the engine with the game, so players never mix engine versions.
