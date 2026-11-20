# High-quality spectral foliage transmission

Albion After now approximates wavelength-dependent light passing through
thin tree leaves, bushes, and meadow grass. This is inspired by Unreal
Engine's Two-Sided Foliage shading model and Unity HDRP's thin-material
Transmission. Godot's existing native spatial `BACKLIGHT` is deliberately
retained, so the effect receives actual directional/point lighting rather
than glowing unconditionally.

## Integrated into the playable world

- `scripts/client/foliage.gd`: sampled leaf albedo provides a vein/thickness
  mask. The high crown and thin bright leaves filter more sunlight than
  darker thick lower leaves. Cut-out leaves only: trunks/bark stay unchanged.
- `scripts/client/grass_field.gd`: grass tips have thinner pigments than
  opaque roots; the existing distance fade skips unseen grass.
- `assets/shaders/foliage_spectral_optics.gdshaderinc`: one shader function
  shared by both systems approximates Beer-Lambert absorption with a fast
  rational function. Green chlorophyll-rich foliage transmits more green
  light; dry grass shifts its spectral profile toward warm tones.
- `graphics_profiles.gd` and `graphics_quality.gd` expose one
  world-wide GPU uniform. Profile switches update all streamed materials
  and both offline and online worlds without rebuilding MultiMesh batches.
- `project.godot` registers the shader uniform for the custom Godot fork.

| Quality | Spectral pigment model | Legacy backlight |
| --- | --- | --- |
| Performance | Off (0.0) | Off |
| Balanced | Off (0.0) | On |
| High | 0.60 | On |
| Ultra | 1.00 | On |

No new texture, framebuffer pass, volumetric lighting, or geometry is
introduced. This does **not** implement Unreal's full two-sided shading
or Unity's screen-space SSS diffusion profiles. The shared shader runs
only on lit vegetation in premium settings. The default render pipeline
still uses alpha scissor rather than alpha blending, preserving cheap
vegetation batching and current cloud shadows/wet-surface PBR.

Native Godot `BACKLIGHT` already provides the required engine lighting
integration; changing the engine's C++ lighting shaders would duplicate
that feature. The engine-side integration is the new registered global,
used by all existing material variants.

References:
- https://dev.epicgames.com/documentation/unreal-engine/shading-models-in-unreal-engine
- https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.0/manual/skin-and-diffusive-surfaces-subsurface-scattering.html
- https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html

Tests: `test_foliage_spectral_optics.gd` runs through the full and
graphics-only suites. On a device, test sunset backlit forest, rainy
meadow, and bright midday grass on Metal Forward+ and Compatibility;
compare p50/p95 GPU time and foliage color without claiming an
unmeasured frame-rate benefit.
