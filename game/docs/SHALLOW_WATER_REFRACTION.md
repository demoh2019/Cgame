# Shallow-water screen-space refraction — graphics quality pass

## Reference engines and intent

The existing water shader already provides depth-based spectral color, foam,
whitecaps, Fresnel highlights, animated analytic normals and shoreline glimmer.
However, the underwater terrain remains geometrically undistorted.

Unreal Engine's Single Layer Water combines scattering, absorption and
refraction; Unity HDRP similarly uses screen-color refraction for transparent
surfaces. We use a small, renderer-aware **screen-space** refraction feature,
not a Nanite/Lumen/Single Layer Water implementation.

- [Unreal Single Layer Water](https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine)
- [Godot screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
- [Godot screen-reading limits](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html)

## Implemented

- **Performance, Balanced, Mobile and GL Compatibility** retain
  `assets/shaders/water.gdshader` with no `hint_screen_texture` declaration.
  They never request the additional 3D opaque-screen copy for refraction.
- **High and Ultra Forward+** select the separate
  `assets/shaders/water_refractive.gdshader` at quality changes.
  `graphics_water_refraction.gd` owns the renderer/quality policy and updates
  one existing ShaderMaterial. The online water plane is not rebuilt.
- The high-end shader samples the original and slightly displaced opaque
  screen color in translucent shallow water. The difference adjusts only
  the **transmitted** contribution, conserving the existing foam, depth tint,
  water alpha, Fresnel and surface roughness. This avoids counting the
  background twice under alpha blending.
- Displacement uses the existing animated view-space water normal, so the
  appearance responds naturally to waves and storms.
- A second sampled depth checks whether the shifted pixel is actually
  underwater. This attenuates unnatural silhouettes at steep shorelines.
- Distortion fades out in deep ocean water, under opaque foam and with
  camera distance, avoiding unnecessary texture taps outside the visible
  shoal region.
- No extra meshes, vertex detail, networking or physics changes.

| Graphics mode | Shader | Strength | Full detail to | Fades out by | Max useful depth |
| --- | --- | ---: | ---: | ---: | ---: |
| Performance/Balanced | Original | 0 | — | — | — |
| High (Forward+) | Refractive | 0.025 | 28 m | 70 m | 3.5 m |
| Ultra (Forward+) | Refractive | 0.040 | 52 m | 110 m | 5.0 m |
| Any Compatibility/Mobile | Original | 0 | — | — | — |

## Rendering limitations and acceptance criteria

Godot screen textures capture the **opaque** frame, not already transparent
players, effects, water or UI, and may include opaque foreground objects.
Depth rejection reduces visible edge artifacts but is not physically exact
ray-traced refraction. The high-quality variant can still add framebuffer
copy/bandwidth cost and pixel shader work; benchmark on target GPU before
increasing its range or strength.

1. Launch the game at a sandy coast, muddy marsh and dock. Check readable
   underwater geometry, small animated displacement, foam continuity and
   undistorted foreground objects.
2. Toggle Performance, Balanced, High and Ultra while walking on the shore.
   Check water doesn't disappear and GPU memory/draw stats stay bounded.
3. Test the same scenes in Compatibility and Forward+ renderers. Compatibility
   must always use the original shader.
4. Profile frame time (P50/P95/P99), GPU transfer cost, resolution and total
   texture samples under an identical camera path and weather. Do not infer
   that a visual improvement has improved FPS.

## Test

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

`test_water_refraction.gd` checks quality policies, real material shader
switching, optical sampling masks, intact pre-existing water physics-like
shading, and avoidance of screen copy on low-end presets. Full render
profiling is still needed; the Godot executable was unavailable in this
editing environment.
