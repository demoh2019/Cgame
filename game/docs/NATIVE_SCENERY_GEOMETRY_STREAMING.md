# Native world-scenery MultiMesh geometry construction

## Objective

Albion After already batches repeated trees, rocks and foliage by visual
category and splits dense MultiMeshes into 32 m spatial buckets. Godot
cannot frustum-cull individual MultiMesh instances; it culls the whole
batch. See the official
[Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

However, building each resident visual bucket involved two GDScript hot
loops: writing 12/16 raw floats per transform and merging an AABB for
every model. During fast rides or camera movement, many visual-only
batches are constructed on the main thread.

## Implementation

- The Cgame-native `MultiMesh.pack_transform_buffer(transforms, colors)`
  builds a single `PackedFloat32Array` using Godot's row-major GPU record
  format. It handles scaled/rotated transforms and optional 4-float color
  channels; rejects bad types, counts and custom-data format. It performs
  **no** GPU upload.
- `MultiMesh.transformed_mesh_bounds(transforms, margin)` makes a
  conservative native union of each transformed mesh AABB, supporting
  rotated and nonuniformly scaled vegetation and landmarks. It is not a
  centers-only approximation that might clip tall or inclined trees.
- `SceneryBatches.add` uses both new methods when the forked Cgame engine
  provides them. The corresponding original `packed_group` and
  `bounds_for` routines remain unchanged as stock-Godot fallback.
- The existing plant-only tint uses the same exact world-space color hash
  and emits an optional `PackedColorArray`, so seasonal pigment variation
  stays stable when chunks stream out and return.
- Every group still creates **one** MultiMesh, **one** buffer upload and
  one scene node. Its draw distance, shadow state and game/server logic
  are not changed.

This is similar in purpose to Unity Entities Graphics
[batched drawing and culling](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.0/manual/entities-graphics-performance.html)
and Unreal World Partition
[HLOD](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-hierarchical-level-of-detail-in-unreal-engine).
It does **not** claim to implement their complete data-oriented or HLOD
systems.

## Verification

```sh
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
# With tests=yes Cgame binary:
godot --headless --test --test-case="*Native static scenery transforms and visible bounds*"
```

- Native C++ tests compare the row-major 12/16-float records for rotated
  and nonuniformly scaled transforms and colors, as well as complete AABB
  merging against Godot's geometry operations.
- The game test compares each native buffer with the original
  `SceneryBatches.packed_group` byte-for-byte, checks world placement,
  preserved tint, conservative cull bounds and the real live batch path.
- Stock Godot runs the same suite on the script fallback.
- A dedicated native-build CI job tests both the engine and game
  integration. No speedup claim is made before CPU profiling in real
  streaming scenes. Measure the time spent in `_build_nature_decor_entry`
  and the frame-time p95/p99 on a native Cgame build.

No assets, network messages, world seeds, physics or game save data change.
