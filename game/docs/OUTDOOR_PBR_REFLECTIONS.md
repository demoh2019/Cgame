# Outdoor parallax-corrected reflections — Albion After / custom Godot

## Why this changes the visible image

Screen-space reflections (SSR) only capture what is already visible on the
screen. Sky cubemaps do provide a fallback but can be inaccurate close to
wet city paving, metal barrels, rooftops, gates and stone architecture.

Following the **reflection capture** approach found in Unreal Engine,
Unity HDRP and Godot, the game now uses a few **nearby, one-shot,
parallax-corrected ReflectionProbes** for towns and architecture. This is
not Lumen or hardware ray tracing. It complements the existing sky IBL,
SSR and indoor dungeon probes.

References:
- Godot local probes and box projection:
  https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html
- Unreal environment reflections:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/reflections-environment-in-unreal-engine
- Unity HDRP reflections:
  https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@latest/index.html

## Game architecture

- Each streamed chunk checks the already-authoritative point-of-interest
  list. Village, farm, depot, fort, ruined city, dock, lighthouse and
  watchtower sites add a **plain Node3D marker** only if the site center
  belongs to that chunk. Each site therefore gets one marker, not one
  marker per overlapping chunk. Unloaded chunks release their markers.
- The hub places three markers across its stone plaza and nearest building
  ring. No GPU probe is created here either.
- A single `OutdoorReflectionBudget` node scans near markers once every
  **0.45 seconds**, chooses stable nearest locations with **5 m hysteresis**
  and reuses at most **1 High / 2 Ultra** ReflectionProbes. The capture
  cooldown is **1.6 seconds**, preventing one-shot cubemap work each frame.
- UPDATE_ONCE captures remain attached to the selected site until the
  player moves to another place. Probes are centered several meters above
  the ground. The existing sky remains the fallback outside the bounded
  volumes and when outdoors is not near architecture.
- The capture is box-projected (for more stable reflection direction on
  façades), blends over a 3.5 m boundary, and is **not interior**. This
  avoids incorrectly replacing the sun, moon and sky with dungeon ambient.
- Captures sample only default layer geometry, never render their own
  shadow maps, and limit range to 32–42 m. Imported meshes use cheaper
  LOD thresholds inside the captures.
- Only the real online world instantiates the outdoor pool. The existing
  low-detail solo preview and the dungeon reflection pool are unchanged.

## Renderer-aware resource policy

| Preset | Backend | Max active cubemaps | Selection radius | Capture range | Mesh LOD threshold |
| --- | --- | ---: | ---: | ---: | ---: |
| Performance | Any | 0 | — | — | — |
| Balanced | Any | 0 | — | — | — |
| High | Forward+ | 1 | 44 m | 32 m | 2.4 |
| Ultra | Forward+ | 2 | 60 m | 42 m | 1.5 |
| All | Compatibility / Mobile | 0 | — | — | — |

Switching down to Balanced or Performance frees the pooled probe nodes
and their GPU resources. Even on Ultra, a capture is allowed only when
the player's camera is close to an existing site marker.

## Custom Godot engine changes

`scene/3d/reflection_probe.cpp` now validates artist-controlled capture
inputs: finite, nonnegative intensity / blend distance / mesh LOD;
finite capture range; and strictly positive finite capture box size.

The setters for size, blend distance, mesh LOD, intensity and capture
distance are **idempotent**. Reapplying unchanged graphic quality
settings no longer forwards redundant values to RenderingServer or
needlessly touches reflection capture state. The probe retains the
original box-projection, sky ambient, update-mode and culling behavior.

These changes apply to all `ReflectionProbe` nodes used by the
custom engine, including existing dungeon captures.

## Testing and profiling

Added regression suites:
- `game/tests/test_outdoor_reflection_budget.gd`: renderer/quality
  gating, stable selection, no duplicate POI markers, resource limits,
  actual probe properties, hub and streaming world integration.
- `tests/scene/test_reflection_probe_capture.cpp`: native setter
  validation, one-shot configuration, idempotent re-application.
- Registered the game suite in `game/tests/run_all.gd`.

Build the **custom engine**, then import and test game resources:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

Visual QA: compare shiny metal/stone in the hub, city ruins and docks,
both with and without local probes at the same time of day. Inspect
reflection parallax when the camera pans, SSR fallback at volume edges,
sunset/sky transitions, blur, cube-face seams and delayed one-shot captures.
Measure GPU P95/P99 frame time, GPU memory and capture frequency on an
identical route with High/Ultra, plus memory release after switching to
Balanced. Cubemap creation can cause short GPU spikes, which is why
capture rate and distance are aggressively bounded.

**Limits:** a one-shot capture is not continuously synchronized with moving
players, weather or destructible objects. It samples only opaque cubemap
faces and may be inaccurate after major world changes. This is an
intentionally cheap compromise for a streamed MMORPG, not fully dynamic
ray-traced GI/reflections.

The current editing environment has no compiled custom Godot binary or
GPU profiling hardware, so C++ compilation, shader runtime and FPS tests
were not run here; the code and test registration are ready for CI/device QA.
