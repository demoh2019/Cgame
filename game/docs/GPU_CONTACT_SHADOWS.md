# GPU-instanced contact shadows for characters and infected

This feature is installed into the **real** `game/` runtime on branch
`develop`. It uses a single, camera-local `MultiMeshInstance3D` for
grounding shadows rather than creating one shadow scene node per actor.
This is an inexpensive artistic approximation of soft contact occlusion,
**not** a ray-traced/contact-hardening shadow-map implementation.

## Visual result

- **Performance** retains grounded silhouettes even with expensive
  directional shadow maps disabled.
- **Balanced** adds a subtle penumbra under the player's boots, other
  survivors, infected and town NPCs.
- **High/Ultra** retain softer, fainter contact cues beneath existing
  real-time sun shadows and filmic environmental lighting.
- Distance and atmosphere are respected: the contact fades smoothly at
  the edge of its range, is dimmer under moonlight and heavy rain, and
  is suppressed on dead or swimming actors. Distant/hidden actors
  consume no instances.
- The same system also draws beneath the local/solo survival preview
  (which uses simple colored character meshes).

## Integration

`assets/shaders/contact_shadow.gdshader` is a one-sample-free,
texture-free analytical elliptical falloff. The spatial shader is
unshaded, does not write to the depth buffer and cannot cast shadow
maps. A `PlaneMesh` and a persistent `MultiMesh` are allocated
**once** when `contact_shadow_batch.gd` enters the world.

`CharacterModel.setup()` registers live character models in a
render-only group. This automatically includes the local player,
other players, enemies and streamed settlement NPCs, without changing
gameplay collision, AI, networking or camera controls.

The batch controller:
1. Scans actors at **12.5 Hz**, not every render frame.
2. Filters dead, submerged, invisible and faraway actors.
3. Sorts remaining actors by horizontal camera distance to keep nearby
   silhouettes when the scene is crowded.
4. Writes up to the per-preset maximum instance transforms and opacity
   into one fixed GPU buffer, then sets `visible_instance_count`.
5. Keeps a camera-relative bounding box for correct MultiMesh frustum
   culling. Individual MultiMesh members cannot be hardware-culling
   targets, which is why a CPU distance cap is necessary.
6. Reuses one shader material, so there is no repeated texture
   allocation and no individual per-character draw calls.

| Graphics profile | Maximum radius | Maximum visible shadows | Maximum opacity |
| --- | ---: | ---: | ---: |
| Performance | 28 m | 48 | 0.45 |
| Balanced | 40 m | 80 | 0.32 |
| High | 52 m | 128 | 0.23 |
| Ultra | 70 m | 192 | 0.16 |

All maxima are ceilings rather than required instance counts. The
shader's elliptical falloff further reduces the effective on-screen
opacity toward the shadow's border.

## Where to inspect

- `scripts/client/contact_shadow_batch.gd`: budget,
  actor selection, weather attenuation, dynamic instance buffer
- `assets/shaders/contact_shadow.gdshader`: analytical penumbra
- `scripts/client/character_model.gd`: registration of live actors
- `scripts/client/online_main.gd`: online world integration
- `scripts/client/client_main.gd`: solo preview integration
- `tests/test_contact_shadow_batch.gd`: quality budgets,
  distance/water/death culling, alpha fade, GPU resource creation,
  and both scene integrations

## Validation

```bash
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

On actual graphics hardware compare **the same crowded town, forest
battle and flooded shoreline** with matched camera/daylight/quality.
Verify no floating NPC feet, no over-darkening under existing
directional sun shadows, no shadow projected onto water, and no
accidental disappearance at the 28/40/52/70 metre fade boundary.
Use the already integrated p50/p95/p99 CPU frame capture plus a
GPU profiler for definitive cost, and compare draw calls and overdraw.

This work is inspired by batching/instance techniques also used by
Unity HDRP/URP and Unreal's foliage pipelines. It specifically uses
Godot MultiMesh because, unlike the heavier techniques from those
engines, it also runs on Compatibility and low-power devices.

Reference: https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html

No specific FPS gain is asserted without a real GPU benchmark.
