# Cinematic shallow-water refraction: High/Ultra Forward+

The existing shallow-water shader now has two **cached compile-time variants**
from the **same source**, with an actual scene-color screen sampler only on
High/Ultra with the Forward+ backend. Performance, Balanced and GL
Compatibility/Mobile skip the entire scene capture path and retain the
previous wave normals, spectral absorption, Fresnel, foam and glimmer.

On high end, slight animated wave slopes distort shallow submerged scenery.
A second depth sample checks that the refracted pixel is genuinely behind
the water; abrupt shoreline depth changes and foreground geometry fade out
the effect. Screen edges and camera distances also receive smooth fades.
Water retains its original material lighting, weather-driven ripples and
storm whitecaps. The renderer computes the **difference** between refracted
and straight opaque pixels. That already-lit delta is applied through emission
with inverse alpha compensation, which only changes background transmission
instead of adding an entire second copy of the scene. The authored water
opacity, foam lighting, Fresnel and shoreline palette are unchanged.

### Cost containment
- Extra screen-color and depth reads occur only for **shallow water up to
  3.8 m** close to the camera; distant ocean uses the old path.
- The transmission-corrected High/Ultra shader reads two scene-color pixels
  (straight and refracted) in those pixels instead of one, but removes the
  previous artificial scene brightening and alpha changes.
- High uses a 0.52 maximum mix and a 25–74m distance fade; Ultra 0.86
  and 42–110m. Low presets request **no screen texture** at all.
- Both variants are cached, selected by the existing graphics controller,
  and shared across the single world-ocean mesh; no new geometry, textures,
  server data or character state.
- The high-end scene-color copy can still incur GPU cost, which must be
  measured on a real video card. No frame rate gain is claimed here.

### Industry techniques
Unity HDRP's thin refraction/absorption model and edge fading are adapted to
Godot's native screen-reading shader interface. Unreal similarly combines
screen-space rendering with cheaper fallbacks instead of requiring high-cost
rays for every pixel. This is not a port of Unity HDRP or Unreal Lumen.

References:
https://docs.godotengine.org/en/4.5/tutorials/shaders/screen-reading_shaders.html
https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%4015.0/manual/Refraction-in-HDRP.html
https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-performance-guide-for-unreal-engine

Test:
`godot --headless --path game --script res://tests/run_all.gd`.
New `test_water_refraction.gd` suite verifies quality, shader source, cached
variants and renderer fallback. GPU screenshots/tests are still required.

### Visual acceptance

At the same time of day, compare beaches, docks and submerged rocks with
refraction on/off. Look for natural distorted underwater silhouettes **without**
extra glow or unexpected changes in water opacity. Test against dark rocks and
white painted surfaces, where double-counted scene light is easiest to see.
Measure p50/p95 GPU frame time and texture bandwidth on High/Ultra Forward+:
the physically better transmission adds one extra color fetch in the already
bounded shallow-water branch. Performance/Balanced shader and cost do not change.
