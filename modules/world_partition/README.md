# Native World Partition (experimental)

This optional built-in 3D module introduces `WorldPartition3D`, an X/Z-grid scene streamer. It is the **runtime foundation** for larger terrain/foliage/HLOD workflows, not a finished replacement for Unreal World Partition.

## What works

- Register a sparse mapping from `Vector2i` cell coordinates to local `PackedScene` resource paths (saved with your `.tscn` scene).
- Choose a `Node3D` observer, cell size, and square loading/unloading radii; negative coordinates are handled with floor division.
- **Actor-bound moving sources:** `set_streaming_source_node(name, path, load_radius, unload_radius, priority)` lets a second camera, drone, AI actor or scripted cutscene move its streaming region automatically via a `NodePath` relative to the WorldPartition3D node. The engine resolves the Node3D each streaming update, converts its global transform into the partition's local grid, and keeps the same priorities, resource budgets and unload hysteresis as fixed sources. Missing/reparented/freed nodes suspend that source (active=false, readiness=false, progress=0); stale remote cells unload unless another source/pin wants them. The source configuration persists so it resumes automatically if the same NodePath resolves again. `get_streaming_source(name)` returns the last center, active status and node_path. Updating it with `set_streaming_source` converts it back to a fixed coordinate source. Max 8 sources total.
- **Named multi-source streaming:** up to **8** independent sources with `set_streaming_source(name, center, load_radius, unload_radius, priority)`. Source load radii are 0–4 cells, unload radii 0–8 (at least load radius), priorities 0–100. Nearby player cells are always serviced first, then manual pins, then named sources by descending priority, then predictive prefetch. `get_streaming_source(name)`, `get_streaming_source_names()`, `get_streaming_source_count()`, `remove_streaming_source(name)`, `clear_streaming_sources()` provide control and diagnostics. `is_streaming_source_ready(name)` checks entire region, while `get_streaming_source_progress(name)` reports the fraction of scene-instantiated cells; `streaming_source_ready(name)` and `streaming_source_unready(name)` signal scene-tree completion transitions. One cell overlapping multiple sources is instantiated once, and all sources share the same per-frame budgets.
- **Manually pinned regions:** `pin_cell(cell)`, `unpin_cell(cell)`, `is_cell_pinned(cell)`, `get_pinned_cell_count()`, `clear_pinned_cells()`. Keep up to **16** registered cells available beyond the observer's normal radii (e.g. quest locations or fast-travel destinations). Near-observer cells still receive first priority, pins are serviced before predictive prefetch, and all share the asynchronous request/instantiation limits. Missing/unregistered pins fail; duplicate pins are idempotent. Pinning never blocks, so verify `is_cell_loaded(cell)` before teleporting. Pins are removed when their cell is unregistered or all registrations are replaced/cleared.
- Optionally prefetch a short directional corridor with `prefetch_direction` (each axis -1, 0 or 1) and `prefetch_distance` (0–4 cells, off by default). Cells within the observer's normal radius always have priority. When direction changes, obsolete ahead cells unload if outside hysteresis; resource requests remain shared and budgets are enforced across both passes.
- Load scene resources asynchronously using Godot's `ResourceLoader.load_threaded_request` backend and poll without blocking while still in progress.
- Share a resource-load request between cells using the same scene path.
- Instantiate `Node3D` cell roots on the main thread, preserving their authored transform and applying the cell origin.
- Cap new requests, simultaneous outstanding requests, and instantiation work per frame.
- Optionally cap successive main-thread instantiations with `max_instantiation_time_ms` (default 0 = disabled). The first ready cell always loads, preventing starvation; a single expensive `_ready()` may still exceed the soft budget.
- Unload distant cells, apply hysteresis, emit load/unload signals, and keep explicit APIs for moving/replacing/removing cells.
- Runtime diagnostics: `get_pending_cell_count()`, `get_inflight_request_count()` (deduplicated resource paths), and `get_failed_cell_count()` for HUDs and performance tools.
- **Explicit failure recovery:** `retry_failed_cells()` clears error suppression on demand after a broken asset/path is repaired. It does not retry failures every frame or change registered cell paths; call `update_streaming()` to trigger an immediate reattempt.
- **CPU profiling:** `get_last_streaming_update_ms()` measures the latest update's wall-clock CPU time (polling and scene instantiation) and `get_last_instantiation_attempt_count()` reports attempted instantiations. These are diagnostics, not GPU time or physics-server completion guarantees.
- **Direct cell scene lookup:** `get_cell_node(cell)` returns the loaded Node3D root (or `null`) using the native cell index. Call from `cell_loaded` to configure one cell without scanning all streamed children.
- **Region readiness queries:** `are_cells_loaded(center, radius=0)` returns true only when every cell in the square is instantiated. Useful for spawn/teleport gates, AI activation and gameplay dependencies; scene instantiation does not guarantee downstream physics/asset upload readiness.
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
    world.prefetch_direction = Vector2i(1, 0)
    world.prefetch_distance = 2 # preload up to 2 cells ahead
    world.max_new_requests_per_frame = 2
    world.max_instances_per_frame = 2
    world.observer_path = world.get_path_to($Player)
    world.set_cell_scene(Vector2i(0, 0), "res://world/0_0.tscn")
    world.set_cell_scene(Vector2i(-1, 0), "res://world/-1_0.tscn")
    world.set_cell_scene(Vector2i(10, -4), "res://world/distant_outpost.tscn")
    world.pin_cell(Vector2i(10, -4)) # now registered, load in background
    world.set_streaming_source("survey", Vector2i(10, -4), 0, 1, 75) # radius 0 needs only the configured center cell
    world.set_streaming_source_node("camera", world.get_path_to($SecondaryCamera), 1, 2, 80)
```

Each `.tscn` cell must have a `Node3D` root. The authored origin is relative to its cell: cell `(-1, 0)` starts at local `(-128, 0, 0)` with default cell size. The observer is transformed into the world partition node's local space, so moving/rotating the WorldPartition3D node works.

## Inspecting streaming load

```gdscript
# Poll sparingly (for example 4 Hz), not necessarily every render frame.
var loaded := world.get_loaded_cell_count()
var queued := world.get_pending_cell_count()
var requests := world.get_inflight_request_count()
var failed := world.get_failed_cell_count()
```

You can also inspect `world.get_pinned_cell_count()` to track manual residency requests. Inspect `world.get_streaming_source_count()` to track additional region sources; use `world.is_streaming_source_ready("survey")` before entering a remote location.

These counters describe the current state, not a prediction of future memory or throughput. One background resource request may serve multiple pending cells with the same PackedScene path. See `misc/cgame_forest_showcase` for a 1,024-cell registered world with a short distance-based active radius, directional predictive prefetch, reusable terrain resources and headless streaming regressions.

## Tests

The module includes 64 Doctest cases across `test_world_partition_3d.h` (28) and `test_world_partition_3d_extra.h` (36), including disk-backed scenes, origin-offset checks, load/unload hysteresis, duplicate mappings and overflow guards, shared resource requests, and cleanup of failed/pending ResourceLoader tokens. Tests are picked up by Godot's generated module-test list.

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[WorldPartition3D]*"
```

**Validation status:** Source changes and test cases are present, but a Godot binary/compiler toolchain capable of building this fork was not available to the authoring environment. CI build and test execution must pass before treating the module as production-ready.

## Non-goals and limitations

- **Streaming sources are runtime-only, bounded and square.** They don't author/bake region assets, add network replication, or guarantee physics-server/navmesh synchronization. A secondary source requires a valid main observer path to keep the streamer active.
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
