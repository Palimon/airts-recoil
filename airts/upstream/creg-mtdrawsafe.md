# Upstream pull request: register CProjectile::mtDrawSafe with creg

Text for a pull request to beyond-all-reason/RecoilEngine, from the first commit of
`patch/creg-mtdrawsafe` (`rts/Sim/Projectiles/Projectile.cpp`, one line). Not opened; Jonathan
decides whether and when.

## Title

Register CProjectile::mtDrawSafe with creg (fixes testCreg)

## Body

#3232 (Particle draw optimizations, a53282a) added `bool mtDrawSafe` to `CProjectile` but no
entry in its `CR_REG_METADATA`. Since then `spring-headless --test-creg` (the `testCreg` ctest)
fails with 37 of 216 classes broken:

```
Warning:   Missing member(s) in class CProjectile, between drawSorted & blockPreciseCol, ~1 byte(s)
...
Warning: CREG Results: 37 of 216 classes are broken
```

The field is also missing from save games. `ShieldSegmentProjectile` and `TracerProjectile` set
it per instance, so this registers it with `CR_MEMBER` rather than `CR_IGNORED`:

```diff
 	CR_MEMBER(drawSorted),
+	CR_MEMBER(mtDrawSafe),
 	CR_MEMBER(blockPreciseCol),
```

Tested: `ctest -R testCreg` passes on Ubuntu 24.04 (gcc 13); the other unit tests are unchanged.
