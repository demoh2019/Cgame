# Native Cgame screen-space roughness filtering for imported PBR assets

Modern high-fidelity renderers (Godot 4, Unity HDRP and Unreal)
limit microfacet specular aliasing by filtering roughness in areas
with subpixel normal detail. FSR2/MSAA smooth geometry edges but
fine metal, wet rock, tiled roofs, normal maps and foliage can still
sparkle. The Godot Forward+/Mobile renderer already implements
**screen-space roughness limiting**, but Albion After was not
controlling this native option through the existing user graphics
tiers. Now it does so in addition to the world material-specific
normal variance shader AA.

Per-process quality policy:

| Preset | Forward+ | Amount | Limit |
|---|---|---:|---:|
| Performance | Off | 0.00 | 0.18 |
| Balanced | On | 0.25 | 0.18 |
| High | On | 0.33 | 0.16 |
| Ultra | On | 0.43 | 0.14 |

Mobile caps at Balanced, Compatibility disables the feature at
every tier. The game updates the engine's original
`RenderingServer.screen_space_roughness_limiter_set_active` on
preset changes, but never duplicates GPU samplers, render passes,
material nodes or imported textures. A cached renderer plan avoids
repeating global state updates during routine Auto quality checks.

The C++ fork additionally guards against non-finite and out-of-range
roughness parameters and skips unchanged renderer state. Valid input
is clamped to the same numeric domain declared in engine settings.
This makes live user/auto tuning resilient rather than silently
propagating illegal values to the RD graphics pipeline. This is a
small **actual renderer source change**, not an engine feature claim
based on a client-side shader.

Validated by `res://tests/test_graphics_native_specular_aa.gd`
in the full runner and focused graphics CI runner. Real visual
quality and GPU cost must be assessed by comparing the same scene,
sun angle and moving camera across imported assets on Metal/Vulkan.
