# Seamless roughness-aware SSR to sky/probe reflections

## Problem
The original Cgame Godot Forward+ SSR trace abruptly returned empty
reflections above roughness 0.7. On dynamically wet PBR stone and
weathered metal this appeared as a popping highlight boundary,
especially during camera movement and mip transitions.

## Engine changes
`servers/rendering/renderer_rd/shaders/effects/screen_space_reflection.glsl`
now fades ray confidence smoothly across roughness 0.52–0.70 before
handing control back to the existing sky IBL / reflection-probe
fallback. At roughness >=0.70 the existing cheap early exit remains,
so no extra ray traces are launched on matte surfaces.

The same shader rejects out-of-screen Hi-Z hits and impossible
previous-frame UV reprojections. Near the screen perimeter it avoids
reading invalid geometric normal neighbors. These guards stop
undefined out-of-bounds texelFetch behavior on Vulkan/Metal without
introducing additional textures, render passes or GPU resources.
Ray step limits, Hi-Z hierarchy and conservative half-resolution SSR
are retained.

## Game controls
`graphics_reflections.gd` selects native roughness reconstruction:
Performance/Balanced/Compatibility/Mobile OFF; High MEDIUM;
Ultra HIGH. The global native filter state is only resent on
actual quality changes, including auto-quality fallback. High uses
28 ray steps, Ultra 48, and both retain sky reflection fallback.
Water uses its separate physical refraction/shallow scattering.

The smooth confidence blend follows the roughness-driven reflection
hierarchy used in Unreal SSR/Lumen fallback and Unity HDRP SSR
smoothness fade, rather than claiming those engines' proprietary
ray tracing. Godot supports hybrid SSR with sky/probe fallback.

Tests: `game/tests/test_graphics_reflections.gd` (full and
focused graphics suites) checks native quality, renderer fallback and
per-tier GPU budget. Full shader compilation and side-by-side
captures on Apple Metal and Vulkan are still required to confirm
the intended visual improvement.
