# Dithered foliage end-of-range fade (November 2026)

Foliage is already GPU-instanced via `MultiMesh` and divided into camera-cullable batches. Previous distance caps caused abrupt disappearance of tree and bush groups at the quality profile's configured visibility limit.

This update follows the **per-instance foliage fade** idea in Unreal's foliage scalability, adapted to Godot's existing rendering pipeline. It uses a deterministic 4×4 Bayer screen-space threshold to discard only a shrinking fraction of fragments near the distance cap. There is **no alpha blend**, no transparent sorting, no new texture or material pass, no per-frame CPU work, and the existing foliage MultiMeshes remain shared.

- **Performance / Balanced:** skip dithering; keep the original cheapest near/far behavior.
- **High:** smoothly thin each tree/bush over the last **14 metres** before its quality-specific cull distance.
- **Ultra:** do so over **22 metres**.

The shader reuses each instance's already calculated camera distance from the wind LOD, so there is no second distance calculation. Dithering itself is evaluated only inside the fade band, not on all visible plants. It operates on trees, procedural painted trees, Kenney expanded trees, bushes and berries. Monuments, landmark structures and undergrowth decor with varying authored cull distances are **not** incorrectly faded. Opaque trunk pixels are clipped rather than becoming transparent; original cutout leaves, textures, alpha-to-coverage, PBR shading, normals and shadows are preserved.

Tree/bush cull distances come from `SceneryLod.range_for` and are published via global shader uniforms alongside the normal graphics profile settings. This prevents shader thresholds from drifting away from the actual per-batch draw budgets.

The 4×4 ordered pattern is deliberately fixed in screen space to avoid noisy animated random values. Like other dither fades, it can show a slight stipple pattern while walking. View on real hardware (including Forward+ TAA/FSR2 and Compatibility) before declaring visual acceptance.

References:
- [Unreal foliage culling + per-instance fade](https://dev.epicgames.com/documentation/unreal-engine/foliage-mode-in-unreal-engine)
- [Godot visibility ranges](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Godot rendering limitations / transparent sorting](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html)

## Validation

Run `godot --headless --path game --script res://tests/run_all.gd`. Added regression checks verify material role classification, exact quality-to-culling-distance mapping, a no-work low-quality path, opaque discard and preserved alpha scissor.

Capture a fixed camera track moving slowly across a wooded area, with trees at the 205/260 m and bushes at the 145/185 m thresholds. Inspect stopping/starting, any visible fade mesh silhouette stippling, shadow-map stability and vegetation moving under the wind. Compare median/p95 GPU frame times; *no measured FPS improvement is claimed without a hardware benchmark*.
