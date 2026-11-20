# Curvature-aware PBR terrain in the engine and Albion After game

## Motivation

Large photorealistic worlds (Unreal, Unity HDRP, many scanned landscapes)
use more than direct normal-map lighting: broad ground cavities retain subtle
ambient darkness and exposed ridge tops catch light. Our streaming world
previously had layered PBR textures, clouds, SSR/SSIL and local contact AO,
but no **heightfield curvature data** to distinguish natural depressions
from ridges. This feature adds a small, artist-controlled approximation
without a ray pass, new textures, meshes or extra draws.

Reference approaches:
- Unreal materials / ambient occlusion:
  https://dev.epicgames.com/documentation/unreal-engine/physically-based-materials-in-unreal-engine
- Unity HDRP lighting:
  https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@latest/index.html
- Godot spatial vertex color / AO:
  https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html

## Engine change (C++)

`ChunkedTerrain3D` in the custom Godot fork now exposes
`set_color_data(PackedColorArray)` and `get_color_data()`.

- The optional packed color field has the **same width*depth** as height
  samples. An invalid size or nonfinite color is rejected.
- `HeightmapTerrainGeometry::build_chunk()` copies the authored colors
  into the GPU vertex stream using the source-grid coordinates for each
  selected LOD. Skirt vertices retain their matching surface colors.
- If no colors are authored, the engine allocates **no color attribute**,
  keeping backward compatibility and lower VRAM use for unrelated terrains.
- Replacing or clearing the height field also clears its associated
  colors, avoiding a stale shading response from a different world shape.
- No changes to collision, surface height, world generation or simulation.

## Game integration

`terrain_curvature.gd` builds an R/G cavity/ridge mask from a small
discrete Laplacian of the **same authoritative world height field**:

- **Red:** concave hollows/crevices = slightly darker indirect AO.
- **Green:** exposed convex tops = slightly brighter diffuse color.
- **Blue:** currently unused; reserved for other world shading masks.
- **Alpha:** unchanged 1.0, fully opaque.

Interior neighbors reuse the 33x33 height array already generated for
the terrain. Only boundary samples call the world sampler beyond the
chunk, ensuring identical colors on both sides of a seam. This CPU work
happens **once per streamed chunk**, not each render frame.

The native `ChunkedTerrain3D` vertex color reaches both the
13-layer PBR terrain shader and its optional-asset-free painted fallback.
The color is only a bounded lighting modifier, blended with existing
contact AO, cloud shadows, normal-map micro-occlusion, shoreline caustics
and fog; it does not replace them. Detail transitions fade with the
existing `aa_terrain_detail_radius` for stable far terrain.

| Graphics preset | Strength |
| --- | ---: |
| Performance | 0.00 (no cavity shading) |
| Balanced | 0.30 |
| High | 0.70 |
| Ultra | 1.00 |

Strength is a single shared GPU uniform, so switching presets does not
rebuild existing world chunks. Every preset gets correct geometry and
lighting even while moving between Quality modes.

## Performance and QA

- Extra vertex attributes cost some bandwidth and stream data memory.
  Curvature uses **zero new pixel texture samples** and does not request
  a framebuffer copy, light or postprocess pass.
- World sampler work scales with chunk edge length; interiors use already
  available vertex heights. Validate streaming CPU P95 as well as GPU
  frame time before/after in wooded valleys, a cliff ridge, swamp and city.
- Verify in both Godot Forward+ and Compatibility with optional texture
  packs present and absent. Check for visible seams, excessive dark areas,
  pop at LOD changes and night/day consistency.
- The generator is deterministic; the same seed and world coordinates
  produce identical vertex colors.

Tests:
- C++ `tests/scene/test_heightmap_terrain_geometry.cpp`: near/far LOD
  colors, skirts and optional color buffer path.
- C++ `tests/scene/test_chunked_terrain_3d.cpp`: native setter validation,
  resource lifecycle, height-data invalidation.
- Godot `game/tests/test_terrain_curvature.gd`: analytic bowl, ridge,
  flat terrain, shared chunk border, native upload and both shaders.

Build the custom engine and run tests before release. The editing environment
does not include a compiled custom Godot engine; C++ compilation, Godot
shader compilation and GPU benchmarks could not be run here.

This feature is a **curvature-derived artistic shading approximation**,
not true ray-traced ambient occlusion or a substitute for Lumen.
