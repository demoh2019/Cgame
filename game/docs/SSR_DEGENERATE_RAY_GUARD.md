# Forward+ screen-space reflections: stable rays and no NaN mips

The Cgame Forward+ renderer uses half-resolution Hi-Z SSR with a mip chain,
roughness-based ray rejection and a sky/IBL fallback. Inspired by
AMD FidelityFX SSSR, Unreal Engine SSR and Unity HDRP reflection hierarchies,
this update corrects degenerate ray arithmetic without adding passes.

## Native shader

A reflection can project to a perfectly horizontal or vertical screen ray.
Four historical Hi-Z calculations divided by the zero-valued screen axis.
Another division normalized against a possibly zero depth displacement.
Near-plane clipping could also divide by a near-horizontal ray Z.

The GPU shader now preserves signs while bounding each screen-axis divisor
to a minimum magnitude of 1e-6. Degenerate depth or nearly zero screen
travel (and invalid NaN/Inf directions) output zero color and zero mip
rather than feeding invalid ray hits into the SSR resolver. The existing
sky/probe reflection term is the fallback. No extra textures, ray passes,
draw calls, per-frame CPU work or gameplay state changes are introduced.

## Albion After

GraphicsReflections.apply() now skips unchanged native Environment
properties on repeated profile selections, while preserving the existing
Forward+ High/Ultra SSR step and roughness budgets. Performance/Balanced
and Compatibility/Mobile still disable the reflection ray pass.

Standalone C++ numerical tests cover axis-aligned, negative, near-zero,
NaN and infinite rays. A targeted GitHub Actions workflow compiles the
reference and checks all four protected GLSL divisions. The game's
test_graphics_reflections.gd checks the real native profile transitions.

These tests do not substitute for compiling and rendering the custom
Cgame engine. Visually inspect wet stone and metal at near-grazing angles,
sky reflection fallback, roughness fades, and Metal/Vulkan before release.
