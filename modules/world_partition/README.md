# Native World Partition (experimental)

This optional built-in 3D module introduces `WorldPartition3D`, an X/Z-grid scene streamer. It is the **runtime foundation** for larger terrain/foliage/HLOD workflows, not a finished replacement for Unreal World Partition.

## What works

- Register a sparse mapping from `Vector2i` cell coordinates to local `PackedScene` resource paths (saved with your `.tscn` scene).
- Choose a `Node3D` observer, cell size, and square loading/unloading radii; negative coordinates are handled with floor division.
- Add up to 16 extra observer paths for co-op, split-screen, cutscene cameras, portals and predictive prefetch (attach a Node3D in front of a moving character). All source locations share streaming budgets. Streaming scans nearest grid rings across sources, so another observer's central cell is considered before the primary observer's outer rings.
- Assign cells to event-driven **Runtime Data Layers** via `cell_layers` and toggle them with `set_layer_enabled(name, bool)`. Disabled layers override even pinned and near-camera cells, but obey unload budgets. `layer_states` supports inspector editing and save-game snapshots; missing layer states default to enabled. Each cell has at most one layer, unlike Unreal's broader actor-layer model.
- Retain cells independently for multiple gameplay systems using **reference-counted cell lease tokens**. `acquire_cell_lease(cell)` returns a token and `release_cell_lease(token)` releases only that owner's request. Limit: 256 active tokens; tokens are runtime-only and must be explicitly released. Query counts with `get_cell_lease_count`, `get_cell_lease_count_total` and `get_leased_cell_count`; `clear_cell_leases` releases all. The usual background request/instantiation budgets and inactive Data Layer gates still apply.
- Keep up to 128 specific gameplay-critical cells resident with `pin_cell`, `unpin_cell` and `clear_pinned_cells`. The `pinned_cells` property also appears in the inspector and is serialized with the node for design-time always-loaded areas. Pins are prioritized before camera neighborhoods, but respect the same request and instance budgets. Use this for arenas, quest scenes, safe towns and checkpoints; runtime pins do not require an observer and do not create scene mappings.
- Load scene resources asynchronously using Godot's `ResourceLoader.load_threaded_request` backend and poll without blocking while still in progress.
- Share a resource-load request between cells using the same scene path.
- Instantiate `Node3D` cell roots on the main thread, preserving their authored transform and applying the cell origin.
- Cap new requests, simultaneous outstanding requests, instantiation work and out-of-range scene unloads per frame. `max_unloads_per_frame` (default 32) smooths out mass cleanup after teleports; manual clear/remove or disabling streaming always unloads immediately.
- Unload distant cells, apply hysteresis, emit load/unload signals, and keep explicit APIs for moving/replacing/removing cells.
- Dispatch optional streamed-scene lifecycle hooks `streaming_activated(cell)` and `streaming_deactivating(cell)` before the existing load/unload signals. These run after gameplay state restoration and before `queue_free()` respectively. New native signals `cell_activated` and `cell_deactivating` let AI, physics and navigation systems prepare or detach. On-demand `get_cell_simulation_stats(cell)` reports PhysicsServer3D collision objects/shapes and NavigationServer3D regions in the instantiated scene hierarchy.
- Preserve per-cell gameplay progress with optional scene-root callbacks `capture_streaming_state() -> Dictionary` and `restore_streaming_state(state: Dictionary)`. The native streamer captures state when a cell unloads and restores it when the scene re-enters, after `_ready()`.
- Export and import **deep-copied** runtime state with `snapshot_cell_states()` / `load_cell_states(Dictionary)`; read or edit single cells with `get_cell_state`, `set_cell_state`, `has_cell_state`, `erase_cell_state`, `clear_cell_states` and `get_cell_state_count`. State remains cached when scene registrations are removed, until explicitly erased, and is not automatically written to disk.
- Query currently instantiated cell scene roots with `get_cell_instance(cell)` for safe per-cell visual proxy control. The method returns `null` after unload instead of a stale pointer.
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
```

Extra observers work like additional streaming sources (as in other open-world engines):

```gdscript
# Optional: both players keep nearby cells loaded.
world.additional_observer_paths = [world.get_path_to($OtherPlayer)]
# A Node3D moved ahead of a fast vehicle can also act as a prefetch source.
# Paths resolve relative to WorldPartition3D; invalid paths are ignored.
```

Pin a gameplay-critical scene independent of camera range:

```gdscript
# The scene must first be registered, just like any spatially streamed cell.
world.pin_cell(Vector2i(0, 0)) # Keep a quest hub loaded during a mission.
assert(world.is_cell_pinned(Vector2i(0, 0)))
# When the quest ends, allow the regular distance-based unloading policy.
world.unpin_cell(Vector2i(0, 0))
```

Pinned cells load even if no observer is available. Releasing the last pin
causes budgeted cleanup even when no observer exists; temporary loss of an
observer alone still preserves loaded cells. Calls are nonblocking; the
regular async resource-loader and per-frame instantiation budgets still apply.
Pins are runtime-only and are not scene registrations or saved gameplay state.
Disabling `streaming_enabled` unloads their scenes but preserves the pins, so
re-enabling streaming restores them. If you remove a cell mapping, pinning does
not re-register the scene.

Each `.tscn` cell must have a `Node3D` root. The authored origin is relative to its cell: cell `(-1, 0)` starts at local `(-128, 0, 0)` with default cell size. The observer is transformed into the world partition node's local space, so moving/rotating the WorldPartition3D node works.

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
distance, multiple observers and pinned-cell residency. The properties are
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
atlases or builds HLOD layers. Mesh/scene import, source file changes and
performance on the intended hardware still require validation.

## Tests

The module includes 91 Doctest cases across `test_world_partition_3d.h` (21) and `test_world_partition_3d_extra.h` (70), including disk-backed scenes, origin-offset checks, load/unload hysteresis, duplicate mappings and overflow guards, shared resource requests, and cleanup of failed/pending ResourceLoader tokens. Tests are picked up by Godot's generated module-test list.

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[WorldPartition3D]*"
```

**Validation status:** Source changes and test cases are present, but a Godot binary/compiler toolchain capable of building this fork was not available to the authoring environment. CI build and test execution must pass before treating the module as production-ready.

## Non-goals and limitations

- **No general-purpose editor partitioner or mesh-merging HLOD baker yet.** The demo has a specialized offline forest proxy exporter, but arbitrary authored scenes still require their own cell splitter and asset-generation pipeline.
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
