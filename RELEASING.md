# Releasing AIRTS engine builds

Every release comes from a commit on `airts/main` that passed the gate in `PATCHES.md`. The
Windows and Linux builds of one commit share one sync version (`<git describe> airts-<n>`), so
they play together; builds of different commits do not.

## Where builds run

Release builds run on Zeus in WSL `Ubuntu-24.04` (24 threads, 30 GB), in the clone `~/airts-recoil`
(origin is this fork over HTTPS, read-only; submodules initialised recursively). The Windows
build uses upstream's container build (`docker-build-v2/build.sh windows`, images pinned by
digest in `docker-build-v2/images_versions.sh`); the Linux build is native (gcc 13, gold,
ccache). One script does both, times them, and checks that both report the same sync version:

```bash
cd ~/airts-recoil
git fetch origin && git checkout --detach origin/airts/main
git submodule update --init --recursive
airts/scripts/build-release-zeus.sh          # add "cold" to empty both compiler caches first
```

Output: `~/airts-builds/airts-main-<10-char hash>/linux/` and `.../windows/` (from Windows:
`\\wsl$\Ubuntu-24.04\home\palimon\airts-builds\`), `sync-version.txt` next to them, logs in
`~/airts-builds/logs/`. The source tree is mounted read-only into the Windows container: do not
edit or check out files while a build runs. The script runs no engine; before running one on
Zeus, check `tasklist` for other `spring` processes (the tester runs gates on Zeus).

The native Linux build links against Ubuntu 24.04's system libraries (SDL2, OpenAL, DevIL,
GLEW and the rest), so it runs on Ubuntu 24.04 hosts such as Tokyo but is not a portable
release. A portable Linux archive for players comes from `docker-build-v2/build.sh linux`
(measured on Tokyo, below).

Copy the Linux tree to Tokyo for tests there (from Git Bash on Zeus):

```bash
H=<10-char hash>
wsl -d Ubuntu-24.04 -- tar -C ~/airts-builds/airts-main-$H -cf - linux |
  ssh palimon@192.168.1.250 "mkdir -p ~/recoil-spike/builds/airts-main-$H && tar -C ~/recoil-spike/builds/airts-main-$H -xf -"
```

### Build times

Zeus WSL, 2026-09-30, `airts/main` at `1fec2d87d9`, no other build running (measured):

| Build | Cold (empty compiler cache) | Warm (full cache, fresh build dir) |
|---|---|---|
| Windows, `docker-build-v2/build.sh windows` (all 24 threads) | 659 s (10 min 59 s) | 25 s |
| Linux native, full tree plus install | 468 s (7 min 48 s) | 61 s |

Tokyo, 2026-09-30, `dc05e27162`, both cold at `--jobs 12` while other agents' engines kept the
load average between 60 and 260 (upper bounds, kept for reference):

| Build | Wall time |
|---|---|
| Windows (`build.sh --jobs 12 windows`) | 3189 s (53 min 9 s) |
| Linux, portable (`build.sh --jobs 12 linux`) | 3533 s until the host's process watchdog killed the `spring-headless` link (it matched `g++` lines as engines, 05:05Z to 05:09Z), then 116 s for the remaining links: about 61 min |

The spike's Windows cross-compile on Zeus WSL took 16 min 15 s.

### Builds on record

| Commit | Where | Sync version |
|---|---|---|
| `1fec2d87d9` | Zeus `~/airts-builds/airts-main-1fec2d87d9/{linux,windows}`; Linux copy on Tokyo `~/recoil-spike/builds/airts-main-1fec2d87d9/linux` | `2026.09.01-16-g1fec2d8 airts-2` |
| `dc05e27162` | Tokyo `~/recoil-spike/builds/airts-main-dc05e27162/{linux,windows}` (docker, portable Linux) | `2026.09.01-13-gdc05e27 airts-2` |

`spring-headless --sync-version` prints the version; for `spring.exe` use `spring.exe
--sync-version` on Windows or `strings -n 12 spring.exe | grep airts-`. `spring-dedicated` prints
nothing for `--sync-version`; its infolog banner shows the version.

The version string abbreviates the hash to 7 characters (`git describe --abbrev=7`), and git
lengthens an abbreviation that is ambiguous among the objects of that clone. Two clones with
different object sets could therefore, rarely, print different strings for one commit; compare
`sync-version.txt` across hosts before a mixed-host test.

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
