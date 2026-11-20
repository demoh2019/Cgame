# GPU-friendly grass density LOD

The game already renders meadow tufts as 16 m MultiMesh tiles and switches
between 18-, 9-, and 4-blade geometry with distance and hysteresis.
This update adds a complementary **visible-instance density LOD**:

- 0–18 m: 100% of tufts, original high-detail silhouettes.
- 18–34 m: gradually drop to 72% of tufts.
- 35–55 m: gradually drop to 40% of tufts.
- Beyond: capped at 40% (the existing grass shader fades all blades out).
- A deterministic one-time Fisher–Yates shuffle of the packed transform-and-
  color buffer means every prefix used for GPU drawing is spread over the
  whole tile, instead of leaving rectangular strips.
- On the existing 0.35 s LOD update, `MultiMesh.visible_instance_count`
  changes without rebuilding geometry, regenerating random positions,
  reallocating meshes or touching server simulation state.

This follows the *principles* of hierarchical geometry reduction in
Unreal/Nanite, GPU instancing in Unity, and the native Godot MultiMesh
draw-count control. It is not a Nanite or GPU-occlusion implementation.

At far distances the **submitted tuft count** is bounded at 40% of before;
combined with 4 vs 18 blades per tuft, the theoretical grass geometry
submission is about 8.9% of its closest tier (before the existing shader fade).
This is a geometry budget estimate, **not a measured FPS gain**. Actual frame
rate depends on shader, fill-rate, drivers and visibility.

Run: `godot --headless --path game --script res://tests/run_all.gd`.
The expanded `game/tests/test_grass_lod.gd` covers geometry, hysteresis,
density bounds, deterministic shuffle, intact colors and complete placement
permutations. Profile GPU frame time on desktop and mobile before retuning.
