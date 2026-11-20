# Native World Partition (experimental)

This optional built-in 3D module introduces `WorldPartition3D`, an X/Z-grid scene streamer. It is the **runtime foundation** for larger terrain/foliage/HLOD workflows, not a finished replacement for Unreal World Partition.

## What works

- Register a sparse mapping from `Vector2i` cell coordinates to local `PackedScene` resource paths (saved with your `.tscn` scene).
- Choose a `Node3D` observer, cell size, and square loading/unloading radii; negative coordinates are handled with floor division.
- Add up to 16 extra observer paths for co-op, split-screen, cutscene cameras, portals and predictive prefetch (attach a Node3D in front of a moving character). All source locations share streaming budgets. Streaming scans nearest grid rings across sources, so another observer's central cell is considered before the primary observer's outer rings.
- Keep up to 128 specific gameplay-critical cells resident with `pin_cell`, `unpin_cell` and `clear_pinned_cells`. Pins are prioritized before camera neighborhoods, but respect the same request and instance budgets. Use this for arenas, quest scenes, safe towns and checkpoints; runtime pins do not require an observer and do not create scene mappings.
- Load scene resources asynchronously using Godot's `ResourceLoader.load_threaded_request` backend and poll without blocking while still in progress.
- Share a resource-load request between cells using the same scene path.
- Instantiate `Node3D` cell roots on the main thread, preserving their authored transform and applying the cell origin.
- Cap new requests, simultaneous outstanding requests, instantiation work and out-of-range scene unloads per frame. `max_unloads_per_frame` (default 32) smooths out mass cleanup after teleports; manual clear/remove or disabling streaming always unloads immediately.
- Unload distant cells, apply hysteresis, emit load/unload signals, and keep explicit APIs for moving/replacing/removing cells.
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

Pinned cells load even if no observer is available. Calls are nonblocking; the
regular async resource-loader and per-frame instantiation budgets still apply.
Pins are runtime-only and are not scene registrations or saved gameplay state.
Disabling `streaming_enabled` unloads their scenes but preserves the pins, so
re-enabling streaming restores them. If you remove a cell mapping, pinning does
not re-register the scene.

Each `.tscn` cell must have a `Node3D` root. The authored origin is relative to its cell: cell `(-1, 0)` starts at local `(-128, 0, 0)` with default cell size. The observer is transformed into the world partition node's local space, so moving/rotating the WorldPartition3D node works.

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

The module includes 70 Doctest cases across `test_world_partition_3d.h` (21) and `test_world_partition_3d_extra.h` (49), including disk-backed scenes, origin-offset checks, load/unload hysteresis, duplicate mappings and overflow guards, shared resource requests, and cleanup of failed/pending ResourceLoader tokens. Tests are picked up by Godot's generated module-test list.

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
