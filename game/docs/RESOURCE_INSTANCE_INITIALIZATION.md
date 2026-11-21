# Albion After — batch initialization of world resources

The canonical game at `game/scripts/client/chunk_view.gd` now prepares
resource transforms, tier colors and immutable server entity IDs before
submitting each MultiMesh group. World generation, materials, tier pigments,
visibility state and authority remain unchanged.

`game/scripts/client/resource_instance_initializer.gd` prevalidates every
instance's transform and tint. For groups with 12 or more instances, it uses
native CGame `MultiMesh.set_instance_transforms_batch(indices, transforms)`
and the new `MultiMesh.set_instance_colors_batch(indices, colors)` where
available. Smaller batches and standard Godot 4.4+ use the legacy per-slot
setters. A rejected native call triggers validated per-instance fallback.

C++ `set_instance_colors_batch` validates all indices and RGBA components
before any renderer changes, including duplicates and nonfinite colors.
It accepts hidden slots and both 2D/3D formats. This is one scripting call
for N color updates, **not** one GPU command or faster full-buffer upload.
Prefer `MultiMesh.buffer` for dense contiguous bulk uploads if the entire
buffer is being initialized from structured arrays.

Native C++ tests: `tests/scene/test_multimesh_color_batch.cpp`.
Main-game headless tests: `game/tests/test_resource_instance_initializer.gd`
included in `game/tests/run_all.gd`.

To validate in a built Godot/CGame engine:
```bash
godot --headless --path game --script res://tests/run_all.gd
```

No executable Godot/engine build is available in the current tool environment.
C++ compilation, GDScript execution and FPS gains are therefore unverified.
