# Predictive open-world streaming and unified CPU frame budget

Albion After / Cgame Godot fork, `develop`.

The open world streams generated chunks containing terrain, trees, buildings,
foliage and loot. This release refines how the *existing* scene streamer
schedules costly work; it does **not** modify world seeds, coordinates,
authoritative server inventory, pathfinding or network packets.

## Comparison with production engines

- **Unreal Engine World Partition** uses spatial grid cells, streaming sources
  and source priority; HLOD reduces distant detail and data residency.
- **Unity runtime loading** does background data work but meters main-thread
  object activation according to its loading priority/time budget.
- **Godot MultiMesh** draws many objects in one call but culls a complete
  MultiMesh instance as one spatial object. Albion After already partitions
  decorative instances into local cells.

The added implementation follows those principles without pretending to be
Unreal World Partition, Unity Entities Graphics or Nanite.

## Native engine changes

`scene/main/world_streamer.cpp` uses *one* `frame_budget` and *one*
`frame_started_usec` timestamp throughout its internal-process update:

1. Finalize completed background scene loads from the closest eligible cells.
2. Refresh the predicted priority list, with the true camera/player focus and
   existing load/unload hysteresis controlling residency.
3. Generate procedural chunks using only the **remaining** main-thread count
   and CPU time allowance.

Both activation and generator callbacks count as work. An unsuccessful
generator call also consumes a slot (it may have taken significant CPU time).
A disabled streamer never activates or generates queued chunks. Explicit
`refresh()` gets its own **single combined** budget.

`max_instantiations_per_frame` is a hard cap on chunk calls/activations in a
streamer update. `max_chunk_work_usec` is a *soft* time budget: a single
generator callback cannot be interrupted, so one expensive chunk can still
take longer than requested.

The new read-only `get_queued_generation_count()` exposes waiting procedural
cells; this is intentionally distinct from `get_pending_count()` for
asynchronous scene files. The query does not process or allocate chunks.

## Player-facing improvements

`game/scripts/client/world_streaming_policy.gd` adjusts the forward
streaming *priority* based on movement:

| Player mode | Prediction horizon | Reason |
| --- | --- | --- |
| Stopped / no valid velocity | 0 s | Prefer nearest cells; teleports don't prefetch the stale direction |
| Walking | 2 s | Smooth terrain/prop arrival without expanding the load radius |
| Riding the bike | 3 s | Bring content in front of a faster player earlier |

The game retains the current **150 m initial load radius**, **220 m unload
hysteresis**, **3 chunks maximum per update** and **2.5 ms soft CPU budget**,
later updated by the existing quality profiles. Prediction changes queue
order only: it never extends the actual load radius or adds new assets.

The optional FPS overlay now shows `World: N chunks | M queued` alongside
FPS, frame time and draw calls. It updates every 0.25 seconds **only while the
player has enabled the FPS overlay**, not every frame.

## Validation

- Engine files: `scene/main/world_streamer.{h,cpp}`, `doc/classes/WorldStreamer.xml`
- Gameplay: `game/scripts/client/online_main.gd`,
  `game/scripts/client/world_streaming_policy.gd`
- UI: `game/scripts/client/ui_accessibility_layer.gd`
- Native integration test: `game/tests/test_world_streamer_shared_budget.gd`,
  registered in both game test suites

To verify on a rebuilt Cgame engine:

```sh
godot --headless --path game --script res://tests/run_graphics.gd
```

Test walking, sprinting, cycling, turning 180°, and being teleported while
near a chunk boundary. Monitor frame-time p95/p99 (CPU and GPU separately),
chunks per frame, queued cells, memory residency, and pop-in. Profile on
Apple M1 Metal and low-end Compatibility. This is a source-level improvement;
it is **not** a measured FPS claim.

References:

- https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
- https://docs.unity.com/en-us/engine/7000.0/script-reference/unityengine/application/backgroundloadingpriority
- https://docs.godotengine.org/en/stable/classes/class_multimesh.html
