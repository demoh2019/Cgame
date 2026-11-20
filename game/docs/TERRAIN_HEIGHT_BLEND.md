# Height-aware terrain transitions (Albion After)

This update brings a **height-based material layering** idea from Unity
HDRP/URP Terrain Lit into the Godot game renderer. It produces more legible
soil/rock, forest floor, mud/sand and snow transitions: raised stone and
snow appear to protrude above recessed terrain material instead of merely
mixing two opaque photos as semi-transparent paint.

The new `res://assets/shaders/terrain_height_blend.gdshaderinc` runs in
the existing 13-layer PBR terrain shader. It uses the **already computed**
mid-frequency noise and broad terrain noise as a low-cost proxy for layer
microheight. Distinct height priorities are authored per natural material.
It DOES NOT introduce extra material textures, heightmap samplers, passes,
geometry displacement, scene nodes, allocations or gameplay simulation.
Cliffs keep the existing near-field triplanar color and normal mapping,
and material specular/roughness remain physically based.

## Performance and scope

| Graphics profile | Height-relief blend |
| --- | --- |
| Performance | 0 — no additional GPU work |
| Balanced | 0 — identical existing ground transitions |
| High | 0.48 — modest height-aware transitions |
| Ultra | 0.85 — more defined rock/soil/snow layer boundaries |

The shader skips the new calculations on Performance/Balanced and on
distant terrain. On High/Ultra, the existing
`aa_terrain_detail_radius` also bounds the effect, with a smooth fade.

The branch also excludes road-dominated pixels and site/urban-dominated
pixels: roads, asphalt, brick and planks must retain their authored edges.
The road dirt index (4) is never altered. A normalization step conserves
the **entire natural-material weight sum**, so existing biome coverage,
weather wetness, puddles, caustics, roads and blended macro albedo remain
consistent. Each originally zero-weight layer stays zero.

The painted/procedural Compatibility fallback is deliberately not modified;
its original inexpensive graphics remain intact.

## Why this technique

Unity's current Terrain Lit Shader provides height-based blending so
material detail emerges from surface height instead of flat weight mixing:
https://docs.unity.com/en-us/engine/6000.3/manual/materials-and-shaders/built-in/shaders-in-universalrp/reference/shader-terrain-lit

Unity HDRP's Terrain Lit inspector documents both height-based blends
and specular occlusion:
https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%4017.6/manual/terrain-lit-material-inspector-reference.html

Unreal's Lumen performance guidance stresses the importance of limiting
expensive material/lighting work to what is actually visible:
https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-performance-guide-for-unreal-engine

Godot global shader uniforms let one quality switch alter all streamed
terrain materials without iterating their instances:
https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html

This is **not** a port of HDRP or Lumen; the game implements a lightweight
Godot-native material-mask adjustment with existing noise information.

## Code integration

- `assets/shaders/terrain_height_blend.gdshaderinc` — shared relief bias
- `assets/shaders/ground.gdshader` — near-field material weight correction
  before the existing sorted PBR texture-layer budget
- `scripts/client/graphics_quality.gd` — the four graphics presets, with
  the new scalar uploaded only when quality settings change
- `project.godot` — `aa_terrain_height_blend` engine shader uniform
- `tests/test_terrain_height_blend.gd` — quality, texture-read budget,
  no road modification, no negative weights and conserved biome weight
- `tests/run_graphics.gd` and `tests/run_all.gd` — both suites

## Rendering verification

```sh
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

Compare exact camera positions over forest/rock, grassy cliff, snow
transition, swamp and road edges at Balanced, High and Ultra. Verify no
landscape seam on chunk boundaries, no road/urban-edge change, and no
flicker as a chunk exits the camera's terrain detail radius.

Do not claim measured FPS benefits without real GPU median/p95 timings.
This feature has a small additional ALU cost on near High/Ultra terrain,
trading it for more visually distinct material layering; it is zero-cost
on Performance and Balanced via a uniform branch.
