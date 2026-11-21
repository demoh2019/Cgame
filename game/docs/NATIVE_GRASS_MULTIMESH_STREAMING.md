# Native MultiMesh density-prefix shuffling (Albion After / Cgame)

## Why

The Albion After grass renderer already uses a spatially tiled MultiMesh with
distance-based geometry and visible-instance-count LOD. Every 16 m grass tile
stores a packed 3D transform and RGBA tint per tuft (16 floats per instance).
To avoid fading complete rows from one side when distant instances are hidden,
it shuffles whole instance records once at tile generation time.

The old `GrassField.shuffle_instances` performs Fisher-Yates in GDScript and
swaps 16 array fields on each iteration. It is an unnecessary CPU scripting
cost during world streaming, especially when many new chunks appear.

## Implemented

- `MultiMesh.shuffled_instance_buffer(buffer: PackedFloat32Array, seed: int)`
  is a new Cgame native API.
- The native code automatically derives stride from the MultiMesh's 2D/3D
  transform format and optional color/custom-data flags (8/12/16/20 floats).
  It validates the exact instance count and returns input unchanged on
  malformed lengths.
- PCG seed and Fisher-Yates swaps exactly match the original Godot
  `RandomNumberGenerator.randi_range(0, i)` loop. Whole records move as one
  unit; matrix columns, colors and shader custom values cannot be separated.
- The method returns a copy-on-write result, leaving the original buffer
  unchanged. No rendering-server calls or GPU uploads are performed by it.
- Albion After's real `GrassField.build_tile` uses the native implementation
  when available and otherwise uses the original GDScript routine. It still
  submits the completed result to `MultiMesh.buffer` once.

Original grid positions, per-instance colors, seeded generation and
`visible_instance_count` behavior are preserved on both engine variants.

## Tests

The native engine test is registered in
`tests/scene/test_multimesh_visibility.cpp` and checks deterministic seeded
permutations, no source mutation, invalid buffer sizes and 20-float records.
The game regression `game/tests/test_native_multimesh_shuffle.gd` compares
the exact native buffer against the existing game-side Fisher-Yates reference,
checks all 16 channels per grass tuft and confirms integration into the
actual tile builder. It runs under both headless game and graphics suites.

```sh
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
# Build Cgame with tests enabled, run:
# [SceneTree][MultiMesh] Seeded native buffer shuffle preserves full instance records
```

No measured speedup is claimed without profiling a native Cgame build.
This optimization reduces GDScript loop overhead during grass-streaming,
not GPU pixel cost. To evaluate in-game impact, capture CPU timings while
rapidly traversing unexplored forest/meadow chunks and compare against develop.

## Design references

- Godot MultiMesh packed 3D data layout (12 floats transform + 4 color):
  https://docs.godotengine.org/en/stable/classes/class_multimesh.html
- Godot rendering and LOD guidance: use smaller spatially culled batches
  because individual MultiMesh instances cannot be independently frustum-culled.
  https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- Unreal World Partition streaming for incremental resident-cell scheduling:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
