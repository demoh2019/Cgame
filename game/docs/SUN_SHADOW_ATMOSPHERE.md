# Atmosphere-aware sun and moon shadows

High/Ultra rendering now softens the native Godot directional-light
penumbra in cloudy weather and when the sun is low. Direct clear
midday shadows stay crisp and full-opacity; cloudy sunshine gains a
wider soft edge with less harsh contrast; dusk and moonlight remain
readable. The effect uses the existing `shadow_blur` and
`shadow_opacity` on the single `DirectionalLight3D` in the shared
online/solo `Atmosphere` node.

No extra lights, transparent decals, textures, render targets or
shadow passes. Shadow properties update at most 4 Hz, rounded to
hundredths to avoid redundant driver parameter updates. Performance
and Balanced preserve their old fixed shadow settings. High/Ultra
only change parameters of their existing Godot native shadow filters;
cascade counts, distances and shadow-caster budgets stay unchanged.

Influenced by Unreal's soft shadow design and Unity HDRP's light/filter
budgets, but entirely implemented with supported Godot 4 Light3D
properties, not ported proprietary virtual shadow maps.

Tests: `game/tests/test_sun_shadow_atmosphere.gd`, included in
`game/tests/run_all.gd`. Visual and P95 GPU profiling pending.
