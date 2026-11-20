# Spatial scenery culling (November 2026)

## Problem and reference engines

Godot's `MultiMesh` draws all its instances when any part of the group's AABB
is visible; an entire 64 m chunk may contain flowers or props outside the
camera frustum. Godot recommends splitting large MultiMeshes into geographical
groups (https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).
This follows the same **visibility-first** principle as Unreal Nanite's
fine-grained culling and Unity's GPU-instanced batching, without claiming to
reimplement Nanite or require a renderer change.

## Implemented

- `scripts/client/scenery_batches.gd` takes the existing transforms and splits
  a batch into **32 m cells** only at **48 or more objects**. Smaller batches
  remain one draw call, avoiding an explosion in CPU submission work.
- Each sub-batch is still a GPU `MultiMesh`, with a custom conservative AABB
  formed from every fully transformed mesh bounding box. A 0.6 m margin keeps
  wind-driven vegetation within visibility bounds.
- The existing visibility range, shadow choice, placement, rotation, scales,
  and deterministic procedural seeds are preserved.
- Both optional Quaternius foliage and installed CC0 Kenney/Poly Haven decor
  use this helper, while networked gameplay structures and collision stay
  untouched.
- `tests/test_scenery_batches.gd` verifies sparse and dense grouping, total
  instance preservation, range and bounding-box containment.

## Performance and visual acceptance

This is a culling optimization, not a promised FPS increase. Fragmenting a
batch can cost additional draw calls when all cells are on-screen. It should
reduce GPU work when only a portion of a busy foliage batch is visible.

Run after importing the game in Godot:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

Profile the same camera path in a dense forest, meadow and ruined site, at
1280x720 and at target device resolution. Record p50/p95 frame time, draw
calls, vertex/triangle count, and visible batch count in Performance / Balanced
/ Ultra profiles. Compare against the preceding `develop` commit. If draw-call
overhead dominates, raise `SPLIT_MIN_INSTANCES` to 64–96 before increasing
tile subdivision. No physical GPU benchmark has been performed here.
