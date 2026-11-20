# Native World Partition (experimental)

This optional built-in 3D module introduces `WorldPartition3D`, an X/Z-grid scene streamer. It is the **runtime foundation** for larger terrain/foliage/HLOD workflows, not a finished replacement for Unreal World Partition.

## What works

- Register a sparse mapping from `Vector2i` cell coordinates to local `PackedScene` resource paths (saved with your `.tscn` scene).
- Choose a `Node3D` observer, cell size, and square loading/unloading radii; negative coordinates are handled with floor division.
- Load scene resources asynchronously using Godot's `ResourceLoader.load_threaded_request` backend and poll without blocking while still in progress.
- Share a resource-load request between cells using the same scene path.
- Instantiate `Node3D` cell roots on the main thread, preserving their authored transform and applying the cell origin.
- Cap new requests, simultaneous outstanding requests, and instantiation work per frame.
- Unload distant cells, apply hysteresis, emit load/unload signals, and keep explicit APIs for moving/replacing/removing cells.
- Runtime diagnostics: `get_pending_cell_count()`, `get_inflight_request_count()` (deduplicated resource paths), and `get_failed_cell_count()` for HUDs and performance tools.
- **Physics-frame scene activation fence:** every instantiated cell records its creation physics frame. `min_physics_frames_after_load` (0–8, default 2) delays an additional **activation** state. An optional root method `is_streaming_activation_ready() -> bool` can veto activation until game-specific collision/navmesh/terrain setup is complete. Query `is_cell_activation_ready(cell)`, `is_streaming_source_activation_ready(name)`, source activated-cell counts, and activation progress separately from loaded scene roots; unloading/reloading always resets the fence.
- **Independent bounded simulation activation:** loaded cells can retain visuals but pause script/AI simulation independently of LOD. Configure `simulation_radius` (-1 disables), `simulation_hysteresis_cells` (0–8) and `max_simulation_transitions_per_frame` (1–64). The native engine tracks per-cell activation, exposes `is_cell_simulation_active()` and `get_simulation_active_cell_count()`, emits `cell_simulation_changed`, and calls an optional scene-root `set_streaming_simulation_active(active)` **before** `_ready()` for initial state.
- **Prioritized streaming sources:** runtime names carry priorities 0–3 (background, normal, important, urgent); after player and persistent hubs the native scheduler works high to low and alphabetical within each tier, all under existing instance/new-request budgets. Fast-travel scenes can finish before background quest preloads without competing for observer priority. Update a source via `set_streaming_source_priority()`.
- **Nonblocking streaming-source completion:** `get_streaming_source_cell_count`, `get_streaming_source_loaded_cell_count`, `get_streaming_source_failed_cell_count`, `get_streaming_source_progress` and `is_streaming_source_ready` expose bounded readiness for already-registered destination cells. Unregistered/missing source centers fail closed, and ready requires a valid active observer and all relevant `Node3D` roots to be live.
- **Live scene-root accessor:** `get_cell_instance(cell)` returns the active Node3D scene root or `null` without scanning all children or requesting a load. Useful for gameplay population, navigation and cell-local scripts. Never cache the returned scene root beyond an unload without `is_instance_valid()`.
- **Extra mission streaming sources:** up to 8 named world-space locations with radius 0 or 1 can stream quest areas, cinematic viewpoints or teleport destinations independently of the player's grid location. They share the existing threaded asset and instantiation budgets and are removed explicitly when no longer needed.
- **Asymmetric LOD hysteresis:** keep an already detailed cell in full quality for 0–8 extra cell rings, while promotions still happen only at the inner threshold; suppresses rebuild thrashing when observers change grid cells.
- **Opt-in cell detail LOD:** scene roots implementing `set_streaming_lod(level)` receive 0 inside the full-detail radius (or when pinned) and 1 in distant loaded cells. The engine sets the tier *before* the root's `_ready()` and updates existing cells under a per-frame transition budget. The game supplies simpler distant graphics and disables distant physics itself.
- **Bounded motion prefetch:** optional world-space velocity input projects the observer up to 5 seconds / 128 world units ahead and attempts to load one future cell, after immediate-radius cells and pinned hubs. It uses the same async resource cache and per-frame budgets and releases no-longer-relevant speculative scenes.
- **Persistent hub pins:** `pin_cell(cell)`/`unpin_cell(cell)` keep registered camps and quest hubs resident outside the observer's unload radius. At most 128 cells may be pinned to bound intentional scene retention; pinned cells still use normal async load and instantiation budgets.
- **Observer grid events:** `has_observer_cell()`, `get_observer_cell()` and `observer_cell_changed(cell)` help gameplay react to crossing streaming cell boundaries without polling player coordinates. The first successful observer lookup emits this signal, as does a subsequent cell-size or observer-path change.
- Avoid running streaming implicitly in the editor.

## Using the node

Build Godot with the `world_partition` module enabled (it is available when 3D is enabled). In a 3D scene, create a `WorldPartition3D` node with a sibling `Player` node. Set `observer_path` to the player. Register a scene per cell either in the inspector dictionary or in script:

```gdscript
@onready var world: WorldPartition3D = $WorldPartition3D

func _ready() -> void:
    world.cell_size = 128.0
    world.load_radius = 1
    world.unload_radius = 2
    world.max_new_requests_per_frame = 2
    world.max_instances_per_frame = 2
    world.observer_path = world.get_path_to($Player)
    world.set_cell_scene(Vector2i(0, 0), "res://world/0_0.tscn")
    world.set_cell_scene(Vector2i(-1, 0), "res://world/-1_0.tscn")
    world.pin_cell(Vector2i(0, 0)) # Home base persists while exploring
    world.predictive_lookahead_seconds = 2.0
    world.predictive_max_distance = 32.0
    world.set_streaming_source("quest", $Relic.global_position, 0)
    world.detail_radius = 1 # Keep high detail within one cell from the observer
    world.detail_hysteresis_cells = 1 # Demote when farther than two rings
    world.max_detail_transitions_per_frame = 2

func _physics_process(_delta: float) -> void:
    # Supply world-space movement velocity, in world units per second.
    world.predictive_velocity = $Player.velocity
```

Each `.tscn` cell must have a `Node3D` root. The authored origin is relative to its cell: cell `(-1, 0)` starts at local `(-128, 0, 0)` with default cell size. The observer is transformed into the world partition node's local space, so moving/rotating the WorldPartition3D node works.

## Independent AI/script simulation tiers

`simulation_radius` is separate from `detail_radius` and `load_radius`. A cell can be **loaded** (rendering its distant mesh), have full or reduced **LOD**, and independently be **simulation-active** for AI and script effects. Setting `simulation_radius = -1` (default) preserves existing behavior. When enabled, the observer's inner radius activates simulation; an already-active cell keeps running for `simulation_hysteresis_cells` extra grid rings to avoid repeated start/stop as the player crosses a boundary. A pinned gameplay hub always stays active. Per-frame activations/deactivations of existing roots are capped by `max_simulation_transitions_per_frame`; the initial state is assigned when the cell is instantiated.

The native map is usable from game managers even when the cell has no script callback:

```gdscript
world.simulation_radius = 1
world.simulation_hysteresis_cells = 1
world.max_simulation_transitions_per_frame = 2

func _on_cell_simulation_changed(cell: Vector2i, active: bool) -> void:
    if world.get_cell_instance(cell) != null:
        encounter_director.set_cell_ai_enabled(cell, active)
```

An opted-in cell root can implement:

```gdscript
var streaming_simulation_active := true

func set_streaming_simulation_active(active: bool) -> void:
    streaming_simulation_active = active
    if is_node_ready():
        set_process(active)
```

Game code **must actually stop its own processes, animation updates, AI controllers or costly gameplay tasks**. `WorldPartition3D` publishes the state and calls the opt-in callback, but does **not** automatically disable collision shapes or `Node.process_mode` for arbitrary scene hierarchies, to avoid breaking rendering, static terrain or input. Visual LOD toggles do not activate distant AI. Call `get_simulation_active_cell_count()` for diagnostics, `is_cell_simulation_active(cell)` to gate NPC creation. The playable integration lives in `forest_encounters.gd` and `streamed_forest_cell.gd` with `smoke_simulation.gd` verifying near activation, retained geometry, hysteresis, pinned cells and budgeted transitions.

## Physics-frame and scene-defined activation fences

Scene instantiation only means the root is alive, **not** that every physics or navigation system is safe to use. `WorldPartition3D` now tracks each cell's creation frame using Godot `Engine.get_physics_frames()`. With `min_physics_frames_after_load=2` (default), the engine waits until at least two physics ticks have elapsed since a cell was added to the scene tree. This count is reset after unloading and reinstantiating a cell.

To permit scene-specific gameplay readiness, a scene root may implement a **side-effect-free** function:

```gdscript
func is_streaming_activation_ready() -> bool:
    # Example only: replace with actual collision/navmesh/actor-init conditions.
    return is_node_ready() and custom_collision_initialized
```

The scene root is ready only when both its physics-tick delay and optional predicate succeed. Invalid predicate return types fail closed; scenes without this method use the frame barrier alone. All checks are on the main thread and don't call blocking resource loading:

```gdscript
world.min_physics_frames_after_load = 2
if world.set_streaming_source("portal", destination_global, 0, 3):
    # In _process(), after verifying the destination cell is registered:
    if world.get_streaming_source_failed_cell_count("portal") > 0:
        cancel_portal()
    elif world.is_streaming_source_activation_ready("portal"):
        perform_travel_to_known_safe_spawn()
    else:
        print(world.get_streaming_source_activated_cell_count("portal"))
        print(world.get_streaming_source_activation_progress("portal"))
```

These methods complement the older `is_streaming_source_ready`, which only checks instantiated scene roots. **They are not physics-server synchronization, collision-shape bake, navigation bake or GPU-residency guarantees.** The game must validate its spawn position and its own content dependencies. Do not put expensive work in `is_streaming_activation_ready()`: it is polled repeatedly for every relevant cell until ready. Up to eight source names, each at radius 0 or 1, ensure bounded iteration. `smoke_activation_fence.gd` tests real threaded scene loading, the physics delay, manual predicate gating, retargeting and cleanup.

## Asynchronous source readiness and safe fast travel

A streaming source is **not** ready simply because it was registered or its resource request started. Query the native loaded-scene counters to gate camera switches, quest portals or fast travel without blocking the main thread:

```gdscript
# The target cell must already be registered in cell_scenes.
if world.set_streaming_source("fast_travel", destination.global_position, 0):
    var scene_count := world.get_streaming_source_cell_count("fast_travel")
    if scene_count == 0:
        world.remove_streaming_source("fast_travel")
    else:
        # In _process(), do not busy-wait or call load_threaded_get().
        if world.get_streaming_source_failed_cell_count("fast_travel") > 0:
            cancel_travel() # Gameplay-owned action, includes source removal.
        elif world.is_streaming_source_ready("fast_travel"):
            finish_travel() # Gameplay-owned movement to the destination.
        else:
            print(world.get_streaming_source_progress("fast_travel"))
```

The readiness contract is **live instantiated scene roots**, not byte-level resource loading, GPU texture readiness, navmesh baking, full physics synchronization or safe-spawn validation. Sparse source radius neighbors with no registered scene are ignored; the **center** must be registered or `is_streaming_source_ready` stays false. A nonexistent source or disabled streamer is never considered ready. Remote source requests still compete for the original request and instantiation frame budgets. Always implement failure/cancellation and a timeout in gameplay. The complete usage and headless regression are at `misc/cgame_forest_showcase/scripts/streaming_travel.gd` and `tests/smoke_travel.gd`.

## Live cell roots for gameplay

`get_cell_instance(cell: Vector2i) -> Node3D` gives the currently loaded scene root (or `null`) from the native ObjectID map. Use it in gameplay orchestration:

```gdscript
func _on_cell_loaded(cell: Vector2i) -> void:
    var root: Node3D = world.get_cell_instance(cell)
    if root != null and not root.is_queued_for_deletion():
        spawn_cell_encounters(root, cell) # Implemented in the game.
```

The native method does not load new cells, change streaming budgets or transfer node ownership. The returned instance belongs to `WorldPartition3D` and can disappear when the region unloads, the scene is replaced, or the node is externally freed. Use `cell_unloaded(cell)` for cleanup, and avoid holding a raw pointer beyond the streaming lifecycle. The Aurora Forest `forest_encounters.gd` sample demonstrates this with a maximum of five near-field NPCs, and the existing native prediction integration test now asserts loaded/unloaded lookup semantics.

## Additional quest and camera sources

`set_streaming_source(name, global_position, radius = 0)` registers or updates a named source in **global coordinates**. Each source requests existing registered cells within radius 0 or 1; the implementation limits the registry to 8 names. An existing source can be updated even when that limit is reached. Game code can explicitly clean up a finished objective:

```gdscript
world.set_streaming_source("quest", $Objective.global_position, 0, 0)
print(world.get_streaming_source_count(), world.get_streaming_source_cell("quest"))
world.remove_streaming_source("quest")
# Or world.clear_streaming_sources() when changing maps.
```

Normal observer cells are loaded first, then pinned hubs, then extra sources with priorities **3 → 2 → 1 → 0**, then optional velocity prefetch. Each tier is ordered alphabetically by source name; a lower-named background source cannot block an urgent destination. The `priority` parameter is optional and defaults to 1, so existing 3-argument calls keep their original normal behavior. An update with an omitted priority resets that source to 1; use `set_streaming_source_priority(name, priority)` to change only priority, or `get_streaming_source_priority(name)` to query it (unknown source returns -1). Every source uses the existing asynchronous request and instantiation budgets. **Priority never cancels or preempts an already-running threaded `ResourceLoader` request**: it controls new cell requests and instance slots when they compete for a budget. Pinned hubs and near-player cells remain strictly ahead of extra sources; if the player needs every budget slot, even urgent travel waits. Realistic tests must use distinct pending cell instances with a budget of one. Removed or moved sources release their old cells (after the short one-cell unload margin), unless still required by the observer or another source. This only streams **already registered** `PackedScene` cells; sources do not author new geometry. A valid observer is still required. Sources are runtime state and must be restored by gameplay. Run `misc/cgame_forest_showcase/tests/smoke_sources.gd` for end-to-end coverage and `misc/cgame_forest_showcase/tests/smoke_source_priorities.gd` to verify priority order against an actual one-instance-per-frame budget.

## Scene detail callback (optional)

A cell scene can opt in to budgeted near/far streaming detail:

```gdscript
extends Node3D
var streaming_lod: int = 0

func set_streaming_lod(level: int) -> void:
    if streaming_lod == level:
        return
    streaming_lod = level
    if is_node_ready():
        rebuild_visuals_and_collisions() # A project-defined helper.

func _ready() -> void:
    rebuild_visuals_and_collisions()
```

The native streamer calls this method **before** attaching new roots, so their `_ready()` can create only the desired detail. Existing cells receive level 0 when near or pinned, and level 1 when distant. Set `detail_radius = -1` to disable and restore full detail under the configured per-frame transition budget. To avoid costly back-and-forth rebuilds near cell boundaries, set `detail_hysteresis_cells = 1` (valid 0..8): an already-detailed scene remains near-quality for one additional ring while a distant scene upgrades only on entering the original `detail_radius`. New cells receive their initial tier without hysteresis, and pinned hubs always retain full detail. The default zero preserves existing behavior. Diagnostics: `get_cell_detail_level(cell)` (0 near, 1 distant, -1 absent/unsupported), `get_distant_cell_count()` and `cell_detail_changed(cell, detail_level)`.

This is a *two-tier cell-content callback*, not automatic mesh decimation, full HLOD baking or Nanite. The game must maintain collision/navmesh behavior during level switches. See `misc/cgame_forest_showcase/tests/smoke_lod.gd` for a near/far scene regression.

## Inspecting streaming load

```gdscript
# Poll sparingly (for example 4 Hz), not necessarily every render frame.
var loaded := world.get_loaded_cell_count()
var queued := world.get_pending_cell_count()
var requests := world.get_inflight_request_count()
var failed := world.get_failed_cell_count()
```

Use `world.has_predicted_cell()` and `world.get_predicted_cell()` to display the next potential grid coordinate (whether or not a scene is registered). Setting `predictive_lookahead_seconds` to zero disables prefetch. The supplied velocity is finite-checked and capped to 512 units/second; prediction is off by default, never supersedes normal loading priority and does not automatically query a physics node.

For persistent hubs use `world.get_pinned_cell_count()` and `world.get_pinned_cells()`; call `world.unpin_cell(cell)` before leaving a hub permanently. Pins are runtime state, must be re-established after loading a save, and are cleared when their scene registration is removed. Disabling streaming unloads even pinned scenes, but keeps their pin registrations for re-enabling.

These counters describe the current state, not a prediction of future memory or throughput. One background resource request may serve multiple pending cells with the same PackedScene path. See `misc/cgame_forest_showcase` for a playable, deterministic 16-cell demonstration and headless reload test.

## Tests

The module includes 66 Doctest cases across `test_world_partition_3d.h` (30) and `test_world_partition_3d_extra.h` (36), including disk-backed scenes, origin-offset checks, load/unload hysteresis, duplicate mappings and overflow guards, shared resource requests, and cleanup of failed/pending ResourceLoader tokens. Tests are picked up by Godot's generated module-test list.

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[WorldPartition3D]*"
```

**Validation status:** Source changes and test cases are present, but a Godot binary/compiler toolchain capable of building this fork was not available to the authoring environment. CI build and test execution must pass before treating the module as production-ready.

## Non-goals and limitations

- **Scene activation is a gameplay fence, not an engine-wide physics promise.** The physics frame counter establishes a minimum age. Only a scene author's opt-in predicate can verify domain-specific readiness; a bug or omission in it cannot be detected by the engine. Streaming and physics activation remain decoupled from any GPU upload/texture residency.
- **Simulation activation is opt-in per scene or game manager.** It never unloads geometry, removes physics bodies, or pauses arbitrary descendant scripts automatically. Callback scripts must tolerate calls before `_ready()` and execute their own activation logic. Hysteresis can intentionally keep some neighboring cells active even when outside the inner radius.
- **Readiness is not an all-systems fence.** A `true` completion result means the relevant PackedScene roots exist in the live scene tree, not that they finished deferred physics initialization, navigation baking or GPU uploads. Games that stream collision/terrain separately must add their own activation checks.
- **External source fanout is bounded:** at most 8 sources and radius 1; no custom shapes, priorities, source replication or automatic quest area generation. Additional source load requests can be delayed by high-priority camera/player work.
- **Distance LOD hysteresis:** independently adjust the demotion boundary with `detail_hysteresis_cells`. It only changes levels of already-instantiated roots and does not increase the resource streaming radius; check that existing full-detail collision in the added ring is affordable.
- **Distance LOD is opt-in.** Cell roots without `set_streaming_lod()` continue unchanged. The transition budget applies only to *existing loaded* cells, not their initial scene instantiation; scene authors must profile CPU spikes and physically remove/recreate colliders safely.
- **Prediction is opportunistic, not a guaranteed load.** At most one additional grid cell is preloaded. Moving abruptly, changing direction or teleporting can invalidate a forecast; normal observer-radius loading handles these cases. No prefetch cones, priority queues or automatic navmesh/collision warmup are provided.
- **No automatic editor bake/partition yet.** Split source scenes and save each cell manually. Automated authoring and terrain/HLOD export are future integrations.
- **No terrain sculpting, painting or foliage authoring in this module.** They can output regular cell `PackedScene` resources.
- **No cancellation primitive for a running ResourceLoader request.** Moving the observer drops obsolete pending instances; the running resource request finishes and is then discarded.
- **No per-cell physics/navmesh warmup guarantees or server-style streaming replication.** Instances use the regular scene tree.
- **Not virtual geometry, Nanite or texture streaming.** Those require separate rendering systems.
- Cell scenes are currently addressed by full resource path; remapping paths during asset moves must be handled by tooling.
- Errors from missing/corrupt scene resources are logged and the cell is not repeatedly re-requested until its registration/configuration changes.

## Dependencies for subsequent open-world work

1. **Terrain resource + height editing + texture layers (#1, #2, #7):** authoring scene chunks and collision resources.
2. **Foliage + procedural vegetation (#3, #10):** cell-aware procedural placement and instanced rendering.
3. **PCG graph (#4, #38):** reusable dependency-aware node graph for generating terrain cells and biomes.
4. **Automated scene partitioning (#5, this module):** editor bake of selected spatial nodes into scene resources with stable IDs and ownership.
5. **HLOD and streaming diagnostics (#6, #18, #19):** merge/decimate distant content, profile memory and frame time.
6. **Water and atmosphere (#8, #9):** optional streaming-aware world layers.

Treat each as an independent change with unit tests, import tests, stress tests and platform CI before merging. 
