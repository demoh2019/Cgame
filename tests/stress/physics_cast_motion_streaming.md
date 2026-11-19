# Built-in GodotPhysics 2D/3D cast_motion: streaming BVH candidates

## Problem

Before this change, both `GodotPhysicsDirectSpaceState2D::cast_motion`
and `GodotPhysicsDirectSpaceState3D::cast_motion` collected **at most
2048** broadphase AABB proxies, then applied the user-provided collision
layer masks and RID exclusions. In layered or crowded scenes, those slots
could be exhausted by rejected objects. A valid obstacle later in the BVH
could therefore be ignored and the query could incorrectly return a safe
motion fraction of `1.0` (no collision).

## Implementation

- Reuse the `GodotBroadPhase2D/3D::visit_aabb()` callback to traverse
  all proxies overlapping the existing swept AABB.
- Apply `collision_mask`, `collide_with_bodies`,
  `collide_with_areas`, and RID exclusions before narrowphase.
- Keep the current 8-step iterative time-of-impact search, original
  initial-overlap rejection and minimum safe/unsafe motion selection.
- Preserve optional 3D rest/collider information selection; unlike
  `intersect_shape()`, the sweep cannot stop on the first collider
  because a later candidate may be encountered earlier along the motion.
- **Fix a 3D sweep-state bug:** the 3D motion shape was shortened to a
  binary-search fraction and previously reused as the initial sweep for
  the next candidate. It is now reset to the full motion at the start of
  each exact candidate check.
- Compute the 3D motion transformed to local coordinates only once and
  multiply that cached vector by each binary-search fraction, avoiding
  repeated `Basis::xform()` on a hot path.

Uses the existing iterative BVH stack; no per-body memory or unbounded
candidate-array allocation is added. A deep, unusually unbalanced BVH can
still use the helper's existing overflow storage. The callback executes
under the ordinary BVH query lock and must not mutate the broadphase.

## Regression

`physics_cast_motion_overflow_regression.gd` creates 4,096 static bodies
on collision layer 1 and one matching body on layer 2, all along the same
2D/3D sweep. It asserts that an unblocked cast sees the matching body,
wrong-layer and excluded-RID casts have no collision, and a second, nearer
matching body wins. It reports the first-cast latency in microseconds.

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_cast_motion_overflow_regression.gd
```

Run against a matching baseline build on identical hardware and use the
regular `physics_raycast_2d/3d` and stress suite for other physics queries.
The built-in GodotPhysics backend must be selected. This patch **does not**
fix the separate 2048-candidate limit inside `GodotSpace2D/3D::test_body_motion`;
that path requires its own careful data-flow refactor.

Compilation, native tests and measured speedups are not confirmed until
the target build/CI and the above regression have actually executed.
