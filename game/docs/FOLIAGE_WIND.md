# GPU foliage wind and storm response

The swaying tree and bush meshes now use a stable arithmetic hash based on the world-space root to diversify leaf colour and microsurface roughness. This avoids a trigonometric call per vertex; the appearance remains varied without adding textures or draw calls.

The existing distance-based wind LOD still suppresses trigonometric animation for foliage beyond its fade range. During storms, foliage receives up to 65% stronger wind displacement from the already-updated global `aa_weather_wetness` parameter. Weather blending is continuous and does not update any individual tree on the CPU.

The change affects only vertex positions in the visual shader. Collision, authoritative simulation, world generation, save state and multiplayer consistency are unchanged.

**Validate:** Run `godot --headless --path game --script res://tests/run_all.gd`, then capture identical forest scenes in clear weather and storms at different camera distances and quality settings. Compare GPU frame time; lower shader operation counts are not themselves measured FPS gains.
