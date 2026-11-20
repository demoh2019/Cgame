# Visual Quality Lab — Godot 4.x / Cgame

An **opt-in playable 3D rendering demo** and a portable dynamic-resolution component, using ideas from Unreal Engine's frame budget / temporal upscaling approach without pretending to implement Lumen, Nanite, VSM, or TSR. The scripts only use stock Godot features; no changes to Godot core or proprietary dependencies are needed.

## What is included

- `addons/visual_quality/adaptive_resolution.gd`: smooths measured FPS over one-second samples, waits for warmup/cooldown, changes only the 3D render buffer scale using asymmetric step sizes and hysteresis, and restores the viewport on exit. Keeps UI/native window resolution unchanged.
- `addons/visual_quality/filmic_sky.gdshader`: procedural sky gradient, three-octave cloud noise, sun halo. Uses `LIGHT0_*` built-ins and avoids `return` in `sky()` (the source of a known Godot sky shader error). Does not reference `TIME`, avoiding mandatory radiance cubemap updates every frame. Cloud animation is **off** by default.
- `demo.tscn`: procedural 3D scene with a metallic/material comparison row, sunlight, shadows and FPS/scale overlay. Press **1** (Eco), **2** (Balanced), **3** (Cinematic).

## Quick start

1. Open this directory as a Godot 4.4+ project. The project defaults to **Forward+** for modern desktop hardware (including Apple Silicon/Metal). Switch to Compatibility or Mobile in Project Settings for weaker hardware; screen-space features are disabled in the demo on Compatibility and Mobile.
2. Open `demo.tscn` and press F6 (or run the project). Use keys **1**, **2**, **3** to compare quality tiers.
3. For an existing game, copy `addons/visual_quality` into its `res://addons/` folder. Add a **Node** under its main 3D scene and attach `res://addons/visual_quality/adaptive_resolution.gd` to it. Set your target FPS and limits in the Inspector. Optionally set a Sky resource's ShaderMaterial to `filmic_sky.gdshader` in your WorldEnvironment.

## Apple Silicon / performance

- **Forward+ (Metal)** supports SSR/SSAO/SSIL and spatial/temporal upscalers, but high-quality effects cost GPU time. Compare presets on actual hardware.
- Compatibility and Mobile modes skip Forward+-specific screen-space effects in this demo.
- Dynamic resolution helps only *GPU pixel-bound* scenes. CPU-bound scenes, shader-compilation hitches or broken frame pacing require profiling, not blindly reducing render resolution.
- The component selects spatial FSR1 only when a RenderingDevice renderer is active and the project currently uses bilinear scaling. It preserves an existing FSR2/MetalFX mode rather than overwriting it.
- This is a standalone demo, **not automatically integrated into an inaccessible game's project files**, and is not a Godot core engine change.

## Validation

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_adaptive_resolution.gd
godot --headless --path . --quit-after 120
```

Python verifies packaging and sky-shader invariants; only Godot actually checks the GDScript parser and shader/runtime. Run tests on macOS Metal before shipping.

## Visual Quality Lab v2 (November 20, 2026)

**Game-ready controls:** `addons/visual_quality/quality_manager.gd` manages three render profiles and optional dynamic resolution. The demo exposes clickable **Eco / Balanced / Cinematic** and **Adaptive ON/OFF** buttons; keys **1**, **2**, **3** continue to work. Settings are stored per project in `user://visual_quality_lab.cfg` with Godot `ConfigFile`. Invalid saved values fall back to Balanced/Adaptive ON. This is a *portable component*; installing the addon does not implicitly modify a separate game's settings menu.

**CPU-bound protection:** The dynamic resolution script samples Godot's `Performance.TIME_PROCESS` and `Performance.TIME_PHYSICS_PROCESS` as approximate CPU load hints. When either one alone consumes at least 90% of the target frame budget, the scaler declines to lower the 3D scale. This heuristic is conservative and **does not measure GPU time**; it is not a full substitute for Unreal Engine's dynamic resolution heuristics or a GPU profiler.

**Isolation and rollback:** the `VisualQualityManager` restores its assigned `Environment` effects when removed. The `AdaptiveResolution3D` node restores the original viewport's scale and scaling mode on exit. The manager never edits global Project Settings. To integrate into an existing game, instantiate `AdaptiveResolution3D` and `VisualQualityManager` in the same 3D scene, set `manager.adaptive_controller` and `manager.target_environment` **before** adding the manager node to the scene tree. Connect your own settings UI to `set_profile()` and `set_adaptive_enabled()`.

### Extra tests

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_adaptive_resolution.gd
godot --headless --path . --script res://tests/test_quality_manager.gd
godot --headless --path . --quit-after 120
```

The Python checks are static/package checks. Run the three Godot commands before marking this package as runtime validated on macOS Metal or other supported drivers.

### References

- [Godot: resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html)
- [Godot: sky shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
- [Unreal Engine: dynamic resolution](https://dev.epicgames.com/documentation/en-us/unreal-engine/dynamic-resolution-in-unreal-engine)


## Visual Quality Lab v3 — GPU frame-time control

When `enable_gpu_frame_measurement` is enabled, the adaptive scaler uses Godot's official `RenderingServer.viewport_get_measured_render_time_gpu()` (milliseconds) to compare actual GPU render cost with the frame-time budget, rather than interpreting capped FPS as GPU load. It uses separate downscale/upscale thresholds (103% / 85% of the budget), integrates over one-second samples, and keeps the existing warmup and cooldown. With an unavailable or zero GPU timing result, it falls back to FPS plus the CPU-work heuristic. The demonstration opts into GPU timing by default; the portable component does **not** opt in automatically.

**Shared-viewport warning:** `viewport_set_measure_render_time` toggles measurement on an entire viewport and does not provide reference counting. Avoid enabling this feature on viewports whose GPU timer measurements are owned by another profiler or quality system. The component disables measurement on exit; use `enable_gpu_frame_measurement=false` if that interferes with other tools. GPU timings are not verified on macOS Metal in this session.

GPU measurement documentation: [Godot RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu).


## Visual Quality Lab v4 — dynamic atmosphere + tiered sky radiance

The demo now includes a portable **AtmosphereController3D** (
`res://addons/visual_quality/atmosphere_controller.gd`) that adds a 24-hour
sunlight curve, warm sunrise/sunset tint, shaded nights, sparse procedural
stars, controllable overcast/cloud layers, and inexpensive distance fog.
The sky's radiance cubemap is refreshed only after explicit setting changes
or at `update_interval_seconds` (2 seconds by default), not every game frame.
Use the **4** key or **Day / Night** button to jump between 14:00 and 22:00,
**5** or **Clear / Cloudy** to switch overcast, and **6** or the **Cycle**
button to enable/disable a full 24-hour loop (480 seconds by default).
Cloud movement is optional (`animate_clouds = false` by default).

**Integration:** copy the `addons/visual_quality` folder into your game.
Create an AtmosphereController3D Node using the script, assign its
`sun: DirectionalLight3D`, `environment: Environment` and
`sky_material: ShaderMaterial` references **before adding it** to the scene
 tree. The provided sky shader must be used for night/star parameters; otherwise
update the script's shader uniforms to match your own sky. The controller
captures and restores the original sun, fog, and sky material uniforms on
exit. Set `restore_on_exit = false` only if you intentionally want changes to
persist after removing the controller.

**Quality scaling:** VisualQualityManager now also sets the radiance cubemap
resolution for its assigned Sky: Eco=128, Balanced=256, Cinematic=256.
A high-end-only opt-in switch `use_512_radiance_in_cinematic` enables 512 for
Cinematic, which may be too expensive on Apple M1 and laptops. Original
sky radiance size is restored on exit. This is intentionally separate from
the dynamic 3D resolution and can be disabled with `manage_sky_radiance`.

### Validation for v4

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_atmosphere.gd
godot --headless --path . --script res://tests/test_adaptive_resolution.gd
godot --headless --path . --script res://tests/test_quality_manager.gd
godot --headless --path . --quit-after 120
```

Python static/package suite: **9 passing checks** in the authoring environment.
GDScript runtime, shader compilation, visual output, and performance on macOS
Metal remain **unverified** until run in Godot on the target hardware.
Avoid running the time-of-day system on a shared Sky resource without cloning
it first; multiple scenes referencing the same resource will see the change.

Design references:
- [Godot Sky process modes and radiance sizes](https://docs.godotengine.org/en/4.6/classes/class_sky.html)
- [Godot environment and fog](https://docs.godotengine.org/en/4.6/classes/class_environment.html)
- [Unreal Engine dynamic resolution](https://dev.epicgames.com/documentation/en-us/unreal-engine/dynamic-resolution-in-unreal-engine)


## Visual Quality Lab v5 — chunked GPU-instanced forest and flythrough

`addons/visual_quality/foliage_chunks.gd` builds reproducible tree layouts
from independent seeded cells. Trunks and crowns are rendered with two
MultiMeshes per nonempty cell rather than hundreds of individual MeshInstance3D
nodes. Per-cell AABBs and `visibility_range_end` permit frustum/distance
culling; one giant MultiMesh would always be visible as a unit.

Quality profile changes immediately change tree density (`visible_instance_count`)
and visibility range without regenerating geometry: Eco (35%, 28 m),
Balanced (65%, 48 m), Cinematic (100%, 78 m).

The demo also has a fly-through controller:
WASD movement, Q/E vertical movement, Shift sprint, right-mouse drag to look.
The center 12-meter radius is kept clear for the material comparison stage.

`tests/test_foliage.gd` verifies deterministic generation, per-cell seed
separation, bounded attempt loops, and excluded regions. This is low-poly
procedural world dressing, **not** Unreal Nanite/HLOD or biome streaming.
It does not implement tree collision, wind, seasons, or a playable quest system.

Godot reference: https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html
Visibility ranges: https://docs.godotengine.org/en/4.6/tutorials/3d/visibility_ranges.html
Unreal HLOD: https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-hierarchical-level-of-detail-in-unreal-engine


## Visual Quality Lab v6 — playable forest quest and persistent progression

Instead of limiting the example to a graphics showcase, the demo now includes a small **playable exploration quest**. Twelve emissive light shards spawn around the forest on a deterministic seed, with a 15–35 meter radius and a non-overlapping angular distribution. Fly with WASD/Q/E, approach a glowing blue shard, and press **F** within 2.5 meters to collect. The HUD shows progress and proximity guidance. Press **R** or the restart button to replay. On collecting the final shard, the quest clears overcast and restores full midday sunlight through the existing atmosphere controller.

The reusable module is `addons/visual_quality/exploration_quest.gd` (`ExplorationQuest3D`). It validates pickups on the game side, prevents duplicate collection, and saves collected IDs to `user://visual_quality_quest_v1.cfg` with version, seed, and item-count checks. The quest uses no network services, accounts, premium currency, telemetry, or copyrighted content. It is a **local single-player prototype** (not a multiplayer-authoritative reward system), and does not claim to be an entire RPG.

To use the quest in another game, create an `ExplorationQuest3D` node, assign its `player` to a camera/player `Node3D` *before adding it to the scene*, and optionally connect `progress_changed`, `pickup_hint_changed`, and `quest_finished` to your own UI and world systems. The world-space placements assume a flat floor around local Y=0; replace `generate_positions()` with terrain-sampling for uneven worlds. The demo assigns the physical player's eye-level Camera3D as its pickup reference.

New regression script: `res://tests/test_exploration_quest.gd`, covering deterministic spawn layout, bounds, pickup proximity, duplicate prevention, reset and state validation. CI runs this test as part of the Godot headless suite. **Actual Godot execution and Apple Metal rendering remain unverified while the CI job is queued and the authorized Mac is offline.**

Source pattern: [Godot user:// data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html), [Godot ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html).


## Visual Quality Lab v7 — first-person physical movement

The prototype now defaults to a **real `CharacterBody3D`** instead of the
free-floating renderer camera. Its capsule collides with a real static floor
and stage obstacles, while the camera is at eye height. Unlike visual-only
movement, the controller handles slopes, floor snap, gravity, jumping,
acceleration, braking, sprinting, and air control in `_physics_process()`.
It offers forgiving **jump buffering** (0.12s) and **coyote time** (0.12s)
without repeated bunny-hopping when the jump key is held. This follows the
same separation of ground/air movement as modern character-movement systems.

**Controls:** WASD walk, Space jump, Shift sprint, RMB drag to look, V to
switch between collision-aware walking and optional free flight. In flight,
Q/E move down/up. F picks up nearby shards; R resets the quest. All weather,
quality and graphics UI controls from v6 remain usable. A new HUD indicator
shows WALK or FLY. The old `fly_camera.gd` remains bundled only for API
compatibility; the demo now uses `character_controller.gd`.

To integrate into an existing 3D game, instantiate `VisualLabCharacter3D`
(or attach `character_controller.gd` to a `CharacterBody3D`) and give it a
collision-enabled level. If the player node has no collision/camera child,
the script creates a capsule and eye-level camera automatically. This is a
local single-player controller, not a full multiplayer predicted movement
component or animation rig. The demo does not yet implement terrain-aware
shard placement or physical tree-trunk collisions.

### Verification commands

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_character.gd
godot --headless --path . --script res://tests/test_character_physics.gd
godot --headless --path . --quit-after 60
```

The Godot physics test spawns a real static floor, drops the player capsule,
checks landing, and checks walk/fly toggling. Python static checks do not
establish that rendering or physical simulation works on a target GPU.

References: [Godot CharacterBody3D](https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html),
[Unreal Character Movement](https://dev.epicgames.com/documentation/en-us/unreal-engine/movement-components-in-unreal-engine).
