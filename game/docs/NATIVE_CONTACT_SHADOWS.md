# Quality-scaled screen-space contact shadows — Albion After

## Visual motivation

Unreal's contact shadows and Unity HDRP's depth-raymarch contact shadows
add the small grounding details ordinary shadow-map cascades often miss:
feet meeting the ground, leaves and stones near a tree base, small ruins,
grass clusters and fencing. In Godot's **Forward+** backend the native
directional-contact implementation already exists in the engine, but it
must be enabled globally and permitted per directional light.

This update uses the existing renderer rather than inventing a duplicate
shader or adding another source of light. It is **not** Unreal Virtual
Shadow Maps, GPU ray tracing, or a substitute for real geometry shadows.

References:
- Godot lights and directional contact shadows:
  https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- Unreal contact shadows:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/contact-shadows-in-unreal-engine
- Unity HDRP contact shadows:
  https://github.com/Unity-Technologies/Graphics/blob/master/Packages/com.unity.render-pipelines.high-definition/Documentation~/Override-Contact-Shadows.md

## Game changes

- The project sets
  `rendering/lights_and_shadows/contact_shadow/enabled=true`.
  **This alone is not enough to render an effect:** the active sun
  `DirectionalLight3D` is explicitly initialized with
  `shadow_contact_shadows_allow=false` on startup.
- `graphics_contact_shadows.gd` opts in only for High/Ultra Forward+.
  `graphics_quality.gd` applies the per-light choice at preset
  changes, not every frame. Compatible hardware gets an extra
  screen-space contact layer; other backends retain existing PSSM.
- High uses blur **0.65**, Ultra **0.95** to gently soften thin foliage
  without erasing nearby rock/object contacts.
- The existing solar PCSS, directional cascades, shadow biases, moonlight,
  weather shadow opacity and shadow draw budget remain unchanged.

| Preset | Renderer | Contact shadows | Additional cost |
| --- | --- | --- | --- |
| Performance | Any | Off | No SSCS prepass/compute |
| Balanced | Any | Off | No SSCS prepass/compute |
| High | Forward+ | On, blur 0.65 | Extra depth/ray pass |
| Ultra | Forward+ | On, blur 0.95 | Extra depth/ray pass |
| Any | Mobile or GL Compatibility | Off | No SSCS pass |

## Native engine optimization

`servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp`
now checks visible directional shadow passes for a contact-shadow-enabled
light **before** forcing a depth prepass. The old global project flag
forced depth work even if every light opted out.

The renderer also:
- Skips the SSCS buffer allocation/dispatch when the eligible-light
  list turns out to be empty.
- Marks the SSCS shader flag only if a contact-shadow pass was
  collected for the scene. This avoids referencing a stale contact
  texture after toggling quality.
- Reuses existing light and shadow data without extra traversal of
  geometry, shadow maps or render passes on low settings.

The light scan is O(number of shadowed lights), rather than O(pixels),
and short-circuits at the first eligible directional light.

## Visual and performance validation

`game/tests/test_contact_shadow_quality.gd` checks the actual
`DirectionalLight3D` parameters, all quality/backend combinations,
low-cost startup and quality-system integration. It is registered in
`game/tests/run_all.gd`.

Compile the modified Godot C++ engine before running the game; testing
the unmodified stock build will not exercise the native early-out.

```bash
# Using your already-built custom engine binary:
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

For a useful A/B comparison, use identical camera paths at tree bases,
stone clusters, a ruined street and character feet. Compare the scene
at High with `sun.shadow_contact_shadows_allow` off/on. Look for
halo/noise artifacts, soft penumbrae in foliage, shadow double counting
over SSAO, character movement and wet rocks. Validate Ultra, High,
Balanced, Performance and the Compatibility fallback in succession.

Measure GPU P50/P95 frame time, forced depth-prepass draw calls,
screen-space effect passes and memory. This effect is **not free** on
High/Ultra: its purpose is visibly better contact detail on capable
hardware. No FPS gain is claimed without profiling the custom engine.

**Limitation:** Contact shadows use only scene depth and cannot cast
shadows from invisible/offscreen objects. When a depth silhouette is
missing the ordinary shadow map and contact AO remain the fallback.
C++ compilation and GPU benchmarks were not available in this editing
environment.
