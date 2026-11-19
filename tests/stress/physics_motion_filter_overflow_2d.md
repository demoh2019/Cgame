# 2D body motion: early BVH filtering (GodotPhysics)

## Why this change exists

`GodotSpace2D::test_body_motion()` drives CharacterBody2D/kinematic collision
queries, including penetration recovery, motion sweep, and final rest-contact
selection. It used to collect the first `INTERSECTION_QUERY_MAX = 2048`
AABB proxies and only then discard unrelated areas, incompatible
collision layers, excluded bodies/objects and collision exceptions.

In a dense or multi-layer scene, irrelevant proxies could occupy **all**
2048 positions and hide the one relevant collider. This is particularly
likely with thousands of monitoring areas overlapping a CharacterBody2D.

## Existing implementation and new regression

The early-filtering code was **already merged into develop concurrently**;
this patch adds independent performance/correctness checks for it rather
than replacing the working implementation.

`_cull_aabb_for_body()` uses the existing `GodotBroadPhase2D::visit_aabb()`
visitor. It rejects non-body proxies, the moving body itself, query exclusions,
collision-mask mismatches, and exceptions before appending a candidate to the
scratch arrays.

All three existing body-motion phases use the same filtering:
1. recovery from overlaps;
2. swept motion / safe fraction search;
3. final rest contact.

This mirrors the already present 3D body-motion early filter and follows
Jolt's recommendation to reject ineligible objects as early as possible.

**Remaining limitation:** the candidate array still stores at most **2048
eligible** body/shape proxies. This change prevents ineligible objects from
consuming the cap; it does not remove the cap for an extreme overlap of
2048+ genuinely colliding shapes. A separate streaming-narrowphase refactor
is required for that case, especially because the 2D one-way platform and
recovery logic shares per-phase state.

The previously merged 2D implementation also avoids dividing by zero when `motion_length == 0`.
This preserves a zero displacement vector for stationary recovery queries
without changing the collision solver's iteration counts.

No new persistent body memory or extra heap allocation is introduced.
Existing broadphase visitors have a fixed stack with an overflow path
for exceptionally deep/unbalanced BVH trees.

## Reproducible stress test

The integrated stress case `physics_motion_filter_overflow_2d` creates
a kinematic moving circle and a static obstacle, then floods the swept AABB
with at least 2304 monitoring areas and 128 wrong-layer static bodies.
It reinserts the target after the irrelevant proxies to expose vulnerable
insertion orders, and verifies motion detection, RID exclusions, body
collision exceptions, and zero-displacement behavior.

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_motion_filter_overflow_2d \
  --scale 8 --frames 90 --repeats 5 \
  --timeout 600 --rss-limit-mib 6144 \
  --output out/physics-motion-filter-2d.json

python3 -m unittest discover -s tests/stress \
  -p 'test_physics_motion_filter_2d.py' -v
```

The pure Python contracts are structural checks; real correctness, FPS
impact and RSS must be verified by the headless Godot executable. Compare
the same scene on identical hardware and engine settings before claiming
a speed or memory improvement.
