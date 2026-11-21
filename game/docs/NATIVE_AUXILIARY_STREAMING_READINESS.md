# Native auxiliary streaming-source readiness

Unreal Engine World Partition exposes `Is Streaming Completed` on its streaming sources, enabling users to distinguish a requested streaming area from a **completed** one. The Cgame `WorldStreamer` now offers a bounded, read-only counterpart for its existing near-waypoint auxiliary source.

## Engine API

```gdscript
streamer.set_auxiliary_source(Vector3(40, 0, 8), 12.0)
print(streamer.get_auxiliary_source_progress()) # 0.0–1.0, baseline scene readiness
print(streamer.get_auxiliary_source_pending_count())
print(streamer.get_auxiliary_source_failed_count())
print(streamer.is_auxiliary_source_ready()) # True only after all cells settle.
print(streamer.is_auxiliary_source_ready(true)) # Also waits for staged cosmetic detail.
```

The engine examines at most **64 intersecting source cells**, using the same radius cap and grid enumeration as the existing auxiliary scheduler. A cell counts as complete when its scene is alive or when a generator intentionally reported an empty cell. Failed cells are explicitly excluded and block readiness. With `require_visual_details = true`, a loaded scene reporting `has_pending_visual_detail()` must later call `mark_visual_details_ready(cell)` before it becomes fully ready.

Disabled, far-away (dormant), invalid-focus and disabled-streamer states **fail closed**: zero progress, zero pending/failed cells, and false readiness. A source must be within the existing `load_radius + cell_size` limit; no remote scene island is instantiated. Unloading/resetting scenes or moving the source automatically affects the next queried snapshot.

These APIs are **diagnostics only**. They never allocate scene nodes, retry failed loads, perform physics/navigation synchronization or imply safety for instant teleport. They do not modify generation queues, budget limits, route priority, or server authority.

## Albion After integration

The client assigns its existing `WorldStreamer` to its `WorldMap` after construction. On the expedition map, when a nearby personal waypoint matches the **active auxiliary source**, a small line displays `Scenery prefetch: N%`, `ready`, `retrying`, or `Terrain ready; details finish on approach` when the scene is loaded but staged cosmetics are deferred by simulation LOD. The indicator uses full visual readiness and only queries while the map is drawn. It never exposes private markers to the network and is hidden for out-of-range/stale waypoints or older binaries without the API.

## Tests

- `game/tests/test_auxiliary_streaming_readiness.gd` validates disabled/remote source states, real chunk-generation progress, null/empty chunks, staged visual completion, source clearing, failed generation and retry recovery, and live map captions.
- `game/tests/run_auxiliary_readiness.gd` runs a focused engine-plus-game suite, included in native streamer CI.
- Run with the custom Cgame engine: `godot --headless --path game --script res://tests/run_auxiliary_readiness.gd`

Related Unreal docs: https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
