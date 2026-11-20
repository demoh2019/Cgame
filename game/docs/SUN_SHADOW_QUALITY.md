# Renderer-aware solar shadow quality and atmospheric contrast

The sun was previously initialized with `light_angular_distance = 0.6`
for **every** graphics quality level. In Godot Forward+, any positive
directional angular size enables expensive PCSS contact-hardening filtering.
This is an unnecessary cost on Performance/Balanced; Godot recommends
explicitly disabling PCSS for lower hardware targets.

Unreal Engine and Unity HDRP similarly expose directional-source angles and
shadow-filter-quality budgets. The game now makes the trade-off explicit.

## Shadow GPU budget

| Renderer / quality | PCSS angular distance |
| --- | ---: |
| Forward+ Performance | 0° — off |
| Forward+ Balanced | 0° — off |
| Forward+ High | 0.35° |
| Forward+ Ultra | 0.53° |
| Compatibility or Mobile, any profile | 0° — off |

`0.53°` is approximately the apparent angular diameter of the Sun. This
is a *quality-specific* runtime setting, not a second directional light or
an extra shadow-map draw pass. The existing cascade and shadow-map settings
remain under `GraphicsLighting` control.

## Weather-responsive shadow contrast

Clouds scatter and diffuse direct illumination. The existing atmosphere
already reduces the sun's energy when storming, but its directional shadows
stayed dark. The new pure `SunShadowQuality.opacity` function maps the
current sun height, daylight and eased storm strength to `shadow_opacity`:

- High midday sun yields clearer, deeper cast shadows.
- Golden-hour low sun casts slightly softer-contrast shadows.
- Moonlight keeps faint, readable shadows.
- Heavy cloud cover lowers shadow opacity continuously rather than leaving
  high-contrast black shapes under a grey sky.

The shadow opacity is updated **at most 5 times per second**, and only
when it changes beyond a small epsilon. The angular distance is applied
on a renderer/quality switch, never per frame. No new textures, shaders,
render passes, shadow casters or simulation changes.

## Validation

Run `godot --headless --path game --script res://tests/run_all.gd`.
The `test_sun_shadow_quality.gd` suite checks profile and renderer
selection, realistic angular size, clamping, weather transitions,
runtime reversibility and no interference with the existing cascade budget.

Compare a matching tree-lined road at midday, sunrise, storm and moonlight.
Switch Balanced/High/Ultra on Forward+, and compare normal-contact shadows,
moving foliage, pixel flicker and p50/p95 GPU frame times. Compare Mobile
and Compatibility fallback. The expected GPU saving from disabling PCSS on
lower presets must be measured; it is not a measured FPS claim.

Sources:
- https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- https://dev.epicgames.com/documentation/unreal-engine/directional-lights-in-unreal-engine
- https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.0/manual/HDRP-Asset.html
