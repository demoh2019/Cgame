# Terrain mesh streaming: shared main-thread time slice

## Why this feature exists

`ChunkedTerrain3D` can generate and upload several uncached LOD meshes in one scene update. In a large open world, multiple streamed terrain nodes can enter the scene during the same process frame; CPU mesh construction and GPU resource submissions may cause noticeable frame-time hitches despite otherwise high FPS.

Unreal Engine's level streaming exposes per-frame component-registration budgets and its texture streamer processes new level data incrementally. Unity's mesh/texture upload system also offers an upload time slice. This implementation applies the **time-slicing principle to the custom Godot terrain mesh generator**, not to the entire texture streamer or generic GPU uploader.

## Native Godot engine

New opt-in `ChunkedTerrain3D` API:

- `mesh_build_budget_usec`: integer CPU budget, 0–20,000 microseconds; **default 0** preserves legacy eager mesh generation.
- `get_pending_mesh_build_count()`: reports deferred mesh builds after the last automatic update.
- `force_update()`: remains synchronous, to support editor tools, explicit teleport prewarming and existing tests.

All native terrain nodes share one main-thread per-process-frame ledger. When a chunk needs an uncached LOD mesh, the terrain renderer checks the elapsed microseconds since the first streaming update in that frame. It defers further mesh construction after the budget is exhausted; this is a **soft** budget because a single mesh build is atomic and may exceed the limit.

To prevent starvation, **the first missing mesh of the frame always builds**. Subsequent work is attempted on the next process frame; deferred chunks are reevaluated without waiting for their usual 0.16–0.5 s LOD update interval. Cached mesh switches do not consume the build budget.

When a chunk is already visible at an earlier LOD, that existing RenderingServer mesh remains visible until its replacement is ready. The code preserves existing GI participation, cast-shadow flags, terrain materials, LOD selection, normal morphing, per-vertex shading, CPU collision policy and server-authoritative gameplay.

The limiter is **not** a new worker-thread pipeline. Mesh building and RenderingServer operations remain on the main thread for compatibility. Since all Albion After terrain nodes use the same graphics tier, they have the same shared budget; the smallest budget wins if different terrain nodes are configured separately.

## Albion After integration

The game sets the native property **before** adding each new terrain node to the SceneTree. Graphics quality changes retune existing terrain via the current `aa_chunked_terrain_lod` group instead of recreating world geometry.

| Graphics preset | Global native mesh-build time slice |
| --- | ---: |
| Performance | 900 µs / frame |
| Balanced | 1,500 µs / frame |
| High | 2,300 µs / frame |
| Ultra | 3,500 µs / frame |

These values are **initial tuning targets**, not measured per-GPU optima. Quality tiers can allow more CPU generation work because their visible mesh detail and streaming distances are larger. The scheduler preserves lighting, collision, network state and native LOD behavior. The game never changes authoritative world generation because of the streaming budget.

## Testing and performance acceptance

After rebuilding the customized Godot engine, run the native tests in `tests/scene/test_chunked_terrain_3d.cpp` and:

```bash
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

The tests cover the native policy (zero-budget fallback, first-mesh progress, exhausted time slice), clamp handling, deferred mesh counters, synchronous `force_update`, quality-tier budgets, live reconfiguration and initial game-chunk configuration.

Visual QA: walk and teleport into a large forest or city with many new streamed chunks. Verify newly visible distant terrain populates over subsequent frames, the character does not fall through the ground (authoritative game collision remains unchanged), and an already visible LOD never disappears when a finer mesh is deferred. Repeatedly change High/Ultra and Performance/Balanced while crossing chunk boundaries.

Measure **main-thread p50/p95/p99 frame time**, number of deferred meshes, terrain visibility pop-in latency, mesh building costs, and p50/p95 GPU time on target devices. Compare before/after using identical camera movement and world seeds. The budget helps distribute CPU spikes; it does not reduce total triangle generation or guarantee a particular FPS uplift.

**Requires a rebuilt custom engine; native compilation and actual CPU/GPU benchmarking are not available in this session.**

## Priority within a terrain node

The native limiter previously walked chunk meshes in height-grid storage order. When the CPU time slice had run out, a near-camera patch with missing geometry could wait behind a far or offscreen LOD, producing avoidable pop-in.

The engine now exposes **`ChunkedTerrain3D.mesh_streaming_priority`** with three modes:

| Mode | Streaming order | Use |
| --- | --- | --- |
| 0 | Original row-major order | Legacy engine scenes, tests and tools (default) |
| 1 | Missing visible meshes first, then distance to focus | Performance |
| 2 | Same, with a bounded camera-facing preference | Balanced, High and Ultra |

Both new and already loaded Albion After terrain nodes receive this property through `ChunkView.configure_terrain_streaming_priority` / `apply_terrain_streaming_priority`. A fixed 35% multiplier makes camera-facing chunks load earlier without rejecting terrain behind the player. When the camera is unavailable the mode-2 priority degrades to mode-1 distance order. Ties use stable source-grid indices.

**The priority pass is local to each `ChunkedTerrain3D` node.** It does not implement a fully global ranked list of every terrain chunk. The CPU time-slice budget remains shared across all terrain nodes, preventing their costs from adding independently. The optional priority pass runs only when a node has multiple chunks, an active viewer and a positive mesh-build budget. Large native terrain nodes use an O(N log N) sort over small temporary records; the world game's 64 m terrain nodes each contain only four 16-quad render subchunks. Existing mesh caches, geomorph targets, normal streams, PBR materials and collision flags are unchanged.

When an upgrade is deferred, the engine preserves both the visible mesh and its existing geomorph shader parameter, avoiding a transient shading or silhouette jump while that upgrade is waiting. Neither priority mode alters the selected LOD, geometry accuracy, shadows or lighting; it changes only **which pending CPU construction finishes first**.

Engine regression tests in `tests/scene/test_chunked_terrain_3d.cpp` cover stable ordering, visible holes before upgrades, facing-direction weighting, extreme inputs and backward-compatible property clamping. `game/tests/test_terrain_mesh_streaming.gd` checks new terrain nodes, quality presets and live retuning. Benchmark near-camera terrain pop-in latency during teleports, rapid forward movement and 180-degree camera turns. Also monitor CPU p95/p99 frame time and pending mesh counts to ensure the sort cost stays below the existing time slice.

The implementation is inspired by Unreal Engine World Partition streaming-source priorities and Unity's throttled runtime asset integration, but is not identical to either engine's internal streamer. The C++ source needs a custom Godot rebuild and actual hardware validation before any measured performance benefit is claimed.

