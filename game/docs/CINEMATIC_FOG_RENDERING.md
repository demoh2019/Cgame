# Cinematic lighting: hybrid fog for beautiful and scalable world atmosphere

The canonical `game/` client now supports two **renderer-aware** atmospheric
paths inspired by high-quality AAA lighting without imposing Forward+ GPU
requirements on the default Compatibility build.

## What players see

- **Compatibility / Mobile / Performance / Balanced:** very inexpensive
  height-based mist near sea level. Haze is slightly thicker in rain and when
  the sun is low. The existing colored distance fog, horizon palette,
  day/night lighting, clouds, wet grass and storm darkening remain intact.
- **Forward+ High:** the same depth/height atmosphere plus a short
  **48-meter** physically based volumetric-fog region. Sunlight scatters
  in near-field fog, improving silhouettes at dusk and during rain.
- **Forward+ Ultra:** the volumetric effect reaches **72 meters**, uses
  a slightly stronger scattering density and keeps more detail near
  the camera. This remains a consciously GPU-intensive manual option.

Fog uses the existing authoritative, interpolated weather/day clock. No
new gameplay events, server RPCs, scene reloads, camera shake or
per-frame noise texture builds are introduced. No scattering grid is
allocated by the Compatibility or Mobile renderer.

## Performance and correctness decisions

1. Follow Godot's native **froxel-based volumetric fog** on Forward+,
   instead of implementing expensive ray-marching inside each terrain
   or water material. This approach follows the goal of Unreal Engine's
   real-time aerial perspective and Unity's HDRP volumetric fog while
   using actual Godot engine facilities.
2. On **High**, cap the froxel region at 48 m, versus 72 m on **Ultra**.
   A shorter region provides finer depth slices at the same GPU grid size,
   and reduces distant fog overdraw and ghosting.
3. Enable temporal reprojection at **0.66/0.74** rather than the more
   ghost-prone default 0.9. Avoid expensive GI/ambient injection into
   fog; keep the existing directional sun as the only volumetric
   lighting source for this feature.
4. Compute only a handful of smooth CPU scalar values per weather
   update: height density, volumetric density and sun scattering.
   No 3D noise texture, additional shadow map, fullscreen postprocess,
   extra vegetation geometry or extra dynamic lights are introduced.
5. Maintain continuous weather fading, clamping volume density to
   0.02 and near-ground fog density to 0.004. Player visibility remains
   readable; storms increase atmosphere but never force whiteout.
6. **One source of truth:** `cinematic_fog.gd` determines
   renderer/quality eligibility. `graphics_lighting.gd` delegates
   to the same profile instead of writing conflicting values after
   `atmosphere.gd` has configured volumetrics.

## Integration points

- `scripts/client/cinematic_fog.gd` — pure renderer profile and
  weather response, plus implementation of Godot `Environment` and
  `DirectionalLight3D` parameters.
- `scripts/client/atmosphere.gd` — applies conditions during the
  already existing day/night/weather loop.
- `scripts/client/graphics_quality.gd` — propagates the **actual**
  renderer after any engine fallback and the selected quality tier.
- `scripts/client/graphics_lighting.gd` — the same shared fog
  budget, preserving existing cascaded shadow map settings.
- `tests/test_cinematic_fog.gd` — validates renderer gating,
  bounds and transitions, actual Environment properties, and
  the quality selector's integration.
- `tests/test_graphics_lighting.gd` — updated to ensure the
  previously existing lighting module agrees with the new
  dedicated fog policy.

The local solo preview and the online client both use
`GraphicsQuality.apply` and `Atmosphere`; this is not a separate
demo scene. No native C++ extension or engine rebuild is required.

## How to check visual results

```bash
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

Capture a fixed scene/camera and compare:

- Clear morning, midday, sunset and nighttime at the shoreline.
- A storm in forests and at the abandoned city edge.
- Compatibility at Performance, Balanced and Ultra.
- Forward+ at Balanced, High and Ultra (with warm shader caches).

For comparable benchmarks, measure GPU frame-time median/p95,
draw calls, VRAM, shadows and the cost of volumetric fog in the same
hardware and location. **No FPS improvement is claimed until real GPU
measurements are available.** High/Ultra should be visibly richer
on supported hardware; lower modes retain readability and budget.

Source references:

- Godot — https://docs.godotengine.org/en/4.6/tutorials/3d/volumetric_fog.html
- Godot Environment — https://docs.godotengine.org/en/4.6/classes/class_environment.html
- Unreal Engine shadow budgets — https://dev.epicgames.com/documentation/en-us/unreal-engine/virtual-shadow-maps-in-unreal-engine
- Unity terrain shader detail budgets — https://docs.unity.com/en-us/engine/6000.3/manual/creating-environments/script-terrain/terrain-shader-graph
