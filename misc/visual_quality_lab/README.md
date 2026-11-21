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


## Visual Quality Lab v12 — world telemetry and adaptive work budgets

This version adds two **reusable GDScript engine extensions** and wires both
into the playable open-world demo. They are designed to help diagnose and
moderate CPU spikes from scene streaming and navigation, without conflating
CPU work with a GPU-limited frame rate.

### `WorldTelemetry3D`: bounded measurements and repeatable captures

- Samples Godot `Performance` monitors every 0.5 seconds: FPS, CPU process
  and physics times (in ms), object count; plus current loaded/pending world
  cells, scene-streaming duration (microseconds), cells created/released per
  streaming update and since project launch, AI interest-manager time and
  sleeping NPC count.
- Keeps **at most 240 records** in a circular buffer (configurable). Exposes
  a CPU-time 95th percentile and returns defensive snapshot copies.
- Press **0** to toggle the in-game profiling overlay. Press **P** to save
  the recorded samples as CSV under
  `user://visual_quality_world_telemetry.csv`. CSV writing is explicit,
  not performed continuously in `_process()`. Only `user://` destinations
  are allowed for the built-in exporter.

### `WorldBudgetGovernor3D`: cooperative CPU pressure control

- Every 0.8 seconds, consumes a new **CPU** sample. It lowers the per-update
  scene-spawn count and the AI-interest update count only after **3 sustained
  high-load windows**; it restores their counts after **5 sustained low-load
  windows**. Between thresholds, counts remain unchanged to resist jitter.
- The nominal target is **16.7 ms CPU**; the threshold and window lengths
  are configurable. Eco, Balanced and Cinematic cap scene instantiation to
  **1/2/4 cells** per streamer update and AI checks to **6/8/12 cells** per
  interest pass. Streaming unloads are not throttled by the governor, to avoid
  retaining distant scene instances unnecessarily.
- Independently, `WorldStreamer3D` enforces a configurable **2,500 µs
  cooperative budget** between scene instantiations. This is *not a hard
  real-time limit*: a single expensive `PackedScene.instantiate()` cannot
  be interrupted once begun.
- Press **B** to toggle the automatic governor. Disabling it restores the
  defaults for the active quality preset. The HUD shows current budgets.

**Interpretation:** Godot `Performance.TIME_PROCESS` and
`TIME_PHYSICS_PROCESS` are approximate engine-side monitors. They are not
GPU timings or exact end-to-end frame-duration measurements, and their values
can be affected by project configuration, vsync, frame limiting, profiler
sampling and platform. The governor is an **experimental heuristic** until
profiling has been completed on the target machine. Real verification must
include Godot's built-in CPU/Visual profilers and device-specific GPU timings.

### Validation

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -q
godot --headless --path . --script res://tests/test_world_telemetry.gd
godot --headless --path . --script res://tests/test_world_budget_governor.gd
```

The local Python static suite has **27/27 passing checks**. The two GDScript
tests exercise ring-buffer ordering, P95, defensive reads, CSV output,
hysteresis, clamped budgets and quality-mode recovery. They are also included
in the CI workflow but have **not yet been executed in Godot** in this working
environment, and Apple Silicon/Metal performance remains unverified.

References:
- https://docs.godotengine.org/en/4.6/classes/class_performance.html
- https://docs.godotengine.org/en/4.6/tutorials/scripting/debug/the_profiler.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/introduction-to-performance-profiling-and-configuration-in-unreal-engine


## Visual Quality Lab v13 — predictive scene streaming and per-cell hotspot diagnostics

This release adds reusable, deterministic **velocity-aware streaming priorities**
and an in-game **per-cell performance inspector**. Both are integrated in the
existing playable forest and work with the v8–v12 streaming, state, quality,
AI and CPU budgeting modules.

### New engine services

`WorldStreamingPlanner3D` (`addons/visual_quality/world_streaming_planner.gd`)
contains pure, testable algorithms for predicting which cell the player is
likely to reach using their *local-space velocity*. Look-ahead is limited to
0.8 seconds and 2 cells by default. All urgently needed cells inside the
current loading radius are sorted first (closest cells before distant ones),
with velocity direction used only to break ties. At most 4 optional look-ahead
cells inside the unloading radius are appended afterwards; speculative cells
cannot evict currently needed cells or bypass the spawn operation/time budgets.
A stopped player does not trigger speculative requests. The planner reads
registered/active cell coordinates and never instantiates scene-tree objects.

`WorldStreamer3D` now records per-cell costs for successful instantiation
and unload callbacks: last spawn, peak spawn, last unload, and number of
operations. Profiling includes scene instantiation and ready/cell-loaded
callbacks; unload timing covers detach/queue-free work, **not** deferred
memory reclamation. Only the most recent 96 cell profiles are retained by
default, with oldest-record eviction so diagnostics do not grow forever.
A sorted `get_slowest_cells()` accessor returns **defensive copies**.
The v12 profiler/CSV stream adds cumulative prefetch count, number of
profiled cells, and the worst observed cell spawn cost.

### Game tools and controls

The new `WorldStreamingInspector3D` shows a compact spatial map at the top
right: `@` is the player cell, `#` a loaded cell, `+` a predicted future
cell, and `.` a registered-but-unloaded cell. The map also shows aggregate
load metrics and the three most expensive cell spawns by CPU time. Press
**K** to show/hide the map, and **L** to export per-cell hotspot data to
`user://visual_quality_cell_hotspots.csv`. Existing **P** telemetry CSV and
**B** automatic work-budget controls remain available. Exporting is
explicit and accepts only `user://` paths.

### Tests and scope

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_streaming_planner.gd
godot --headless --path . --script res://tests/test_streaming_cell_profiler.gd
godot --headless --path . --script res://tests/test_predictive_streaming_runtime.gd
```

30/30 Python static/package tests passed locally. The new Godot tests cover
negative coordinates, prediction limits, deterministic priority, resource
safety, bounded profiling, CSV output and an actual predictive load/unload
scene flow. **They have not executed in Godot here**: the project's CI remains
queued, the authorized Mac is offline, and this environment lacks the Godot
runtime. No unverified FPS or hardware improvement is claimed.

This is **a reusable GDScript engine extension immediately applied to the
demonstration game** in `misc/visual_quality_lab`, not a rewrite of Godot's
C++ streaming core nor an implementation of Unreal World Partition/HLOD.
A different, local game project remains out of reach and is not modified.

References:
- https://docs.godotengine.org/en/4.6/tutorials/io/background_loading.html
- https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine


## Visual Quality Lab v14 — stream-safe contextual interaction system

This update adds a reusable gameplay/engine service,
`addons/visual_quality/world_interaction_router.gd` (`WorldInteractionRouter3D`),
that connects streamed world objects to a single interaction command. It is
immediately instantiated in `demo.gd` and works with existing systems rather
than requiring a new scene architecture.

### Provider API

Any `Node3D` may expose the following optional protocol:

```gdscript
func get_interaction_targets(eye: Vector3, search_radius: float) -> Array[Dictionary]:
    return [{"action_id": "activate", "position": global_position,
             "label": "Activate", "radius": 2.8}]

func activate_interaction(action_id: String, actor: Node3D) -> bool:
    # Revalidate availability and distance here (never trust a cached prompt).
    return false

func get_interaction_message(action_id: String) -> String:
    return ""
```

The router queries the existing global quest provider, then inspects only
*nearby loaded* `WorldStreamer3D` cells through direct coordinate lookups.
It selects the nearest relevant action in the camera's forward cone, with
stable tie-breaking. There is an optional physics ray for line-of-sight; this
is **off** by default to avoid unexpectedly blocking interactions with
non-colliding example objects. Actions are re-selected and validated when
executed; `cell_about_to_unload` clears focused scene references before the
streamer frees the cell. This avoids calls into scenes that no longer exist.

The same **H** key now interacts with three kinds of gameplay targets: collect
blue light shards, activate orange forest beacons, or talk with patrolling NPC
forest guards. The on-screen context prompt shows what H will do, and a feedback
line reports the result. The old **F** pickup and **G** beacon controls remain
available for compatibility. NPC conversations are counted per cell and are
saved/restored through the existing `WorldStateStore3D` along with beacons and
patrol progress. The saved count is bounded to 999; no live Node references are
stored in save files.

### Constraints and tests

This is a local single-player gameplay service, not multiplayer-authoritative
interaction, quest scripting, sophisticated object tagging, large-scale
inventory, or a full Unreal Gameplay Ability System. The example uses a
3.5m maximum query distance and updates focus at most approximately every
0.12s. Provider activation always rechecks real player distance. If enabling
occlusion, make sure interaction target colliders and the collision mask are
configured correctly.

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -q
godot --headless --path . --script res://tests/test_world_interaction.gd
godot --headless --path . --script res://tests/test_world_interaction_runtime.gd
```

**33/33 local static/package tests pass.** The two new Godot suites exercise
selection and out-of-range rejection, then an integrated streamed beacon,
NPC conversation, unload-time focus invalidation and shard collection. Actual
GDScript parsing, physics/world rendering and macOS Metal runtime behavior are
**not yet verified** because no working Godot binary is available locally
and the GitHub CI workflow remains pending/queued.

References: [Godot scene-tree groups](https://docs.godotengine.org/en/stable/tutorials/scripting/groups.html), [Godot 3D ray-casting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html), [Unreal Gameplay Framework](https://dev.epicgames.com/documentation/unreal-engine/gameplay-framework-in-unreal-engine).


## Visual Quality Lab v15 — persistent inventory, item recipes and equippable light

This release extends the demo's reusable **GDScript game/engine services**, not
Godot's core C++ renderer. Its item definitions and recipes are maintained by
`VisualItemCatalog` (`addons/visual_quality/item_catalog.gd`); item stacks,
source-unique rewards, save/load and atomic recipe mutations are managed by
`WorldInventory3D` (`addons/visual_quality/inventory_component.gd`). These are
reusable nodes/classes that do not reference the demo's player or world cells.

**Game integration:** collecting quest light shards now rewards `light_shard`;
activating a streamed beacon rewards a `forest_essence`. Source keys such as
`quest:<seed>:<index>` and `beacon:<x>:<z>` prevent a reward from being granted
again after a level reload, a beacon-state reset or a quest replay. On first
use of v15, the demo migrates already-collected shards and activated beacons
from v6–v14 save files. Claims remain recorded even when resources are spent.

**Controls:** press **I** to open/close the centered inventory panel. Press
**C** (or click the recipe button) to create an `spark_core` from **2 light
shards**. Press **J** to create a unique `forest_lantern` from **1 spark core +
2 forest essences**. Press **T** to equip/unequip its warm, player-carried
OmniLight3D, useful during night exploration. The light is intentionally
shadow-free to keep rendering cost modest. Existing H contextual interactions,
F pickup, G beacon activation, NPCs, world streaming and atmosphere controls
continue to function. Players can collect light shards even before opening the
inventory UI.

**Persistence and protections:** inventory files are versioned and tied to a
world ID, saved with Godot `ConfigFile` to `user://` through temporary-file
replacement. Inventory changes roll back in memory if saving fails. Only
registered item IDs and positive, bounded counts are accepted when loading.
Crafting checks every ingredient and output capacity **before consuming
anything**. Receipts (up to 8,192) are also saved and prohibit duplicate
rewards; counts are capped at 99/99/20/1 for shards/essence/cores/lanterns.
The inventory exposes signals, copies of its state, pure recipe simulation,
and methods to add, remove, craft and claim one-time rewards.

The world/beacon and quest save files are separate from the inventory file;
**there is no distributed transaction across those files**. On startup, the
demo reconciles committed world and quest progress using stable source IDs.
This is a single-player prototype, not a network-authoritative inventory,
large-scale item database, trading system, or equipment animation pipeline.
Quest replay/reset does **not** allow farming the same rewards indefinitely.

**Verification:** Python packaging/static regression suite **37/37 passed**;
Godot runtime tests below were added to CI but have *not* been executed in
this environment (the local Godot binary and authorized Mac are unavailable,
while GitHub Actions still has no confirmed passing run):

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_inventory_component.gd
godot --headless --path . --script res://tests/test_inventory_crafting.gd
godot --headless --path . --script res://tests/test_inventory_persistence.gd
godot --headless --path . --script res://tests/test_inventory_gameplay.gd
```

References: [Godot save-game guidance](https://docs.godotengine.org/en/4.6/tutorials/io/saving_games.html), [ConfigFile](https://docs.godotengine.org/en/4.6/classes/class_configfile.html), [OmniLight3D](https://docs.godotengine.org/en/4.6/classes/class_omnilight3d.html).


## Visual Quality Lab v16 — attributes, equipment and timed abilities

This version extends the reusable **GDScript engine addon** and immediately
connects it to the playable open-world demo. Two new components are inspired by
the concepts of Unreal Gameplay Ability System (GAS), not GAS itself:

- `addons/visual_quality/attribute_component.gd` (`WorldAttributes3D`):
  four stats (max health, max stamina, movement multiplier, stamina regeneration),
  equipment and timed modifiers, finite-value validation, capped vitals, effect
  expiry and signals. Sprint now spends stamina only while moving; stamina
  regenerates after a configurable delay since its last consumption.
- `addons/visual_quality/ability_component.gd` (`WorldAbilitySystem3D`):
  reusable action definitions with stamina costs, cooldowns and timed effects.
  **X Dash** adds +0.85 movement multiplier for 0.65 seconds, costs 30 stamina,
  and has a three-second cooldown. **Z Focus** adds +25 stamina regeneration
  for five seconds, costs 10 stamina and has a 12-second cooldown. The ability
  cannot activate if dead, on cooldown, or low on stamina.

### Equipment and game integration

The existing `WorldInventory3D` now saves equipped slots within the **same
version-1 ConfigFile** as the inventory and one-time reward claims. It validates
item ownership and slot identity during load; absent `equipped` (older v15
saves) is treated as an empty equipment set. Removal or crafting that consumes
an equipped item automatically clears the slot. Failed saves roll back in
memory, including equipment choices.

The **forest lantern** now fills the utility slot and grants **+20 max
stamina** when equipped, alongside its existing warm light. **T** equips and
toggles the light. The new **trail boots** fill the feet slot and increase
movement speed by **25%**. Craft boots using **1 light shard and 2 forest
essences** with **U**, and equip/unequip with **Y**. Inventory buttons also
provide these actions. **I** opens the inventory. The live HUD now shows HP,
stamina, movement multiplier, Dash cooldown and Focus cooldown.

Previous demo features (streamed 49-cell world, persistent beacons, patrol NPCs,
quest rewards, H interactions, day/night/weather, graphics tiers, CPU governor,
world profiling) are retained.

### Validation and limitations

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_attributes.gd
godot --headless --path . --script res://tests/test_abilities.gd
godot --headless --path . --script res://tests/test_equipment.gd
godot --headless --path . --script res://tests/test_equipment_persistence.gd
```

**41/41 Python static/package checks pass locally.** The four new Godot
headless test suites (attributes/effects/stamina; ability costs/cooldowns;
equipment ownership and auto-unequip; persistence and v15 compatibility)
are included in CI but **have not run in Godot locally** because no executable
is installed and CI has not yet completed. Apple Silicon/Metal performance
remains unverified.

This change is a **portable GDScript engine extension and playable demo** inside
`misc/visual_quality_lab`. It does not modify the Godot C++ engine core, nor
the separate inaccessible local game. It does not provide multiplayer authority,
prediction, animation tasks or attribute replication.

Documentation:
- https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-ability-system-for-unreal-engine


## Visual Quality Lab v17 — combat components, enemy state and streamed combat gameplay

The **engine addon** now exposes three reusable GDScript systems and the
**playable demo uses all three immediately**. The architecture follows the
attribute/effect separation used by Unreal's Gameplay Ability System and
Godot's composition-oriented scenes, but does not attempt to replicate GAS.

### Reusable gameplay/engine components

- `addons/visual_quality/combat_component.gd` —
  **`WorldCombatant3D`**: faction filtering (player/hostile/neutral), finite
  damage validation, bounded physical armor mitigation
  (`damage * 100 / (100 + armor)`), brief post-hit immunity, stun with expiry,
  damage/defeat/status signals, and a single defeat event per life. Restore
  saved health/stun without replaying defeat rewards.
- `addons/visual_quality/hostile_sentry.gd` —
  **`WorldHostileSentry3D`**: distinct from existing friendly patrol NPCs.
  Each streamed cell contains a red physical sentry that attacks nearby
  players at most every 1.7 seconds for nominal 9 damage, can be stunned
  (purple), and turns dark/loses collision on defeat. It suspends its AI and
  combat status ticking when its cell is put to sleep by the existing interest
  manager. Exports primitive `sentry_health` and `sentry_stun` state.
- `addons/visual_quality/combat_controller.gd` —
  **`WorldCombatDirector3D`**: attacks only loaded hostile actors found by
  bounded nearby cell lookups. Stable deterministic camera-facing target
  choice, target caps and stamina/cooldown enforcement. Unlike a whole-world
  actor scan, it does not retain streamed nodes across commands.

### Integrated gameplay

- **M**: strike the living hostile in front of the camera within 4m.
  Nominal 36 damage, 12 stamina, 0.55s cooldown.
- **N**: stun shockwave within 5.5m, up to 8 enemies, nominal 18 damage +
  2.5s stun; 35 stamina and 7s cooldown.
- **Backspace**: respawn after player defeat; restores HP/stamina and the
  spawn position, leaving the world and inventory intact. Dead players cannot
  move until they respawn.
- Defeated sentries yield **one forest essence** per distinct cell through
  the existing `WorldInventory3D.grant_once("sentry:x:z", ...)` logic, so
  unloaded/recreated or reset actors cannot be farmed indefinitely.
- The cell's saved state now includes damaged/defeated sentry health and
  remaining stun duration. Returning to a cell restores the enemy's state.
  The previous global reset-world-cells control intentionally resets enemy
  health as well as other cell state. The HUD shows combat feedback and a
  **current-session** defeat count. Existing movement, crafting, NPC dialogue,
  environment, streaming and profiler controls are preserved.

### Validation

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -q
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/test_combat_component.gd
godot --headless --path . --script res://tests/test_combat_selection.gd
godot --headless --path . --script res://tests/test_hostile_sentry.gd
godot --headless --path . --script res://tests/test_combat_streaming_runtime.gd
```

**45/45 local Python static/package checks pass.** These four new GDScript
suites cover armor/team immunity, stun, one-time death, bounded targeting,
physical sentry behavior, defeat loot, and streamed save/unload/rehydration.
They are added to the Godot CI job but actual Godot execution, rendered
gameplay and Apple Metal performance are **not verified** while the local
Godot binary and connected Mac remain unavailable and CI stays queued.

**Limitations:** this is a local single-player prototype. Combat attacks test
angle and range, **not line-of-sight**; walls do not block the abstract hit
calculation yet. Hostile sentries are stationary proximity attackers, not
navmesh-driven combat agents. Player health is reset on restart, while enemy
cell health is persisted. There is no authoritative multiplayer, prediction,
animation combat pipeline or C++ engine core modification. Only the addon and
demo at `misc/visual_quality_lab` were changed, not a separate inaccessible
local game.

References:
- https://docs.godotengine.org/en/4.6/getting_started/first_3d_game/07.killing_player.html
- https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-effects-for-the-gameplay-ability-system-in-unreal-engine
