# Upstream report draft: QTPFS background path searches crash (SIGSEGV) with worker threads

Draft of an issue for beyond-all-reason/RecoilEngine. Not filed; Jonathan decides whether and when.
Evidence stays on Tokyo under `~/recoil-spike/evidence/qtpfs-crash/` and `~/recoil-spike/e2-qtpfs/`.

## Title

QTPFS: segfaults in background path searches (SharedFinalize, SmoothPathIter, LoadPartialPath) with WorkerThreadCount > 1

## Body

Engine: master at ff8e2a1 (`2026.09.01-5-gff8e2a1`, Linux, gcc 13.3, RelWithDebInfo), headless, one
process, two Lua AIs, `system.pathFinderSystem = 1` in `modrules.lua`. Upstream master has no
commits after ff8e2a1 touching `rts/Sim/Path/QTPFS/` as of 2026-09-30, and we found no open issue
or pull request for this.

The same start script (fixed `FixedRNGSeed`, no human input) crashes at a different frame and in
a different function on most runs when the thread pool has more than one worker, and never
crashes single-threaded:

| Variant (4 runs each, same script and archives) | Result |
|---|---|
| QTPFS, default `WorkerThreadCount` (24-thread host) | 3 of 4 segfault: frame 14806 in `IPath::SetSourcePoint` (Path.h:278) from `PathSearch::SharedFinalize` (PathSearch.cpp:2617); frame 34621 in `PathSearch::LoadPartialPath` (PathSearch.cpp:398); frame 47341 in `IPath::SetPoint` (Path.h:239). The fourth ends at GameOver frame 50010 |
| QTPFS, `WorkerThreadCount = 1` | 4 of 4 finish, all at GameOver frame 51345 |
| Same archive with `pathFinderSystem = 0` (HAPFS), default threads | 4 of 4 finish, all at GameOver frame 14850 |

In a 36-game batch with QTPFS, 5 games crashed (frames 9841, 10711, 11131, 22351, and one without a
trace); the other traces were `SetSourcePoint` from `SharedFinalize` (three) and
`PathSearch::SmoothPathIter` (PathSearch.cpp:2279). The same 36 games with HAPFS had no crash.

Every trace runs on a thread-pool worker inside the background task started by
`PathManager::ExecuteQueuedSearches` (`for_mt_background`, PathManager.cpp:1096, "Do NOT impact
this group while the background tasks are running"):

```
<03> rts/Sim/Path/QTPFS/Path.h:278          QTPFS::IPath::SetSourcePoint(float3 const&)
<03> rts/Sim/Path/QTPFS/PathSearch.cpp:2617 QTPFS::PathSearch::SharedFinalize(IPath const*, IPath*)
<04> rts/Sim/Path/QTPFS/PathManager.cpp:1201 QTPFS::PathManager::ExecuteSearch(PathSearch*, NodeLayer&, unsigned, bool)
<05> rts/Sim/Path/QTPFS/PathManager.cpp:1098 ExecuteQueuedSearches()::{lambda(int)#2}
<06> rts/System/Threading/ThreadPool.h:726   ForBackgroundTaskGroup<...>::ExecuteStep(int)
```

`SetSourcePoint` writes `points[0]` right after `dstPath->CopyPoints(*srcPath)`, so the head path
of the share chain (`registry.get<IPath>(chainHeadEntity)`, PathManager.cpp:1199) had no points
when it was copied. Our reading, not verified: the background searches read other paths' `IPath`
components (the share-chain head in `SharedFinalize`, the partial head in `LoadPartialPath`) and
the registry (`registry.all_of<PathSearchRef>(...)`) while the main thread's sim systems can
still change or delete those paths, so a search can copy a path that is being rewritten. The
single-threaded runs being both crash-free and identical fits that reading.

The same engine is also not deterministic across runs with default threads on a movement-heavy
fixture that uses HAPFS (GameOver frame varies between runs; identical with
`WorkerThreadCount = 1`), in every release we tried back to 2026.06.12; that may or may not be the
same class of problem.

Reproduction: our arena matches (two Lua AIs, ground armies, `pathFinderSystem = 1`), each start
script run several times with default threads. We can share the archives, start script and
logs.
