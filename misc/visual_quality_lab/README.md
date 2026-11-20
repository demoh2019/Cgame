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

## Visual Quality Lab v8 — engine-level scene streaming used by the game

`addons/visual_quality/world_streamer.gd` adds a reusable `WorldStreamer3D`
component based on Godot `ResourceLoader.load_threaded_request()` and
`load_threaded_get_status()`. Assets are loaded in the background, while
PackedScene instantiation and node attachment happen on the main thread.

Cells can contain ordinary hand-authored scenes. Register them with
`register_scene_cell(coord: Vector2i, path: String)`, and assign a player
or camera `Node3D` to `source`. The optional scene-root method
`configure_stream_cell(coord)` is called before the scene enters the tree.
Connect `cell_loaded`, `cell_unloaded`, `asset_load_failed` signals for
per-cell persistence and game systems. Scene resource paths are cached
and only one in-flight asset request is allowed per unique path.

Loading and unloading are constrained by configurable cell radii,
nearest-first ordering, hysteresis (`unload_radius_cells` greater than
`load_radius_cells`), operation budgets and a concurrency limit.
These are operation budgets, not strict per-frame millisecond budgets.
Three quality presets set load radii 1/2/3 cells and unload radii 2/3/4.

### Demonstration

The playable game registers **49 14-meter forest cells (7×7)** using the
reusable `res://world/forest_cell.tscn`. Not all 49 are created at startup:
as the player moves, nearby sections are instantiated and distant ones are
removed. The HUD shows active/registered cells and in-flight assets.
Press **7** to pause/resume streaming, and keys 1–3 to change radius
and foliage density. The ground/collision stage now measures 112×112 m.
Other features — physical player, quest, persistent progress, atmosphere
and dynamic GPU-aware quality — remain integrated.

`ChunkedFoliage3D` now caches shared trunk and canopy meshes/materials
across streamed cells, while keeping per-cell independent MultiMesh
transform buffers and culling.

### Tests and limits

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_world_streamer.gd
godot --headless --path . --script res://tests/test_world_streamer_runtime.gd
```

16/16 static tests passed in the authoring environment. The runtime
test checks threaded asset loading and unloading following source movement.
Godot runtime and Apple Silicon/Metal validation remain outstanding until
CI completes / the authorized Mac becomes available.

This is a reusable engine addon and an integrated demo, **not** a modification
of the Godot C++ scene streamer or automatic Unreal World Partition/HLOD.
Do not treat unloading scene nodes as persistent game state storage; use
`cell_unloaded` to capture relevant state in the host game.

- Godot: https://docs.godotengine.org/en/4.6/tutorials/io/background_loading.html
- Godot thread safety: https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html
- Unreal: https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine


## Visual Quality Lab v9 — persistent world state for streamed cells

Large worlds need **two independent lifecycles**: scene instances may unload to
free rendering/physics resources, while state changed by the player must survive
both streaming boundaries and a game restart. `WorldStateStore3D` is a reusable
Godot scene-streaming component for exactly that use case. It extends the
`WorldStreamer3D` used in v8 and immediately powers interactable forest beacons
in the demo game.

### Engine/scene API

`addons/visual_quality/world_state_store.gd` provides a small protocol for any
streamed `Node3D` root:

- `save_stream_state() -> Dictionary` returns *changed* state, or `{}` for the
  unchanged/default state.
- `load_stream_state(state: Dictionary)` hydrates a newly instantiated cell.
- Optional signal `stream_state_changed` tells the store to persist immediately.
- Optional `get_stream_cell_coord() -> Vector2i` supports attaching the state
  manager after the cells are already loaded.

Set `store.streamer = streamer`, `store.world_id = "your_stable_world_id"`,
and optionally `store.save_path = "user://world_v1.cfg"`; **add the store to
 the scene tree before the streamer begins loading cells**. The streamer now
emits `cell_about_to_unload(coord, cell)` while the live node still exists.
The store captures the state there, before `remove_child()` / `queue_free()`.
When a cell reappears, its state is restored after instantiation.

Save files are versioned and keyed by world ID and stable integer grid cell
coordinates (`x:z`), preventing accidentally reapplying one world's state to
another. The store rejects Object/Resource/Node references in snapshots and
only accepts bounded native primitive properties (bool, int, float, string,
Vector2, Vector3, Color). It writes to `user://...tmp` and atomically renames
that file over the prior save on success. Missing or incompatible saves are
ignored rather than silently migrated. Every active cell is snapshotted on
explicit save/exit; immediate changes are saved when notified by a cell.

For larger online worlds, additional measures would be required: server-side
ownership, validation, replication, migrations, conflict resolution, background
save I/O, and checkpoint/backup management. This implementation is intentionally
**local, single-player, and opt-in**; it does not rewrite Godot's C++ renderer.

### Integrated demonstration

Each streamed forest cell now has an **orange emissive beacon**. Walk near a
beacon and press **G** to activate it; it turns **green**. The HUD displays
"Saved cells". Walk beyond the forest cell's unload radius and return: that
beacon will still be green after its `PackedScene` is recreated. Progress also
survives restarting the demo. Press **8** or click "Reset forest beacons" to
clear all stored beacon states, both currently active and unloaded. The
previous light-shard quest (`F`), quality presets (1–3), day/night/weather
(4–6), streaming toggle (7) and character locomotion remain available.

### Verification

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_world_state_store.gd
godot --headless --path . --script res://tests/test_world_state_runtime.gd
```

The static suite passed **19/19** checks in the authoring environment.
The two new GDScript suites test serialization, rejection of references,
version/world isolation, activation, unload, rehydration and reset. They must
be executed with Godot to validate runtime correctness. Target macOS Metal
rendering and FPS also remain unverified while the linked Mac is offline.

Architecture references:

- [Godot: saving games](https://docs.godotengine.org/en/4.6/tutorials/io/saving_games.html)
- [Godot: DirAccess atomic rename](https://docs.godotengine.org/en/4.6/classes/class_diraccess.html)
- [Unreal: World Partition](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine)


## Visual Quality Lab v10 — streamed navigation and persistent NPCs

The open-world engine extension now streams **navigation regions and AI
characters together with the forest cell scenes**. The demo spawns one blue
patrol NPC in each loaded cell. The NPC follows a four-way deterministic patrol
using Godot's `NavigationAgent3D` and becomes orange / ALERT when the player
enters its 4.5 m awareness radius. It returns to patrol after the player
passes 7 m away (hysteresis avoids state oscillation). NPCs do not attack; this
is a navigation and behavior prototype, not a combat system.

### Reusable engine components

- `addons/visual_quality/navigation_tile.gd` (`StreamedNavigationTile3D`):
  a minimal `NavigationRegion3D` adapter with a one-polygon planar tile.
  When an authored/pre-baked `NavigationMesh` is supplied, automatic flat
  generation is skipped. Region nodes disappear with the streamed cell.
- `addons/visual_quality/streamed_patrol_npc.gd` (`StreamedPatrolNPC3D`):
  physical `CharacterBody3D`, one `NavigationAgent3D`, path following at physics
  cadence, decision/sensing cadence of 0.9/0.55/0.35 s for Eco/Balanced/
  Cinematic. Avoidance RVO is disabled by default to avoid cost with many agents.
  The agent waits for navigation-server map synchronization before querying a
  route and calls `get_next_path_position()` every physics tick when active.
- `world/forest_cell.gd` now creates both navigation region and NPC after the
  cell is instantiated. It passes the existing player's node as the NPC's
  awareness target and connects quality controls to the NPC decision interval.
- `WorldStateStore3D` from v9 now also persists per-cell NPC patrol index and
  bounded local position. Only primitive properties are serialized; transient
  node, navigation agent, and player references are never stored. This state
  is captured when a cell unloads and restored when that cell respawns.

**In-game diagnostic:** the HUD shows active NPC count and number alerted.
Press **9** to pause/resume NPC AI across loaded cells. New cells inherit the
current global AI setting. All earlier player/quest/streaming controls remain.

### Limitations and profiling

The sample's planar tiles only cover a flat surface. They **do not account for
central stage props or tree trunks**. For an actual level with complex geometry,
replace each tile's flat mesh with a baked NavigationMesh that avoids obstacles,
and test cross-cell region connectivity. For larger NPC populations, add interest
management, temporal throttling of the physics navigation updates, animation
LOD, appropriate RVO agent policies, and actual CPU/GPU profiling. No C++
engine core files were changed, and this addon is not a replacement for Unreal
World Partitioned NavMesh.

### Tests

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_streamed_navigation.gd
godot --headless --path . --script res://tests/test_streamed_navigation_runtime.gd
```

The Python suite has **21 passing static/package tests**; GDScript and Godot
runtime testing **still require a working Godot binary and Apple Metal target
hardware**, neither available in this execution environment. The PR CI includes
both GDScript tests but has not yet reported a passing run.

Technical references:
- https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html
- https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html
- https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partitioned-navigation-mesh-in-unreal-engine



## Visual Quality Lab v11 — obstacle-aware streamed navigation and AI simulation LOD

**Engine addon:** `StreamedNavigationTile3D` now supports rectangular blocked
regions and an agent clearance margin. Rather than rebaking the visual scene,
it builds a low-polygon, welded navigation grid whose blocked polygons are
omitted. A single center obstacle uses **8 walkable quads** (versus one flat
quad that allowed movement through obstacles). A configurable maximum of eight
rectangles per tile bounds the polygon count. Existing baked `NavigationMesh`
resources remain untouched; the runtime generator is an opt-in fallback for
simple flat world cells. For complex geometry or dynamic obstacles, bake or
incrementally update actual navigation meshes using Godot's official APIs.

**Immediately in the game:** streamed forest cells outside the central showcase
cell now contain a 2.2 × 2.2 m solid rock. Their navmesh has a corresponding
exclusion expanded by 0.35 m, so NPC centers should route around the rock.
The central showcase retains its existing stage props and flat navigation
surface; those showcase props are **not yet** represented in the navigation
mesh. The generated nav tiles also do not account for procedural tree trunks,
which currently have no individual collision shapes.

**AI service:** `WorldAIInterestManager3D` manages nearby vs sleeping NPCs
according to player distance with entry/exit hysteresis. Instead of updating
all agents simultaneously, it checks up to **6 / 8 / 12 cells per update**
(Eco / Balanced / Cinematic), every 0.45 seconds by default. Simulation radii
are 18 / 28 / 42 m; asleep NPCs suspend their per-physics-tick AI, without
unloading persistent state. A global AI disable suspends all currently loaded
agents immediately. The manager also reports the CPU microseconds spent in
its **own interest-update pass**, not total navigation/AI frame time.
The HUD shows sleeping NPCs and the last interest pass duration.

This is an opt-in GDScript engine service integrated into the Visual Quality Lab
playable demo, not a Godot C++ core rewrite, Unreal MassEntity implementation,
full Recast bake, dynamic RVO crowd system or a finished AAA game.

### New regression scripts

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -q
godot --headless --path . --script res://tests/test_navigation_obstacles.gd
godot --headless --path . --script res://tests/test_ai_interest.gd
godot --headless --path . --script res://tests/test_navigation_obstacles_runtime.gd
```

**24/24 Python static/package checks** passed locally. The GDScript algorithm,
collision/navigation and rendered-frame verification requires a working Godot
binary; the authorized Apple Silicon machine remains offline, and CI is not
confirmed passing. No unverified behavior should be treated as production-ready.

Technical references:
- https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html
- https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html
- https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partitioned-navigation-mesh
