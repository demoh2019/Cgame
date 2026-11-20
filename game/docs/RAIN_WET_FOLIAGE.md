# Rain-wet vegetation: scalable forest materials

This update extends existing wind/grass/weather rendering with a **quality-
scaled wet leaf PBR response**. It borrows the cost-budgeting approach from
large Unreal/Unity outdoor renderers rather than trying to port their
proprietary renderers to Godot. It is compatible with both Forward+ and
Compatibility.

## In-game behavior

Rain's existing server-time-driven atmosphere updates one
`aa_weather_wetness` GPU global used by terrain, grass and the nature kit.
The foliage material now uses this value to darken leaves and bark and to
blend its **real imported PBR roughness and specular** toward moist,
reflective leaf surfaces.

A separate `aa_vegetation_wet_gloss` shader global defines a rendering
budget by the same graphics preset already used in the game:

| Preset | Wet leaf gloss strength |
| --- | ---: |
| Performance | 0 (matte rain, cheapest) |
| Balanced | 0.35 |
| High | 0.70 |
| Ultra | 1.00 |

The scalar only changes when graphics settings are applied. It is **not**
sent per tree or per chunk. Plant wetness itself follows the existing
smooth atmosphere storm blend; the same leaves look natural in daylight
and more reflective during rain.

The nature-kit tree shader retains its original albedo texture, alpha
scissor, tint, per-tree colour, normal-map distance LOD, metal/roughness/ORM
texture maps and sway animation. The effect adds **no extra texture
samples, nodes, draw calls, animations or server messages**. One additional
uniform is broadcast to all existing foliage batches. Global weather
also continues to animate the already-batched grass and storm wind.

## References and performance rationale

- Unreal Engine's shadowing guidance explains why careful effect budgets
  and fewer shadow casters matter in outdoor scenes:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/shadowing-in-unreal-engine
- Unity URP's GPU Resident Drawer batches repeated objects and reduces CPU
  draw-submission overhead:
  https://docs.unity.cn/6000.4/Documentation/Manual/urp/gpu-resident-drawer.html
- Godot recommends MultiMesh instancing and render distance / HLOD budgets:
  https://docs.godotengine.org/en/4.4/tutorials/performance/optimizing_3d_performance.html

Neither Unreal Nanite/Lumen nor Unity HDRP was copied into the Godot code.
This feature uses Godot's existing materials and GPU-global uniforms.

## Regression and visual QA

```sh
godot --headless --path game --script res://tests/run_all.gd
```

`res://tests/test_rain_wet_foliage.gd` tests global registration,
preset clamping and monotonic quality budget, shader use of real PBR
textures and alpha cutouts, weather synchronisation and the existing
grass batching guarantees.

On a GPU, compare dry/rain at the same camera position in forests,
ruins and swamps on all four profiles. Check diffuse colors, specular
highlights, PBR normal mapping, alpha edges and frame-time p50/p95.
Performance changes should be measured before claiming an FPS increase.
