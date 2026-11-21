# Albion After: sparse MultiMesh resource state updates

The canonical game in `game/` now updates sparse server-owned resource visuals through `game/scripts/client/chunk_view.gd::apply_state`. Only changed resource IDs are sent per MultiMesh chunk. The CGame API `MultiMesh.set_instance_transforms_batch(indices, transforms)` validates all inputs and performs per-instance RenderingServer updates from one script call. Standard Godot uses an equivalent prevalidated per-instance fallback. Game server inventory, authority, stable IDs and save format are unchanged.

Tests: `game/tests/test_multimesh_resource_updates.gd` is registered in `game/tests/run_all.gd`. Run `godot --headless --path game --script res://tests/run_all.gd` and compile engine native tests on a machine with Godot and C++ build tools. This environment has no Godot executable or C++ engine build, so runtime/GPU results remain unverified.
