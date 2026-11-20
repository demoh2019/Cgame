# Weather-synchronised cloud shadows and sky panorama

This feature replaces the old, fixed cloud-shadow drift vector with motion
derived from the **actual regional weather wind** already delivered to both
the online and local game clients. It improves the relationship between
swaying trees, wind-blown meadows, sky clouds and the patches of light moving
over the landscape.

## What the player sees

As wind changes speed and direction, the shadow field on trees, grass,
cliffs and roads gradually follows. Its phase is integrated over time
rather than computed from current wind times world clock. A change from
east wind to north wind therefore causes a smooth change in travel
direction, **not a sudden jump** in the lighting pattern.

The daytime panoramic cloud layer also moves according to the same
accumulated wind. Its offset is sampled only at the atmosphere's already
bounded sky-radiance refresh cadence, preserving the existing cached-sky
performance design. The sun/moon disc, night stars, dawn tone mapping
and storm colors are unchanged.

The simulation is **visual only**. No gameplay weather, networking or
authoritative world system is changed.

## Performance

- One existing **128 x 128 R8 cloud shadow LUT** is built once and cached;
  it is not regenerated when the wind changes
- One texture sample per shaded terrain/grass/leaf pixel is retained
- The same tiny GPU-global `aa_cloud_shadow_offset` (vec2) updates together
  with the existing vegetation wind global, **at most 10 times a second**
- The GPU-side cloud sample remains disabled on Performance and at night
  when the cloud strength is zero
- The cloud position wraps every **1024 metres**. Repeating texture UVs
  remain continuous, and floating-point precision cannot degrade over
  long sessions
- Total cloud speed is capped at **7.5 m/s** for full regional wind;
  large frame stalls are clamped to a maximum 0.25 s cloud motion step
- The sky's daytime panorama uses its existing texture fetch and cached
  radiance pipeline, with no new sky pass or additional sampling

`CloudShadowLut.advance_offset(previous, wind, delta)` is a pure,
deterministic integration function. The wind vector has packed
`(direction_x, direction_z, normalized_speed)` channels, shared with
existing `VegetationWind.smooth`.

## External rendering guidance

- Unreal Engine describes the use of a cached **cloud shadow map**
  rather than repeatedly tracing volumetric clouds for every surface:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine
- Unreal's cloud materials expose wind velocity controls for animated
  cloud fields:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-material-in-unreal-engine
- Godot's GPU global uniforms efficiently update multiple shaders with
  one setter, while reading them back from the render thread is costly:
  https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html

This implementation adopts those **budgeting principles** with Godot's
native global uniforms. It is not a port of proprietary cloud rendering.

## Integration and tests

- `scripts/client/cloud_shadow_lut.gd`: wrapped wind integrator and
  shader-equivalent world UV helper
- `assets/shaders/cloud_shadow.gdshaderinc`: one world-aligned GPU offset
- `scripts/client/atmosphere.gd`: smoothing, 10 Hz upload, sky synchronization
- `assets/shaders/sky.gdshader`: cloud-panorama rotation at radiance cadence
- `project.godot`: shader uniform registration
- `tests/test_weather_cloud_advection.gd`: speed bounds, sudden gusts,
  invalid data, seams, GPU sampling budget, renderer integration

With a Godot installation:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

In a GPU build, compare calm, light east wind and strong north wind on the
same forest road in daytime. Watch leaves, grass, cloud shadows and the
panorama for abrupt phase jumps, check chunk edges while moving, and
measure median and p95 frame time before claiming performance gains.
