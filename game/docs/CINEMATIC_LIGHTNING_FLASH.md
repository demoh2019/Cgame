# Cinematic weather lightning: zero new light draw passes

Real lightning impacts already exist in the authoritative simulation
(`lightning_struck`). This addition makes those impacts briefly illuminate
the **actual game world** instead of only showing the earlier purple ground
warning. The existing server damage, counterplay, 2.8-second telegraph,
world seed, storm rules and networking remain unchanged.

## Scene effect

The two-stage light pulse raises and cools the existing:
- directional sun/moon illumination;
- Environment ambient light energy and tint;
- weather-fog scattering color.

There is a very short initial bright white-blue pulse, followed by a
weaker secondary return stroke and a quick fade. The pulse lasts no more
than **0.46 seconds** and is entirely analytic: it uses the elapsed time
since the actual strike event, not animation frame counts.

**Only an authoritative strike starts a flash**, never a pending hazard
warning or unrelated storm rain. Both online and offline game clients
subscribe to their existing `lightning_struck` event. Strike distance
reduces the light contribution quadratically; beyond 180 m it is zero.
Underground viewpoints do not receive sky flashes.

The intensity is limited by current quality settings using the same
quality level passed to the game's Atmosphere:

| Graphics profile | Peak lighting budget |
| --- | ---: |
| Performance | 0.26 |
| Balanced | 0.43 |
| High | 0.66 |
| Ultra | 0.88 |

## GPU costs and safety

No extra OmniLight3D or DirectionalLight3D is created: existing sunlight
and ambient/fog are lifted only while the flash is nonzero. The scene's
current shadow-enabled state remains unchanged. No extra shadow map,
reflective cubemap, PBR material, lightning particle, post-processing
pass, shader variant, network packet or world simulation work is added.

The atmosphere always computes its original day/night/fog lighting first
and adds the brief visual enhancement afterward. The original lighting
is recomputed on the next update, so a strike cannot leave the world
permanently washed out.

## Why this design

Godot's DirectionalLight3D already illuminates distant surfaces and
Environment already controls ambient and fog:

- https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html
- https://docs.godotengine.org/en/stable/classes/class_environment.html

Unreal Engine's environment-lighting art pass uses non-shadow-casting
lights and storm lightning masks for similar mood changes:

- https://dev.epicgames.com/documentation/en-us/unreal-engine/07-adjust-environment-lighting-features

Unity encourages quality-dependent real-time lighting work:

- https://unity.com/how-to/performance-optimization-high-end-graphics

Those are architectural references; this implementation uses native
Godot rendering APIs and the game's actual server-generated weather.

## Testing

`tests/test_graphics_lightning_flash.gd` verifies the real lighting
properties on Godot objects, both-stage timing, far-distance cutoff,
invalid network data, graphics profile monotonicity, outdoor-only
behavior and exact integration into both online and offline clients.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

GPU QA: trigger a real strike at night outside a dungeon in a storm,
then repeat at midday and from a sheltered dungeon. Compare the original
scene at the same point to confirm night visibility and no permanent
lighting changes. Profile average and 95th-percentile GPU frame time
and shadow-map count before claiming numerical speedups.
