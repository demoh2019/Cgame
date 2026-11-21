# Cgame rendering (experimental)

This optional built-in 3D module ports the game's GDScript client rendering features into native engine code. Each class keeps the semantics of the GDScript library it replaces (`game/scripts/client/*.gd`), so game code can move over without behavior changes. The GDScript facade in `game_facade/cgame_rendering.gd` prefers the native class (checked through `ClassDB`) and falls back to the GDScript library when the engine was built without this module.

## Classes

| Native class | Replaces | Notes |
|---|---|---|
| `CgameImpostorBaker` | `impostor_baker.gd` | Bakes 8 yaw frames at 128 px into an atlas inside an isolated `SubViewport` world; atlas cache keyed by mesh. Embeds the impostor shader (`get_impostor_shader()`). Never bakes on the headless display server. |
| `ImpostorField3D` | `impostor_field.gd` | `MultiMeshInstance3D` far-LOD ring of camera-facing impostor quads; hidden until its atlas is baked; range tiers per quality level. |
| `CgameShaderWarmup` | `shader_warmup.gd` | Draws every spatial `.gdshader` once on a sub-pixel quad (color and shadow pipelines) and exposes the `RenderingServer` pipeline compile counters. |
| `CgameFoveatedShading` | `graphics_foveated_shading.gd` | Elliptical VRS rate map builder and `Viewport` apply with texture cache. |
| `CgameFramePacing` | `graphics_frame_pacing.gd` | V-Sync mode and FPS cap per tier from the display refresh rate. |
| `CgameHDROutput` | `graphics_hdr_output.gd` | `DisplayServer` HDR request and paper-white luminance by tier. |
| `CgameAreaLights` | `graphics_area_lights.gd` | Emitter size (PCSS) for registered `OmniLight3D`/`SpotLight3D`, soft shadow filter quality per tier. `register_light` replaces the GDScript `register` (reserved word in C++). |
| `CgameVRAMBudget` | `graphics_vram_budget.gd` | Per-tier video memory budgets and sustained-pressure detection. |
| `CgameGPUResourceReport` | `gpu_resource_report.gd` | Scene walk estimating mesh/material/texture/shader VRAM, render-pass info, memory timeline ring buffer and Markdown report. |
| `CgameRTEffect` | `rt_compositor_effect.gd` | Native `CompositorEffect` (render thread): BLAS cache with budgeted builds and LRU eviction, TLAS, ray-query shadow and AO passes, spatial and temporal denoise. GLSL embedded in `cgame_rt_shaders.h`. |
| `CgameInstanceCulling` | `gpu_instance_culling.gd` | Frustum and Hi-Z culling with a compute path on a local `RenderingDevice` and an exact CPU path. GLSL embedded. |

Not ported (no native class requested): `character_shading.gd`, `sea_fft_detail.gd` and the scene-scanning driver `rt_effects.gd`. The driver-side pure helpers it uses (`settings`, `extract_triangles`, `pack_positions`, `pack_indices`, `blas_key`, `select_nearest`, `budget_take`) are available as static methods on `CgameRTEffect`, and the driver keeps working with the native effect through `submit()`, `configure()` and `take_evicted_keys()`.

## Verification status

Pure logic (frame pacing, HDR wanted, area-light sizes, VRAM pressure, texture byte estimates, VRS map layout, culling kernel versus an independent brute force, Hi-Z occlusion, impostor frame size, RT budget/eviction/parameter packing/source assembly) is covered by doctest cases in `tests/test_cgame_rendering.h`.

Not verified on hardware: the GPU path of `CgameInstanceCulling`, the whole `CgameRTEffect` render-thread pipeline (needs `RenderingDevice::SUPPORTS_RAY_QUERY`, which Metal does not provide today), the visual result of the impostor bake and `ImpostorField3D`, `CgameShaderWarmup` pipeline counters and the VRS/HDR requests. These require a full build and a GPU; the module was only syntax-checked when it was written.

## Using it

Build Godot with the `cgame_rendering` module enabled (available when 3D is enabled).

```gdscript
CgameFramePacing.apply(2)
CgameHDROutput.apply(3, "forward_plus")
ImpostorField3D.configure(2)
ImpostorField3D.add(chunk, bush_mesh, bush_transforms, 60.0)
CgameShaderWarmup.start($Camera3D)
```

Or through the facade, which also works on engines without the module:

```gdscript
const Gfx = preload("res://game_facade/cgame_rendering.gd")
Gfx.frame_pacing_apply(2)
```
