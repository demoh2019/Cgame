# Conservative clipped swept-AABB pruning for 2D/3D shape casts

## Related techniques in other engines

Box2D uses time-of-impact fractions and clipped shape casts for repeated
narrowphase collision checks. Jolt recommends filtering candidates early,
before reaching expensive collision tests. Cgame already uses streaming
BVH callbacks, but the shape-cast solver still received every candidate
inside the **full** displacement swept bounds even after a closer hit was
known. Rapier's BVH scene queries follow the same broadphase-then-exact
narrowphase separation. No code from any external engine is copied.

## Optimization

In `GodotPhysicsDirectSpaceState2D::cast_motion` and
`GodotPhysicsDirectSpaceState3D::cast_motion`:

1. The original full-sweep BVH query is **unchanged**. It is always used
   so we never prematurely terminate candidate discovery.
2. Once a solver finds a collision earlier than the current `best_safe`,
   compute a smaller, conservative swept AABB from the query shape's
   initial bounds and the vector `motion * best_unsafe`.
3. Expand by the **nonnegative** query margin plus `CMP_EPSILON` for
   contact boundaries and floating-point uncertainty.
4. For later BVH candidates, compare this shorter AABB against the
   collision object's **existing cached broadphase shape AABB**.
   Candidates that cannot possibly improve the nearest collision time
   skip the expensive 2D SAT or 3D GJK distance checks.

The clipped bound is recomputed **only** when a better time-of-impact is
found, not on each candidate, and the extra AABB test is skipped until
a collision has shortened the sweep. The existing 8 solver iterations,
one-way/collision filters, RID exclusions, and 3D rest-info selection
are left intact.

### Safety invariant

For a fixed-orientation shape moving linearly by `motion`, its AABB at
any time `t` between zero and `best_unsafe` lies inside the union of
its start AABB and that AABB translated by `motion * best_unsafe`.

Thus a collider whose cached world bounds do not overlap the expanded
union cannot be hit **earlier** than the already found hit. The cached
collider bounds conservatively account for the shape and its broadphase
padding/CCD expansion.

A shared inline helper in `servers/physics_cast_motion_pruning.h`
implements that bound for both `Rect2` and `AABB`. No new per-collider
state, persistent cache, or heap allocations are introduced; each cast
stores only initial and clipped bounds.

## Reproduction

Native C++ `tests/servers/test_physics_cast_motion_pruning.cpp`
covers 2D/3D swept bounds, reverse displacement, grazing contacts,
zero movement and nonnegative margins.

Python `tests/stress/test_physics_shapecast_clipped_aabb.py`
checks source contracts and the conservative bound across 4,000
deterministic randomized 2D/3D shapes and movements.

Headless regression creates **4096 distant static colliders plus
2 near obstacles in each dimension**, verifying that the nearer one
wins, excluding it reveals the second, and nonmatching collision
masks produce no hits:

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_shapecast_clipped_aabb.py' -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_shapecast_clipped_aabb_regression.gd
```

To determine whether this speeds up real scenes, compare identical
builds/scenes with near-first and far-first obstacle orders, both 2D
and 3D, and measure query latency, CPU and peak RSS. There may be
little benefit for scenes without an early known collision or with
every body clustered near the same point. The extra AABB checks can
even create overhead in those scenes.

The native C++ build, Godot runtime and CI results are **not** verified
in this authoring environment; synthetic geometry checks are not a
measured FPS or RAM improvement.
