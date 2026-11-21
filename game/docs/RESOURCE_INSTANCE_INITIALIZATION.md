# Albion After — atomic full-buffer resource initialization

CGame 3D MultiMesh API: `set_instance_transform_color_buffer(transforms: Array, colors: PackedColorArray) -> bool`.

The method validates the **entire** input (3D format, use_colors enabled, use_custom_data disabled, exactly instance_count transforms/colors, and finite transform/color values) before modifying any instance. A valid non-empty input is packed in native C++ and uploaded once with `MultiMesh.set_buffer()` / RenderingServer, **not** N individual renderer commands. An empty 0-instance input succeeds without GPU allocation. The existing engine's `pack_transform_buffer()` is reused to guarantee the 16-float (12 matrix + RGBA) layout.

In the **canonical Albion After** `game/scripts/client/chunk_view.gd`, `resource_instance_initializer.gd` now chooses that native API for dense groups of at least 12 world resources. On stock Godot 4.4+, it builds a PackedFloat32Array with exactly the same 16-float records and assigns `MultiMesh.buffer` in a single upload. Tiny groups use original setters; groups with `use_custom_data` set retain the per-instance path so no animation payload is overwritten.

World positions, resource tiers/tints, stable server IDs, masks and persistence remain unchanged. For sparse depletion/restoration, use the existing `multimesh_resource_updates.gd`, which avoids rewriting the entire buffer.

Tests: engine `tests/scene/test_multimesh_full_color_buffer.cpp`, and game `game/tests/test_resource_full_buffer.gd` (registered in `run_all.gd`). The test covers nontrivial Basis rotations/scaling, row-major packing, RGBA, invalid inputs without partial renderer changes, custom-data preservation, small groups and empty buffers.

Run in a built CGame engine:
```bash
godot --headless --path game --script res://tests/run_all.gd
```

No executable Godot/CGame engine is installed in this session, so native compilation, headless GDScript runs, scene rendering, and GPU frame-time improvements remain unverified. It is a reduction in renderer command count for dense initialization, not a measured frame-time or memory optimization.
