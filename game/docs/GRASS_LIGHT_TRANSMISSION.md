# Backlit grass tips — physically-inspired, inexpensive vegetation lighting

The game already uses a lightweight spatial grass shader with a single MultiMesh
per tile, 3 geometry LOD tiers, GPU sway, wetness, and shared cloud shading. Its
blades previously shared a uniform upward-facing normal. This produced a relatively
flat meadow at golden hour even with detailed trees and terrain.

Modern engines offer thin-foliage transmission: Unreal's **Two-Sided Foliage** shader
and Unity HDRP's transmission for thin surfaces. The analogous low-cost native
Godot control is `BACKLIGHT`, which adds light from the reverse direction without
allocating an SSS screen-space blur.

## Implementation

- Reuses each grass blade's already-computed color, tip height, weather wetness
  and camera-distance fade to simulate thin green leaf tissue.
- Tips respond more strongly than roots, preserving ground contact and avoiding
  glowing, uniformly saturated tufts.
- Uses the existing `diffuse_lambert_wrap` material and native Godot direct-light
  backlighting, not a fake constant `EMISSION`. Moonlight and other scene lights
  continue to control the visible result.
- All of this uses **zero additional textures, draw passes, meshes or procedural noise**.
  Only a small set of fragment arithmetic operations is added for visible grass.
- Existing wind, geometry LOD, clouds, rain darkening, alpha-free mesh shading and
  streaming remain unchanged.
- The same global shader uniform is updated when a quality preset changes, so
  already-streamed grass tiles adapt immediately without material duplication.

| Profile | Grass transmission intensity |
| --- | ---: |
| Performance | 0.00, disabled |
| Balanced | 0.10 |
| High | 0.22 |
| Ultra | 0.36 |

The Low tier takes an explicit disabled path; fading-out grass is also excluded.
This is **not** an implementation of a full subsurface-scattering renderer.
For thin grass and a high camera angle, the cheaper direct backlight term is a
more suitable tradeoff.

## Validation

Headless suite: `godot --headless --path game --script res://tests/run_all.gd`.
The added regression test checks all four fidelity budgets, direct-light
transmission, camera fade, rain/cloud compatibility and global registration.

Visual acceptance: capture matched meadow scenes at mid-day, golden hour,
moonlight and during storms on both Forward+ and Compatibility. Ensure blades
light gently without looking fluorescent and root shadows remain readable.
Measure GPU p50/p95 frame time in high-density grass at 720p and 1080p.
No FPS improvement is claimed before actual hardware measurement.

References:
- https://dev.epicgames.com/documentation/unreal-engine/shading-models-in-unreal-engine
- https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html
- https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
