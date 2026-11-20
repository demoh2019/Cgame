# Seamless terrain anti-tiling for High / Ultra

The game's thirteen-layer PBR terrain already includes biomes, roads, site
paving, rain response, mipmapped texture arrays, triplanar cliffs and
camera-distance normal-map LOD. On wide grassy plains, repeated texture
patterns may still be noticeable.

Inspired by Unity HDRP terrain Shader Graph's texture tiling breakup,
this feature warps horizontal ground material coordinates with **already
computed** continuous mid- and macro-scale terrain noise. This works in
world space, so material details stay stable across streamed chunk borders.
The same warped coordinates and corrected mip derivatives drive albedo
and normal maps, preserving surface shape and texture filtering.

No extra texture fetches, noise octaves, geometry rebuilds, draw calls,
intermediate buffers or textures are required. Performance / Balanced
use zero-strength and skip the warp entirely. High uses 0.24 and Ultra
0.42, both bounded by 0.55. The rain shader, world map, road layout,
paving masks, 13 layers and cliff triplanar UVs are intentionally unchanged.

Implemented with a single renderer global registered in project.godot;
GraphicsQuality.apply updates all existing and newly streamed chunks,
including when Auto mode adjusts graphics detail.

Regression: res://tests/test_terrain_antitiling.gd
Run: godot --headless --path game --script res://tests/run_all.gd

Measure frame pacing and compare before/after shots on real GPUs to
retune the visual strength; static tests do not constitute a GPU benchmark.
