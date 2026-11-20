# Cinematic far-focus depth of field (engine + Albion After)

## References and motivation

Unreal's Cinematic Depth of Field and Unity HDRP's Depth of Field separate
near subject matter from far-away backgrounds using focal planes and
bokeh. Godot Forward+ already has a native depth-aware DOF renderer via
`CameraAttributesPractical`, but Albion After previously disabled the
effect unconditionally in its exposure pipeline. This patch activates a
subtle premium treatment **without any custom full-screen camera blur shader**.

- Unreal: https://dev.epicgames.com/documentation/en-us/unreal-engine/cinematic-depth-of-field-in-unreal-engine
- Unity HDRP: https://github.com/Unity-Technologies/Graphics/blob/master/Packages/com.unity.render-pipelines.high-definition/Documentation~/Post-Processing-Depth-of-Field.md
- Godot: https://docs.godotengine.org/en/stable/classes/class_cameraattributespractical.html

## Engine improvement

The custom Godot fork now exposes
`CameraAttributesPractical.configure_cinematic_dof(enabled, far_distance, far_transition, amount)`.

Unlike calling three or four individual DOF setters (each dispatching a
RenderingServer update), the native method:

1. Validates finite inputs, clamps positive distances/transitions and bounds
   blur to `0..1`.
2. Sets all far DOF properties and disables near DOF in **one backend update**.
3. Skips unchanged profiles to avoid redundant render-thread work.
4. Preserves the exact same resource, `auto_exposure_enabled`, ISO limits,
   and all other camera exposure settings.
5. Leaves old Godot scripting APIs, serialized scenes and default
   `dof_blur_far_enabled = false` untouched.

The script falls back to ordinary setters on unmodified stock Godot, so
the graphical feature remains testable without the custom native API.

## Game integration and visual intent

`GraphicsCinematicDof` uses the existing
`Atmosphere.world_environment.camera_attributes`, initialized first
by `GraphicsEyeAdaptation`. Quality switches reapply DOF immediately.
The online isometric camera periodically refreshes the *distance from
camera to survivor*, including camera zoom and photo-mode orbit, to keep
the survivor and nearby interactive ground sharp.

The native DOF far threshold is roughly:

`max(camera_to_survivor + margin, minimum_distance)`

| Profile | Enabled | Safety margin | Minimum far distance | Transition | Blur |
| --- | --- | ---: | ---: | ---: | ---: |
| Performance | no | — | — | — | 0 |
| Balanced | no | — | — | — | 0 |
| High Forward+ | yes | 34 m | 52 m | 42 m | 0.08 |
| Ultra Forward+ | yes | 25 m | 44 m | 34 m | 0.14 |
| High photo mode | yes | 27 m | 43 m | 31 m | 0.11 |
| Ultra photo mode | yes | 20 m | 36 m | 25 m | 0.18 |

Compatibility and Mobile are disabled deliberately, despite DOF
technically being available on some Mobile renderers, to protect the
frame budget. DOF always affects **far background only**; near DOF stays
off. UI overlays in CanvasLayers are not blurred by the 3D depth pass.

Focus is sampled no faster than every 350 ms. The plan is quality-gated
and the controller ignores changes smaller than about 1.2 m, avoiding
camera-smoothing render-thread uploads. There is no new game texture,
compute workload, camera post FX shader or scene traversal.

**Cost caveat:** Native DOF *does* incur a GPU depth-of-field
postprocessing cost when enabled. This is why only the two premium
Forward+ presets use it. Do not interpret "no custom pass" as
"zero GPU cost". The amount is deliberately small to protect detail
and reduce artifacts.

## Testing and art validation

Engine C++ tests are part of
`[SceneTree][Camera3D] Atomic cinematic far DOF preserves exposure`.

Run game tests:
`godot --headless --path game --script res://tests/run_all.gd`

`test_graphics_cinematic_dof.gd` checks all renderer gates, quality
bounds, zoom/photo focus, native resource reuse, exposure isolation,
renderer fallback and integration with the real online camera.

Compare sharpness near player and enemies, mid-field foliage and distant
mountain silhouettes in daytime, dusk, rain, dungeons and photo mode.
Check transitions while scrolling zoom, sprinting and riding. On M1
Forward+ record native GPU p50/p95 with High/Ultra DOF on/off and
with FSR2/dynamic scaling. Confirm Compatibility has no DOF blur.
If performance or readability suffer, lower the blur amount or raise
the far threshold rather than stacking a separate post blur.

No game engine build, hardware screenshots or actual FPS measurements
were available during authoring.
