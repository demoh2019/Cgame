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
- **Selective bounded LRU route cache:** `find_cell_path()` now caches shortest cardinal routes **and empty results**, up to `max_cell_path_cache_entries` (0–128, default 64). Exact endpoint/loaded-only keys, defensive Array copying, deterministic LRU eviction and cache hit/miss diagnostics avoid redundant breadth-first searches for repeated quest HUD and region routing queries. Registration edits invalidate both kinds; live scene load/unload only invalidates loaded-only entries, preserving non-live route caches when the camera moves.
- **Deterministic bounded cross-cell routing:** `find_cell_path(from, to, loaded_only=false)` returns the shortest cardinal corridor of registered `Vector2i` world cells, respecting missing topology and optionally restricting the route to already-instantiated scene roots. Synchronous breadth-first expansion is capped at 512 visited cells (overflow-safe 32-bit coordinates) to prevent runaway CPU. This complements, but does not replace, a baked navigation mesh or obstacle-safe surface paths.
- **Immutable partial NavMesh obstacle updates:** `patch_navigation_tile(previous, resolution, previous_blockers, blockers, agent_radius, max_slope_degrees)` compares old/new circular footprints, including duplicates and reordering, and re-tests only grid triangles intersecting changed blocker influence. Unaffected triangles reuse the old walkability mask; exact polygon indices/order match a fresh full build, and unchanged footprint sets return the same cached NavigationMesh. `get_last_navigation_tile_retested_triangle_count()` quantifies geometric work (512 full tests on a 16×16 tile versus a small local subset for a barricade). Invalid topology safely falls back to a full build.
- **Native bounded dynamic NavMesh dirty scheduler:** `mark_cell_navigation_dirty(cell)` coalesces repeated edits for live opted-in cells and dispatches `rebuild_streaming_navigation_mesh() -> bool` under `max_navigation_rebuilds_per_physics_frame` (1–16, default 1). Uses nearest-first deterministic ordering, max 128 queued cells, no duplicate rebuild grants per physics frame, a two-tick readiness fence and `cell_navigation_mesh_rebuilt` signal. Per-cell revisions and a monotonic world NavMesh generation invalidate stale NPC paths on changes.
- **Native slope- and obstacle-aware navigation tile generation:** `build_navigation_tile(vertices, resolution, blockers, agent_radius, max_slope_degrees)` builds deterministic walkable NavigationMesh triangles from sampled terrain, rejects excessive slopes and intersects full triangles against circular obstacle footprints expanded by NPC radius. Hard limits: 2..32 cells per tile axis, at most 256 blockers, 2048 triangles, finite positions, validated radii and slope. No Recast bake or implicit physics-server mutation.
- **Independent streamed NavigationRegion3D tier:** `navigation_radius` (-1 all loaded active/default, 0–32 near observer), `navigation_hysteresis_cells` (0–8), `max_navigation_transitions_per_frame` (1–64), native `cell_navigation_changed` signal, ready and count APIs. Pinned hubs and important/urgent sources can activate navigation outside player radius. Optional scene callback `set_streaming_navigation_active(active)` enables actual authored NavigationRegion3D tiles; `is_streaming_navigation_ready()` reports their state after two physics-frame sync ticks.
- **Native fixed-physics-frame navigation scheduler:** register up to 128 live Node3D agents, give them priority 0–3, and cap costly path/steering **recalculations** at `max_navigation_updates_per_physics_frame` (1–64, default 2). The engine chooses winners deterministically by priority, least recent update, then agent name, avoiding starvation among equally important active NPCs. Only loaded simulation-active physics-active cells qualify. Grants are consumed once per agent per physics tick and weak ObjectIDs protect against deleted agents; owner-safe unregister prevents stale NPC replacement bugs. Aurora Forest uses these grants to schedule real obstacle raycasts; this is not navmesh baking.
- **Independent native physics streaming tier:** per-cell `physics_radius` (-1 all-loaded legacy), `physics_hysteresis_cells` (0–8) and `max_physics_transitions_per_frame` (1–64). Loaded visuals and AI simulation stay separate. An opt-in root `set_streaming_physics_active(active)` filters its authored colliders; `cell_physics_changed`, `is_cell_physics_active()`, `get_physics_active_cell_count()` expose state. Important/urgent streaming sources and pinned hubs force destination cells to full visual LOD and active physics, while background quest preload remains cheap. `is_streaming_source_physics_ready(name)` requires an additional physics tick and optional scene predicate before travel.
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

## Bounded cached cell routing and selective invalidation

Repeated `WorldPartition3D.find_cell_path(from, to, loaded_only=false)` queries now reuse a **bounded native LRU route cache** rather than rerunning up to 512-cell breadth-first searches for unchanged endpoints. The cache key preserves both complete signed `Vector2i` endpoint coordinates and the `loaded_only` option; no lossy hash of grid positions or reversed-path approximation is used. The default size is 64 routes per world, adjustable from 0 (disabled) to 128. Results include empty/unreachable paths, since repeatedly searching an unchanged disconnected corridor is wasteful.

```gdscript
world.max_cell_path_cache_entries = 64
var route: Array = world.find_cell_path(start_cell, quest_cell)
# Quest HUD can call this repeatedly while player stays in the same cell:
var same_route: Array = world.find_cell_path(start_cell, quest_cell)
print("Cache hits/misses/entries: ",
    world.get_cell_path_cache_hit_count(), "/",
    world.get_cell_path_cache_miss_count(), "/",
    world.get_cell_path_cache_entry_count())
world.clear_cell_path_cache() # Also resets diagnostic counters.
```

Eviction is least-recently-used, with stable key tie-breaking. Every result returned to GDScript is an **independent Array**: appending/removing/editing a route cannot poison the internal cached path. Registration topology changes through `set_cell_scene(s)`, `remove_cell_scene` or `clear_cell_scenes` invalidate **all** cached routes. Ordinary scene loading/unloading invalidates **only loaded-only routes** and leaves registered-topology paths cached, so moving the observer does not cause unnecessary quest pathfinding. A cached positive loaded-only route also rechecks its live roots before reuse, catching roots independently queued for deletion. The cache does not mistake a visually registered cell for a walkable NavMesh and does not cache `NavigationServer3D.map_get_path()` answers. NavMesh obstacle edits do not change the registered-cell graph and therefore need not invalidate this high-level cache; those changes already update the separate native `navigation_mesh_generation` used by NPCs.

`get_cell_path_cache_hit_count()` and `get_cell_path_cache_miss_count()` are cumulative, saturating signed-32-bit counters. Capacity changes discard entries, and `clear_cell_path_cache()` explicitly resets entries and metrics. `smoke_cell_route_cache.gd` tests actual forest loading, reuse, copy isolation, selective unload invalidation and invalidation of negative routes; the native Doctest covers LRU order, disabled cache, invalid cache size and graph changes. This is main-thread request coalescing **not** async pathfinding.

## Safe registered-cell routing

`WorldPartition3D.find_cell_path(from, to, loaded_only=false)` returns a deterministic shortest sequence of adjacent configured cells, from start through destination. Each step moves one X/Z cell (no diagonal corner-cutting); disconnected gaps are avoided. It is useful for streaming-area quest arrows, broad NPC region plans, and detecting disconnected world topology.

```gdscript
var origin_cell: Vector2i = world.local_position_to_cell(world.to_local(player.global_position))
var target_cell: Vector2i = world.local_position_to_cell(world.to_local(quest.global_position))
var route: Array = world.find_cell_path(origin_cell, target_cell)
if route.size() > 2:
    var next_cell: Vector2i = route[1]
    var next_local: Vector3 = world.cell_to_local_position(next_cell)
    print("Next streaming region: ", next_cell, " origin=", next_local)

# Require a continuous corridor of already-instantiated cell scenes:
var safe_loaded_corridor: Array = world.find_cell_path(origin_cell, target_cell, true)
```

The search checks only registered scene paths, **not** terrain collisions, slope, water, NavMesh edges or active navigation region connectivity. `loaded_only=true` additionally requires each route cell to have a live instantiated root; it is still not a gameplay/physics-ready guarantee. To prevent unbounded CPU spikes, breadth-first search is capped at 512 visited cells, returning an empty route if the goal cannot be found within that limit. Equal shortest paths use deterministic neighbor order `+X, +Z, -X, -Z`, and coordinate math is overflow-safe.

The Aurora Forest quest compass uses this native topological path to point toward intermediate registered cells for distant relics rather than blindly pointing through gaps. `smoke_cell_routes.gd` and the native Doctest verify gaps, shortcuts, disconnected regions and the loaded-only option. A full hierarchy/portal graph and true navigation mesh corridor are separate future capabilities.

## Incremental navigation tile updates with obstacle snapshots

`WorldPartition3D.patch_navigation_tile(previous, resolution, previous_blockers, blockers, agent_radius=0.45, max_slope_degrees=45.0)` is a **native C++ incremental geometry filter**. It accepts a cached `NavigationMesh` built by the same WorldPartition3D terrain-grid builder, plus the complete old and new blocker sets. This avoids re-testing all triangles when only one barricade is added, moved or removed.

```gdscript
# From an opted-in streamed cell scene root, called by the existing bounded
# navigation dirty-cell scheduler:
var current: PackedVector3Array = get_current_tree_rock_and_barricade_footprints()
var updated: NavigationMesh = partition.patch_navigation_tile(
    previous_mesh, 16, saved_footprints, current, 0.45, 42.0)
if updated != null and updated.get_polygon_count() > 0:
    if updated != previous_mesh:
        $StreamingNavigationRegion.navigation_mesh = updated
    previous_mesh = updated
    saved_footprints = current.duplicate()
    print("Nav triangles re-tested: ",
        partition.get_last_navigation_tile_retested_triangle_count())
```

The engine compares blocker coordinates as an exact **multiset**, so merely changing their order does not waste NavMesh work and two identical obstacles still count separately. Added/removed footprints are automatically expanded by the NPC radius and combined into a conservative dirty rectangle. Polygons wholly outside the changed bounds preserve their existing pass/fail result; overlapping triangles use the **same** slope and triangle/disc clearance predicate as `build_navigation_tile()`. Both methods enumerate triangles in identical grid order, so the resulting vertex and polygon arrays are exactly the same as a full rebuild (given unchanged terrain samples, radius and slope rules). The native builder also validates cached polygon topology and falls back to a full, safe rebuild if it detects a malformed old grid. A no-change patch returns the original resource without modifying the navigation server.

For a 16×16 forest tile, full regeneration filters **512 triangles** every time; a local obstacle change typically filters just a few dozen. `get_last_navigation_tile_retested_triangle_count()` reports the last number of *geometric filter evaluations*, not measured milliseconds or total CPU cost. Incremental patching still scans bounded cached polygon metadata and candidate triangles; no claim of an asynchronous worker or a guaranteed frame-time improvement is made. Limits remain 32×32 quads, at most 256 old and 256 new blockers, finite positions/radii, and the original 0–8 agent radius / 0–89-degree slope bounds. If terrain height, resolution, agent radius or slope policy changes, **build a fresh full tile** and reset the obstacle snapshot.

Aurora Forest caches the complete blocker snapshot on each streamed scene root and uses the incremental API on the existing `rebuild_streaming_navigation_mesh()` callback. The physical B-key barricade toggles collision and triggers the native dirty scheduler, but now NavMesh regeneration does **not** resample all analytic ground heights or re-check unaffected tree/rock triangles. The root persists, and previously loaded regions still use the two-physics-frame NavigationServer readiness fence. `smoke_incremental_navmesh.gd` verifies exact polygon-array equivalence for add/move/remove, no-change/reordered cache hits and localized filter counts; `smoke_dynamic_navmesh.gd` verifies the real live barricade uses the patch rather than silently falling back to a full rebuild.

This approach is analogous in purpose to localized dirty navigation updates in Unreal, but it is a small deterministic grid algorithm, **not** Unreal Recast or Godot's runtime Recast/NavMeshGenerator, and is still synchronous under the native one-tile-per-physics-frame queue.

## Dynamic navigation obstacle updates with bounded rebuild work

Games can edit in-world collision obstacles and refresh a cell's existing `NavigationRegion3D` **without unloading the scene or recreating its foliage**. This feature uses opt-in, scene-owned rebuilding: the native module schedules work; scene code creates and publishes the new `NavigationMesh`.

```gdscript
world.max_navigation_rebuilds_per_physics_frame = 1
world.cell_navigation_mesh_rebuilt.connect(_on_navigation_rebuilt)

# After changing the scene-owned obstacle data and collision:
if world.mark_cell_navigation_dirty(cell):
    # The native streamer will invoke the scene root's callback at most once
    # per available physics-frame slot, combining repeated marks.
    pass

# On the streamed cell scene root:
func rebuild_streaming_navigation_mesh() -> bool:
    var new_mesh: NavigationMesh = rebuild_mesh_from_current_obstacles()
    if new_mesh == null or new_mesh.get_polygon_count() == 0:
        return false
    $StreamingNavigationRegion.navigation_mesh = new_mesh
    return true
```

The engine enforces **at most 1–16 attempted callbacks per engine physics frame**, even if `update_streaming()` is called multiple times. Repeated marks for one cell are coalesced, and eligible tiles are selected by Manhattan distance to the observer with deterministic X/Z tie-breaking. Only already-loaded scene roots implementing `rebuild_streaming_navigation_mesh()` can be dirtied; at most **128** distinct dirty cells are tracked. Navigation-inactive cells retain pending updates but are not rebuilt until activated. Failed or non-Boolean callbacks remain dirty and cannot pass readiness; they retry at most once per physics frame per budgeted attempt. On unload, pending updates and revision counters are cleared.

`is_cell_navigation_ready(cell)` returns false immediately after a mark, so fast travel and path queries can wait until a successful rebuild **plus two completed physics frames**. A successful refresh emits `cell_navigation_mesh_rebuilt(cell, revision)`, increments the per-cell revision (initially 0), and increments `get_navigation_mesh_generation()` for global path-cache invalidation. The global generation also advances immediately when a tile is first dirtied, and when a cell loads, unloads or changes native navigation activation. While any tile is pending, gameplay can choose to suspend old cached routes and use local steering. This prevents an NPC from keeping an obsolete corridor through a changed **intermediate** tile. It is a versioning signal, not proof that an updated map can still reach its goal.

Aurora Forest demonstrates the path: press **B** to build/remove a physical barricade several meters ahead. Each loaded cell owns one optional barricade, represented by both a visible box collider and a circular NavMesh blocker (which includes the NPC radius). The scene rebuild callback generates a **new** native filtered NavMesh resource, assigns it to its existing NavigationRegion3D, and leaves the terrain, vegetation, and scene root intact. The HUD shows pending dirty tiles; stalkers re-query their path on the next available native steering grant once the updated region is ready. The new `smoke_dynamic_navmesh.gd` tests dirty coalescing, frame caps, physical obstacle geometry, restored polygons, scene preservation and NPC path invalidation.

**Limitations:** the generator remains synchronous on the main thread, bounded by existing mesh resolution (max 32×32) and 256 blockers. Budgeting caps **how many** expensive tile updates happen per physics frame, not their milliseconds. It does not implement background Recast baking, moving obstacle continuous updates, automatic polygon links or server sync forcing; NavMesh server changes still propagate on physics ticks. A permanently failing callback remains queued and can consume one scheduled slot per later frame.

## Native obstacle-clearance and slope-aware terrain tiles

Use `WorldPartition3D.build_navigation_tile(vertices, resolution, blockers, agent_radius=0.45, max_slope_degrees=45.0)` for deterministic, bounded **native C++ triangle filtering** before publishing a NavMesh to NavigationServer3D:

```gdscript
# Sample a (resolution+1) x (resolution+1) regular terrain grid in cell-local
# space, with X as the fastest-changing coordinate.
# Each blocker packs Vector3(local_x, local_z, obstacle_radius).
var navmesh: NavigationMesh = world.build_navigation_tile(
    sampled_vertices, 16, tree_and_rock_footprints, 0.45, 42.0)
if navmesh != null:
    $NavigationRegion3D.navigation_mesh = navmesh
```

Each terrain quad is split into up to two +Y-facing triangles. A triangle with an upward slope beyond the threshold is discarded. A candidate triangle is also discarded when its XZ footprint **intersects any obstacle circle expanded by the NPC radius**; the calculation uses planar triangle/segment distances, so large triangles cannot incorrectly remain walkable just because their centroids miss a blocker.

Inputs are capped: resolution **2–32** (max 2048 triangles), **256 blockers** (Vector3(x, local_z, obstacle_radius), obstacle radius 0–16), agent radius **0–8**, slope **0–89 degrees**. All sampled vertices and blockers must be finite. Invalid data returns a null resource with an error. The procedure runs **synchronously on the caller thread** and performs up to O(resolution² × blocker_count) tests; callers should generate once per streamed cell, cache the result, and use navigation-region streaming budgets to amortize work.

This is a small deterministic grid-based NavMesh filter, **not Recast baking**. It models circular horizontal obstacles (including a conservative circumscribed radius for rocks), but not vertical clearance, moving obstructions, jump links, precise polygon clipping, or dynamic NavMesh rebuilding. It intentionally deletes entire triangles instead of cutting holes. Avoid creating overly dense meshes or excessive footprints; and keep shared tile seams and guaranteed walkable border strips, otherwise filtering may disconnect cells. Native Doctest covers increasing agent radius, slope limits, invalid inputs and bounds. `smoke_navigation_clearance.gd` checks a real game's collision footprints and generated NavMesh; these tests require a compiled Cgame runtime.

## Streaming actual NavigationMesh regions

`WorldPartition3D` can now manage a fourth independent runtime tier: **navigation regions**. It is separate from what is visually loaded, how many physics obstacles participate in collisions, and which AI scripts run. The default `navigation_radius = -1` preserves the native policy's all-loaded-active behavior. The Aurora Forest demo opts into `navigation_radius = 1`, one-ring hysteresis and no more than two live-cell region transitions per frame.

```gdscript
world.navigation_radius = 1
world.navigation_hysteresis_cells = 1
world.max_navigation_transitions_per_frame = 2
world.cell_navigation_changed.connect(_on_cell_navigation_changed)
```

A scene root opts into `set_streaming_navigation_active(active)`, called once before `_ready()` and on subsequent budgeted state transitions. In the demo, each near-detail cell creates a real `NavigationRegion3D` holding a deterministic 16×16-grid obstacle-filtered `NavigationMesh` (up to 512 triangles) from the same analytic terrain height function used by the ground mesh. Adjacent tiles share height and edge coordinates, so Godot's `NavigationServer3D` can connect their boundaries after its physics synchronization. Distant or nav-dormant cells do not generate an active region. Navmesh resources are cached per live cell; they are freed when the cell scene unloads.

```gdscript
func set_streaming_navigation_active(active: bool) -> void:
    navigation_active = active
    if is_node_ready():
        $NavigationRegion3D.enabled = active

func is_streaming_navigation_ready() -> bool:
    return is_node_ready() and $NavigationRegion3D.enabled
```

The engine adds a **two-physics-frame activation fence** before `is_cell_navigation_ready(cell)` succeeds, optionally checking the scene callback. `is_streaming_source_navigation_ready(name)` waits for all registered source cells; urgent/important priority 2/3 sources and pinned hubs request near nav regions even if far from the observer. Neither native flag nor time delay by itself guarantees a NavigationServer3D map connection, navigation mesh quality or safe agent radius. **Avoid force-syncing the server**: navigation map changes normally propagate on the physics loop.

Stalkers query actual `NavigationServer3D.map_get_path()` only under existing native CPU permits (`max_navigation_updates_per_physics_frame`), throttled again to a new route at most every 12 physics ticks unless their destination moves more than 4 m. They use cached waypoints between queries and preserve their up-to-three-ray local collision avoidance as a fallback. **Important limitation:** native triangle filtering now excludes steep slopes and conservative tree/rock discs expanded by agent radius, but does not perform exact polygon carving or fully validate walkability, capsule height or dynamic obstacles. The physics-ray steering fallback remains important. Recast-based carving and hierarchical path caching remain future work.

Validation: new `smoke_navmesh_streaming.gd` exercises live nav region polygons, real NavigationServer path across adjacent cells, priorities, pin/unpin, dormant regions, and reactivation. Running it requires a compiled Cgame executable; it has not been executed in this authoring environment.

## Navigation and AI work scheduling

`WorldPartition3D` now provides a bounded, deterministic **per-physics-frame allowance** for expensive NPC steering/path recomputation. It is independent of resource, collision and simulation transition budgets; the engine does **not** automatically generate navigation meshes or calculate `NavigationServer3D` paths. This lets game-level AI scale query work without freezing `CharacterBody3D` movement.

```gdscript
world.max_navigation_updates_per_physics_frame = 2

func configure_npc(npc: CharacterBody3D, agent_id: String) -> void:
    world.register_navigation_agent(agent_id, npc, 2)

func _physics_process(delta: float) -> void:
    # Keep movement integration and any NavigationAgent3D internal stepping
    # running every physics frame; throttle only EXPENSIVE path/target updates.
    if world.try_acquire_navigation_update(agent_id):
        cached_steering = recalculate_expensive_steering_or_path()
    move_and_slide_with_cached_steering(delta)

func _exit_tree() -> void:
    world.unregister_navigation_agent_if_owner(agent_id, self)
```

**Scheduler behavior:** registered names are 1–64 characters (128 agents max); priorities 0–3. Each physics frame the native code freezes a list of at most `max_navigation_updates_per_physics_frame` eligible winners. Eligible agents are live, inside the scene tree, receiving physics processing, and currently in a streamed cell where both `is_cell_simulation_active` and `is_cell_physics_active` are true. The highest priority wins; equal priorities use least-recently-selected ordering and alphabetical name to break ties. Every grant can be consumed only once per frame, regardless of which enemy script processes first. If urgent agents permanently saturate the budget, background agents can wait indefinitely: priorities are **strict**, while fairness is for agents within a priority tier.

On a cell unload, dormant actors stop qualifying immediately; game code should call `unregister_navigation_agent_if_owner` when the node exits. If an enemy respawns under the same stable ID while the old instance is queued for deletion, the old instance **cannot** unregister the replacement. Deleted ObjectIDs are pruned on the next scheduling pass.

**Godot NavigationAgent3D caution:** its `get_next_path_position()` needs to be called every physics frame to advance its internal path state. Do **not** throttle that step with this scheduler. Throttle goal changes, explicit `NavigationServer3D` path requests or other costly steering calculations. Query a navmap only after server synchronization. Aurora Forest currently has **no baked navmesh**; it uses up to three `PhysicsDirectSpaceState3D.intersect_ray()` obstacle probes per granted steering recalculation; actor physics movement continues every tick. This is local avoidance, **not** globally correct pathfinding. Run `smoke_navigation_budget.gd` to test native grants, fairness, priority, dormant filtering and stalker integration.

## Independent collision streaming tiers

Spatial collision activity is not the same as loaded geometry, visual LOD, or AI simulation activity. The physics policy has its own bounded, optional tier:

```gdscript
world.physics_radius = 1
world.physics_hysteresis_cells = 1
world.max_physics_transitions_per_frame = 2
world.cell_physics_changed.connect(_on_cell_physics_changed)
```

An opted-in cell scene root can implement `set_streaming_physics_active(active)` to set an appropriate collision layer or defer shape disabling safely. The native module sets the initial state **before** the scene's `_ready()`; it also emits `cell_physics_changed` after subsequent budgeted transitions. Pinned hubs stay physics-active. For important/urgent (priority 2/3) streaming sources, the scheduler forces active physics and full-detail LOD in destination cells **even outside the normal physics radius**. This permits the normal nearby terrain to stay responsive while distant fast travel preloads and activates its arrival colliders. Ordinary/background sources (0/1) do not force distant physics.

`is_cell_physics_ready(cell)` requires a live physics-active scene plus at least one completed engine physics frame since activation. A root may further implement `is_streaming_physics_ready() -> bool` to verify the actual properties or collision resources on its own scene. `is_streaming_source_physics_ready(name)` checks that every registered scene in the named source passes this fence; use it **alongside** `is_streaming_source_activation_ready(name)` before fast travel. This is deliberately not a claim that arbitrary server physics/mesh/navmesh/GPU resources are synchronized.

```gdscript
func set_streaming_physics_active(active: bool) -> void:
    # Example only: keep visual meshes visible but filter their obstacle body.
    $FoliageCollisions.collision_layer = 1 if active else 0

func is_streaming_physics_ready() -> bool:
    return $FoliageCollisions.collision_layer == 1
```

**Scope:** Cgame does not automatically pause physics bodies or deactivate arbitrary scene descendants. Foliage in Aurora Forest keeps its collider shapes allocated but disables their collision layer, reducing physics query/collision participation — **not necessarily physics shape memory or CPU frame time**. The new `smoke_physics_tiers.gd` checks native activation, a live PhysicsServer raycast, urgent source behavior, full LOD, source removal, pinned hubs and the default opt-out behavior.

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

## Gameplay residency, persistence and navigation gates

The sections below describe gameplay-facing APIs layered on the streaming
sources, pins and navigation tiers above. Residency claims (pins, leases and
route leases) are served before observer rings and work without a valid
observer; runtime data layers always win over claims. Streaming sources
(`set_streaming_source()`) remain the way to add cameras, co-op players or
prefetch targets, and sources of the same priority are scheduled nearest ring
first so no source starves another under a small request budget. Distance
unloads are limited by `max_unloads_per_frame` (default 32);
`retry_failed_cells()` clears failure markers for an explicit retry.

## Fine-grained NavigationLink3D gates for streamed AI

Cell-wide navigation gating disables every walkable region of a scene.
For a door, bridge or isolated transition between two regions, use an
authored `NavigationLink3D` instead. Godot's navigation server can include
or exclude a link without rebuilding a navigation mesh or unloading a cell.

The link must be a real child of the source cell scene. Name it consistently
and register the required edge **once during scene setup**:

```gdscript
world.set_route_connection_link(Vector2i(0, 0), Vector2i(1, 0), "PatrolBridgeLink")

# A switch only controls this one bridge, not either cell's nav region:
world.set_cell_navigation_link_enabled(Vector2i(0, 0), "PatrolBridgeLink", false)
assert(world.is_cell_navigation_enabled(Vector2i(1, 0)))
assert(world.acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0)).is_empty())

# Once opened, the AI may reserve both cells again:
world.set_cell_navigation_link_enabled(Vector2i(0, 0), "PatrolBridgeLink", true)
var tokens := world.acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0))
world.release_cell_route(tokens)
```

`get_route_connection_link(from_cell, to_cell)` queries a registered edge;
`clear_route_connection_link` unregisters it. Each required link is
associated with its **source** cell, but its availability gates travel in
either direction across that edge. Multiple independent route owners are
still protected by token-based leases, and no partial allocations occur if
a required link is closed.

`get_navigation_link_states()` returns a safe, deep-copy checkpoint map;
`set_navigation_link_states()` restores it, applying changes to loaded
links and preserving overrides for temporarily unloaded cells. A default
unlisted path is open. Only disabled entries are stored, limited to 4096
cells and 128 link paths per cell, and unsafe NodePaths are rejected.
Subscribe to `cell_navigation_link_state_changed(cell, path, enabled)`
to release stale paths and reacquire routes as topology changes. Configuration
of *which* cell edge requires *which* link belongs to the authored level
setup, not to the saved runtime gate states.

The demo includes two walkable patrol islands on navigation layer **2**,
which are separated by an 8-meter gap in mesh coordinates. A manually
authored `PatrolBridgeLink` provides the sole navigation connection.
The surrounding procedural world uses navigation layer **1** and remains
accessible even when the patrol bridge is closed. The player controls the
bridge using the `PatrolGate` interactable switch (E). NavigationAgent3D
queries layer 2 and has custom physical movement across this short bridge
because an off-mesh navigation link specifies a route, **not automatic
movement for a CharacterBody3D**.

This is fine-grained link connectivity, not a dynamic navmesh bake, crowd
simulation, agent obstacle avoidance, or general multi-floor topology
solver. Links must connect authored regions within the navigation server's
link-connection radius and are synchronized on subsequent physics frames.
Changes to a link's path or scene hierarchy need a save migration.

## Dynamic navigation cell gates and AI route invalidation

Individual cells can stop contributing their navigation regions to
`NavigationServer3D` without unloading their graphics, physics bodies,
interactive objects or existing stream leases. This is useful for puzzle
gates, changing terrain, doors and quest-controlled navigation access:

```gdscript
world.set_cell_navigation_enabled(Vector2i(1, 0), false)
assert(not world.is_cell_navigation_enabled(Vector2i(1, 0)))
assert(world.acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0)).is_empty())

# When the player opens the gate, the route may be reserved again.
world.set_cell_navigation_enabled(Vector2i(1, 0), true)
var corridor_tokens: Array = world.acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0))
world.release_cell_route(corridor_tokens)
```

The native streamer updates every `NavigationRegion3D` descendant of
the specified loaded cell and emits
`cell_navigation_state_changed(cell, enabled)` only on effective
transitions. A navigation-disabled scene stays resident if its camera,
pin, or independent lease still requires it. Existing owners' leases
are **not revoked**; AI systems should subscribe to the signal, stop
movement, release their own corridor tokens and reacquire them once
the gate reopens. `acquire_cell_route` checks both runtime Data Layers
and navigation gates atomically, with no partial token allocations.

The `navigation_cell_states` inspector property, along with
`get_navigation_cell_states()` and `set_navigation_cell_states()`,
allows a game to save and import disabled cells. Only explicit
disabled values are stored, and missing entries default to enabled.
Bulk imports apply to loaded regions and notify subscribers when a gate
changes. A cell is also brought to its effective navigation state after
the scene's `streaming_activated()` callback and before
`cell_activated` subscribers run.

**Scope:** this is a coarse per-cell navigation switch, not geometric
obstacle carving, navmesh runtime baking or edge-specific gates. The
whole navigation region of the cell is disabled, even when only one
door has changed. The current implementation sets all loaded
`NavigationRegion3D` descendants to the effective cell state; custom
region-level enable flags are not preserved independently. For an
individual door, use authored `NavigationLink3D` or geometry-specific
navigation updates in a more advanced system. Godot synchronizes
navigation server changes on later physics frames, and existing agent
paths do not automatically reroute; consumers must invalidate/requery
their path before moving across the changed map.

## Per-object interactive state without scene-root boilerplate

An interactive chest, lever, door or puzzle mechanism can live under any
streamed cell root as a reusable child component. Instead of teaching the
root scene about each child, mark the object with the Godot node group
`streaming_stateful` and implement two small callbacks:

```gdscript
# In the object's script:
func _ready() -> void:
    add_to_group("streaming_stateful")

func capture_streaming_object_state() -> Dictionary:
    return {"opened": opened, "uses": use_count}

func restore_streaming_object_state(state: Dictionary) -> void:
    opened = bool(state.get("opened", false))
    use_count = int(state.get("uses", 0))
    update_appearance()
```

The native `WorldPartition3D` opt-in property `persist_streaming_objects`
defaults to false. Enable it on the detailed scene streamer, and use:

```gdscript
world.persist_streaming_objects = true
# Immediately after a player opens a chest:
world.capture_cell_object_states(Vector2i(0, 0))
# Save all still-loaded and previously streamed out interactive objects:
var object_states: Dictionary = world.snapshot_cell_object_states()
# Rehydrate during checkpoint load (missing objects reset to defaults):
world.load_cell_object_states(object_states)
```

The engine traverses **only a loaded cell's subtree** for group members,
not all world nodes. Each recorded object is keyed by a stable
scene-relative NodePath string and can be reused in any cell. Unload captures
children before the cell's deactivation callback; load restores them after
the cell root's `_ready()` and gameplay/physics state restoration, before
`streaming_activated()`. Manual capture fires
`cell_object_state_changed(cell, states)` only when a real change occurs.
Cache getters return deep copies.

For safe and bounded file persistence, an imported record can have at most
32 fields and each cell at most 128 objects. Supported values are null,
bool, int, finite float, short String (max 1024 chars), Vector2/3 and
integer vector types; nested dictionaries, Arrays, Object references and
RIDs are rejected. NodePath keys must remain relative and cannot escape
the loaded root. This supports small interactive flags and counters, not a
complete arbitrary graph serializer. Changes to authored node hierarchy
can invalidate path-based save records; for production migrations, keep
stable node names or translate saved paths by game schema version.

These are *three independent cache domains*: gameplay root-state
(`snapshot_cell_states()`), RigidBody3D motion
(`snapshot_cell_physics_states()`) and child-interactable state
(`snapshot_cell_object_states()`). A game may opt into any subset.

## Opt-in RigidBody3D streaming persistence

The engine can retain dynamic physics objects in streamed scenes without
requiring each game to write custom callbacks for every body. This is
independent of `capture_streaming_state()` for quest or gameplay data.

```gdscript
# Streamer's inspector flag, or from game setup:
world.persist_rigid_bodies = true

# In the authored cell root, during _ready() or scene construction:
$StreamingCrate.set_meta("streaming_persistent", true)

# Before saving a checkpoint, capture even still-resident bodies:
var states: Dictionary = world.snapshot_cell_physics_states()
var file := FileAccess.open("user://physics.save", FileAccess.WRITE)
file.store_var(states, false)
file.close()

# After reading it with get_var(false) and validating the save header:
world.load_cell_physics_states(states)
```

For each marked `RigidBody3D`, the engine stores its stable **scene-relative
NodePath**, local `Transform3D`, linear/angular velocities, sleeping and
freeze flags. Capture occurs *before* a scene's
`streaming_deactivating(cell)` callback, which may stop or freeze simulated
objects, and restoration occurs *after* the scene's `_ready()` and
`restore_streaming_state()`, before `streaming_activated()`. If a node is
renamed or removed in a later game version, its old record is ignored.

`get_cell_physics_state(cell)` inspects one cell,
`get_cell_physics_state_count()` reports cached cells, and
`clear_cell_physics_states()` clears the cache. Getters and snapshots return
deep copies. Import rejects unsupported types, nonfinite transforms and
velocities, unsafe relative paths and body states with missing fields.
Only marked nodes are ever restored, with a maximum of 128 records per
cell. Missing imports leave currently loaded rigid bodies untouched.

This is **opt-in, in-memory physics persistence**, not a full physics
snapshot/rollback system: it does not preserve collision contacts, forces,
constraints/joints, arbitrary scripts, server RIDs or determinism across
different physics engines. Moving a live RigidBody3D transform or velocity
repeatedly can produce unstable physical behavior; the engine applies stored
state only during scene re-instantiation or explicit save loading. Saved
values can be affected by physics steps between the last snapshot and unload,
so a final save should capture at a well-defined point in the game loop.
Real productions should use versioned, bounded, atomic checkpoint files.

## Navigation corridor leases for streamed AI

Large-world NPCs can traverse multiple `WorldPartition3D` cells without the
camera visiting every cell. The engine exposes a deterministic,
four-connected route between grid coordinates:

```gdscript
var cells: Array = world.get_cell_route(Vector2i(0, 0), Vector2i(1, 0))
# [Vector2i(0, 0), Vector2i(1, 0)] — cells along a stream corridor.
var tokens: Array = world.acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0))
if tokens.size() == cells.size():
    # Wait until the cells are loaded and the NavigationServer has synced.
    # Then use NavigationAgent3D.get_next_path_position() each physics tick.
    pass
# The AI owner releases only its own corridor leases on exit or cancellation.
world.release_cell_route(tokens)
```

The corridor includes both endpoints, moves through orthogonally adjacent
cells, and contains at most **64 cells**. It is a prefetch/residency tool,
**not** a navigation mesh, obstacle solver or final pathfinding algorithm.
A route longer than the cap, one crossing any disabled Data Layer, or one
that would exhaust the existing 256-leased-token limit fails atomically and
returns an empty Array. Existing manual pins/leases of other owners are
unaffected. No partial route is retained on failure. A scene missing a
registered asset cannot load even if it holds a route lease.

A path-following agent must wait for streamed `NavigationRegion3D` nodes
and at least one subsequent physics synchronization before querying
`NavigationServer3D`. Call `NavigationAgent3D.get_next_path_position()`
each physics tick and release the returned tokens when the AI despawns.
The engine intentionally does **not** serialize live lease tokens. A save
file can store the AI's position and destination, from which its new route
is acquired on load. Navigation across neighbors requires truly connecting
scene navigation polygons; simply holding two leases does not connect
disjoint polygons.

## Physics and navigation lifecycle for streamed cells

Detailed cell scenes may contain `StaticBody3D`, `CollisionShape3D`,
`NavigationRegion3D`, agents and other physics/navigation scene nodes.
Only the registered near-detail cells are instantiated, so Godot's servers
receive no distant cell physics/nav resources unless you explicitly put
such resources inside a proxy scene.

Add optional callbacks to the root `Node3D` of any streamed `PackedScene`:

```gdscript
func streaming_activated(cell: Vector2i) -> void:
    # Runs after _ready() and restore_streaming_state(), but the server will
    # not expose the new navigation region until a later physics frame.
    $WalkableRegion.enabled = true
    $TerrainPhysics/GroundShape.disabled = false

func streaming_deactivating(cell: Vector2i) -> void:
    # Runs before capture_streaming_state() and before queue_free() is deferred.
    $WalkableRegion.enabled = false
    $TerrainPhysics/GroundShape.disabled = true
```

A scene need not implement either callback. The engine also broadcasts
`cell_activated(cell)` and `cell_deactivating(cell)` in that same order,
in addition to the established `cell_loaded` and `cell_unloaded` signals.
Use them for cross-scene services such as detaching an AI director,
removing external physics references, or deferring path queries. A
navigation-server query must await a physics frame after the region enters
the scene tree; the example demo waits for two physics frames.

`get_cell_simulation_stats(cell)` returns a dictionary with
`collision_objects`, `collision_shapes` and `navigation_regions`
counts. Unloaded cells return zeros. The query recursively traverses one
loaded cell's nodes **on demand** rather than adding work to every
`WorldPartition3D` streaming tick. It counts nodes, not simulated
contacts, server processing time or finalized navmesh quality.

This implementation does not automatically pause every arbitrary
`RigidBody3D` or save its physics velocity; author custom root callbacks
for your game's simulation lifecycle. It also does not build a tiled
navigation graph; navigation mesh content is provided by the scene author.

## Reference-counted runtime cell leases

Manual `pin_cell()` is idempotent and cannot distinguish competing
owners. For a quest, cutscene or combat system that must independently retain
the same cell, use positive lease handles:

```gdscript
var quest_token: int = world.acquire_cell_lease(Vector2i(4, 2))
var cutscene_token: int = world.acquire_cell_lease(Vector2i(4, 2))
assert(world.get_cell_lease_count(Vector2i(4, 2)) == 2)

# Quest finishes: the cutscene's claim continues to keep this cell loaded.
assert(world.release_cell_lease(quest_token))
assert(world.get_cell_lease_count(Vector2i(4, 2)) == 1)

# The cutscene finishes: normal distance-based unloading can resume.
assert(world.release_cell_lease(cutscene_token))
assert(not world.release_cell_lease(cutscene_token)) # No double release.
```

Tokens are local to their `WorldPartition3D` instance, not persistent
resource IDs. The engine holds at most 256 active tokens. A disabled layer
prevents loading and unloads a leased scene, but does not invalidate the
lease; reactivation can stream it again. Existing observer and pinned-cell
residency works independently, and all requests use the same budgets.
Leases survive scene mapping replacement but cannot resurrect an
unregistered asset. When loading a game save, systems must reacquire the
leases they still need; raw lease tokens must not be serialized as progress.

## Reactive streaming signals

The core streamer now broadcasts these native Godot signals to subscribers:

- `layer_state_changed(layer: String, enabled: bool)`: an effective runtime
  layer transition from `set_layer_enabled()` or `set_layer_states()`.
  Layer states default to enabled, so redundant toggles produce no event.
- `cell_state_changed(cell: Vector2i, state: Dictionary)`: a genuinely changed
  cached state from `set_cell_state()`, scene-root capture on unload or the
  snapshot of a still-active cell. The payload is a defensive deep copy.
  Bulk `load_cell_states()` replaces saved state and restores active cells
  without emitting a separate event for each imported cell.

```gdscript
# Connect once to the native node; gameplay can respond without frame polling.
world.layer_state_changed.connect(_on_layer_state_changed)
world.cell_state_changed.connect(_on_cell_state_changed)

func _on_cell_state_changed(cell: Vector2i, state: Dictionary) -> void:
    if cell == Vector2i(0, 0) and state.get("reward_claimed", false):
        world.set_layer_enabled("combat_event", true)

func _on_layer_state_changed(layer: String, enabled: bool) -> void:
    print("World layer event: ", layer, " enabled: ", enabled)

# Explicit gameplay mutations should publish their new serialized state.
var hub: Node3D = world.get_cell_instance(Vector2i(0, 0))
if hub != null and hub.has_method("capture_streaming_state"):
    world.set_cell_state(Vector2i(0, 0), hub.call("capture_streaming_state"))
```

The signal is not a global bus and does not observe every property of every
`Node`. For immediate notification, gameplay writes its changed state through
`set_cell_state()`. Otherwise it is captured when the cell unloads or the
game saves a snapshot. This avoids per-frame tree scans, but event listeners
should remain cheap and should not recursively trigger conflicting world
mutations.

## Runtime Data Layers (gameplay events)

Use `cell_layers` (a [Vector2i → String] dictionary) and `layer_states`
(a [String → bool] dictionary) to control scene activation independently of
distance, streaming sources and pinned-cell residency. The properties are
exposed in the Godot inspector and persisted in scenes.

```gdscript
# An inactive combat quest has no active arena scene, even if it is pinned:
world.set_cell_layer(Vector2i(4, 2), "combat")
world.set_layer_enabled("combat", false)
world.pin_cell(Vector2i(4, 2))
# On quest activation, the cell streams in using the regular budgets:
world.set_layer_enabled("combat", true)
world.update_streaming()  # Optional explicit tick; the node also processes.
# Persist activation states with the checkpoint along with cell state/pins.
var states: Dictionary = world.get_layer_states()
world.set_layer_states(states)
```

Layer deactivation stops new requests and instantiations, cancels pending cell
mappings and queues existing loaded scenes for budgeted unload. The
`capture_streaming_state()` callback runs during unload and is applied when
the layer is activated and the cell is loaded again. Removing a layer
assignment makes the cell eligible immediately, while deleting a saved
activation state makes that layer enabled by default.

A layer is only a runtime loading *gate*, not a separate renderer,
visibility-only switch or general multi-layer boolean-expression system.
One cell is assigned at most one named layer; default unassigned cells are
always enabled. Layers on two separate `WorldPartition3D` nodes are
independent. For large numbers of cells, stagger activation and profile
`max_instances_per_frame` and `max_unloads_per_frame`.

## Streaming gameplay state and save files

`WorldPartition3D` provides an opt-in lifecycle contract for a scene's
root `Node3D`, in addition to spatial streaming and pinning:

```gdscript
# On the cell scene root (for example, an opened treasure chest):
var opened := false

func capture_streaming_state() -> Dictionary:
    return {"opened": opened}

func restore_streaming_state(state: Dictionary) -> void:
    opened = bool(state.get("opened", false))
    # Update visuals after the scene has finished _ready().
```

The engine automatically captures state immediately before queueing the
loaded cell for deletion and restores the cached data after the next
`PackedScene` instantiation, before emitting `cell_loaded`.
A cell whose root does not implement these methods streams as before.
Empty state dictionaries remove any previous cached value.

For checkpoint saves, ask the engine to capture still-loaded cells:

```gdscript
var file := FileAccess.open("user://world.save", FileAccess.WRITE)
file.store_var({
    "version": 1,
    "cell_states": world.snapshot_cell_states(),
    "pins": world.get_pinned_cells(),
})
file.close()

var input := FileAccess.open("user://world.save", FileAccess.READ)
var checkpoint: Variant = input.get_var(false) # Never deserialize objects.
if checkpoint is Dictionary and checkpoint.get("version") == 1:
    world.load_cell_states(checkpoint.get("cell_states", {}))
    world.set_pinned_cells(checkpoint.get("pins", []))
```

The state cache is in memory until the game explicitly writes it. Use only
save-compatible Variant types (numbers, strings, vectors, arrays and
dictionaries), not Node/Object references. Production saves should validate
the file, schema and size, use temporary-file/atomic replacement and account
for game-version migrations. These APIs do not serialize physics engines,
navigation agents or arbitrary child nodes automatically.

## Offline HLOD proxy authoring example

The built-in demo at `modules/world_partition/demo/` includes a headless
content-generation tool: `tools/bake_hlod_proxies.gd`. It instantiates the
example detailed forest at each cell origin, subsamples MultiMesh transforms,
uses simpler canopy geometry, and writes packed proxy scenes to
`res://generated/forest_proxy_X_Z.tscn`. The game prefers these saved scenes,
falling back to dynamic proxy generation where an asset is missing.

```sh
# Runs with a stock Godot editor, before compiling this Cgame fork.
godot --headless --path modules/world_partition/demo --import --quit
godot --headless --path modules/world_partition/demo \
  --script res://tools/bake_hlod_proxies.gd -- --radius=6 --stride=8
godot --headless --path modules/world_partition/demo \
  --script res://tests/hlod_bake_test.gd
```

This is a **demo-specific offline foliage/mesh subsampler**, not an editor
plugin that automatically merges arbitrary authored scenes, bakes texture

## Tests

The module includes 129 Doctest cases across `test_world_partition_3d.h` (38) and `test_world_partition_3d_extra.h` (91), including disk-backed scenes, origin-offset checks, load/unload hysteresis, duplicate mappings and overflow guards, shared resource requests, and cleanup of failed/pending ResourceLoader tokens. Tests are picked up by Godot's generated module-test list.

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[WorldPartition3D]*"
```

**Validation status:** Source changes and test cases are present, but a Godot binary/compiler toolchain capable of building this fork was not available to the authoring environment. CI build and test execution must pass before treating the module as production-ready.

## Non-goals and limitations

- **Cell route caches store topological, not physical routes.** A cached registered-cell corridor is not a NavMesh-safe or collision-free path. Cache keys distinguish loaded-only from configured routes; dynamic NavMesh updates still require NPC-level path replanning. Caching is deliberately bounded to 128 entries and returns defensive Array copies.
- **Incremental obstacle patches require an unchanged terrain grid and navigation policy.** Each previous NavigationMesh and blocker snapshot must refer to the same geometry, resolution, radius and slope parameters. The algorithm validates cached polygon topology and changed blocker locations, but cannot prove arbitrary user changes to terrain samples or server-side region transforms. It scans cached polygon masks and triangle bounds on the main thread; the diagnostic counter only measures geometric re-evaluations, not CPU milliseconds.
- **Dynamic NavMesh updates are main-thread and scene-owned.** Dirty rebuild limits are explicit per physics frame, but each permitted NavMesh creation can still cost CPU. The native module does not mutate third-party obstacles, force NavigationServer synchronization or guarantee the connectivity of a rebuilt mesh. Failed scene callbacks keep the tile unready.
- **Native terrain tile filtering is conservative, not full Recast baking.** Per-cell 16×16 tiles reject steep triangles and obstacles approximated as expanded discs; hole cutting is coarse (whole triangles), there is no vertical clearance, off-mesh linkage or automatic dynamic obstacle rebake. Terrain-tile seam connectivity still depends on authored free corridors and Godot physics-server synchronization.
- **Cell routing is topological, not physical.** `find_cell_path` is a bounded shortest 4-neighbor route of registered PackedScene cells; it does not confirm walkability across individual objects or NavMesh edges, and an empty result can also mean the 512-cell search limit was reached.
- **Navigation scheduler supplies permits, not pathfinding or a navmesh.** The engine keeps physics, navigation map synchronization and actual movement separate. It limits how often expensive query results can be recomputed, but doesn't guarantee path quality or modify the cost per permitted calculation. Persistent high-priority agents can starve lower priorities; same-priority agents rotate fairly. Registration is bounded at 128 names and invalid/old nodes are weakly tracked.
- **Independent collision filtering is opt-in.** Only scene roots implementing `set_streaming_physics_active(active)` actually change collision properties. The engine's state does not automatically remove shapes from broadphase or reduce shape memory. Urgent sources can temporarily force near LOD and more expensive colliders even far from the observer, within existing transition budgets.
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
