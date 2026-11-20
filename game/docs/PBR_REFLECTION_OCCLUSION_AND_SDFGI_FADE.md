# PBR specular visibility and continuous SDFGI reflections

Albion After / Cgame `develop`. This upgrade repairs the native Forward+
renderer's outer SDFGI cascade reflection transition and improves the existing
PBR indirect-specular occlusion for textured terrain, vegetation, architecture
and imported metallic/roughness materials.

## Comparison / motivation

- **Unreal Engine / Lumen**: indirect specular is evaluated separately from
  diffuse GI, with quality-dependent scene representations and sky fallback.
- **Unity HDRP**: smooth reflection fallback combines screen-space hits,
  reflection probes and sky; indirect specular occlusion can use bent normals.
- **Google Filament / Frostbite**: Lagarde's empirically tuned
  roughness/view/visibility approximation avoids reflective leaks in crevices
  when bent normals are unavailable.

This is a carefully scoped improvement to Godot Forward+; it does **not**
implement the full Lumen, HDRP or Filament renderer.

## Native engine fix: outer SDFGI cascade

In `servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl`,
the outer cascade's original code wrote
`indirect_specular_light = mix(specular, indirect_specular_light, blend)`,
then immediately overwrote that result with
`indirect_specular_light = specular`. The sky/reflection fallback never
actually reached the final pixel. It now writes the blend into the **local**
`specular` variable, exactly like the diffuse GI fade, before the final
assignment.

No new texels, GPU passes or ray steps are required. This affects actual
Ultra SDFGI lighting on streaming terrain and regular PBR geometry.

## Native engine fix: roughness-aware specular occlusion

The previous fallback used ambient RGB luminance and a fixed metallic
multiplier. The new fallback applies the Lagarde approximation to **indirect**
reflection lighting using the existing material AO × screen-space AO:

```glsl
float NoV = clamp(dot(normal, view), 0.0, 1.0);
float visibility = clamp(ao, 0.0, 1.0);
float specular_occlusion = clamp(
    pow(max(NoV + visibility, 0.0001),
        exp2(-16.0 * clamp(roughness, 0.0, 1.0) - 1.0))
        - 1.0 + visibility, 0.0, 1.0);
indirect_specular_light *= specular_occlusion;
```

- Occlusion 1.0: untouched indirect reflections and no `pow()` branch.
- Occlusion near 0.0: dark crevices no longer emit bright sky reflections.
- Grazing views occlude reflection directions more than head-on views.
- Existing direct highlights, skylight diffuse bounce and reflection probes
  remain managed by the existing render pipeline.
- The existing bent-normal path remains unchanged.
- The math is an **empirical visual approximation**, not ray-traced visibility.

The native renderer also applies a **rough-material fast path**: when
`roughness >= 0.55`, the Lagarde exponent is below 0.0012, so indirect
specular visibility is approximated by the existing AO value without invoking
`pow()` or `exp2()`. A 30,000-sample numerical sweep gave maximum absolute
deviation **0.00573** at the threshold. Glossy metal and wet puddles keep the
full roughness/view-dependent model; unoccluded surfaces skip it entirely.

This adds no textures, render targets, additional AO passes or per-material
ShaderMaterial instances. Exact GPU cost should be measured on Apple M1,
especially dense foliage and ruins.

## Game integration: wet-stone cavity visibility

`game/assets/shaders/ground.gdshader` already combines baked ground contact,
micro-cavity normal-map shadows and heightfield curvature through the real
spatial-shader `AO` channel. A rain-filled micro-cavity now progressively
returns to its unoccluded reflection visibility rather than retaining dry
stone's strong curvature occlusion:

```glsl
float cavity_visibility = 1.0 - cavity * 0.24 * (1.0 - puddle * 0.85);
AO = clamp(ground_contact * micro_shadow * cavity_visibility * sky_visibility, 0.0, 1.0);
```

The existing horizon AO can supply `sky_visibility` through native terrain
vertex colors on High/Ultra, further blocking bright reflected sky beneath
overhangs without a texture. Performance/Balanced preserve visibility 1.0.
Foliage still supplies imported ORM ambient occlusion and bounded canopy AO.
High activates cheap SSAO and short SSR; Ultra additionally enables SDFGI
and the repaired sky reflection transition. Performance and Balanced do not
allocate SSAO/SSR/SDFGI buffers. Native specular occlusion is always fed by
the same PBR AO channel; no additional game shading pass is required.

## Regression and visual verification

Python native shader/source/math tests:
`python3 -m unittest tests/servers/rendering/test_pbr_reflection_occlusion.py -v`.
Game test suite: `game/tests/test_pbr_reflection_occlusion.gd` registered in
`game/tests/run_graphics.gd` and `game/tests/run_all.gd`.
The `albion-after-graphics.yml` GitHub workflow also includes the native
shader and regression source in its sparse checkout.

For real-world validation, rebuild the patched Cgame editor and record
identical-camera dry/wet images with High versus Ultra at a SDFGI cascade
boundary. Compare the brightness of wet paving, dark concrete crevices,
metal under arches and indoor surfaces. Check SSAO/SSR/SDFGI GPU timings,
GPU memory, metallic highlight loss, and any temporal seams on Apple M1.
Source-level and numerical tests do **not** prove Metal shader compilation,
correct GPU output or a particular FPS gain.

References:
- Unreal Lumen: https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine
- Unity HDRP reflection hierarchy: https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%4012.0/manual/Reflection-in-HDRP.html
- Unity HDRP specular occlusion: https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%4016.0/manual/HDRP-Features.html
- Google Filament: https://google.github.io/filament/Filament.html#lighting/occlusion/specularocclusion
