# Sky shader: cached radiance fast path and point stars

Godot can sample its built-in RADIANCE cubemap directly in the sky background
pass (documented in the Godot Sky shaders guide). The game already updates
radiance at a bounded cadence; this change reuses that work.

- **Performance and Balanced**: visible sky samples the cached cubemap,
  rather than computing the full panorama, twilight grade, hash stars and
  sun glow for every background pixel on every render frame. Cubemap generation
  still renders the original sky normally, with no recursive sample.
- **High and Ultra**: sky uses full-resolution panorama and sharper circular
  stars based on spherical UV cells, with derivative-based anti-aliasing and
  warm/cool star colors. Star lookup and twinkle are skipped during daytime,
  low sky angles and nearly opaque storms.
- **All tiers**: dark nights skip the otherwise invisible daytime panorama
  and its atan/acos UV calculations.
- The source retains the existing time-driven twilight, sun/moon direction,
  moving panorama, environment reflections and sky refresh cadence.
  No new render passes, render targets, textures, shaders or server changes.

Tradeoff: on Performance/Balanced the radiance cube's lower resolution can
soften the smallest sky details, deliberately in exchange for cheaper frames.
This is distinct from Unreal's physically based Sky Atmosphere LUT and
Unity HDRP's precomputed scattering, but follows the same idea of
*reusing cached atmospheric lighting* rather than recomputing it per pixel.

Test with: `godot --headless --path game --script res://tests/run_all.gd`
Validate final appearance in day/night, sunrise/storm and mobile/desktop
renderers. Actual FPS changes must be measured on physical hardware.
