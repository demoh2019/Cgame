# pcg_graph — node-based procedural generation

Unreal-PCG-style graph runtime for Cgame. Everything here is deterministic,
seed-based and independent of how the world is tiled into streaming cells.

## Classes

| Class | Role |
| --- | --- |
| `PCGData` / `PCGPointData` / `PCGSplineData` / `PCGParamData` | Data on graph edges. Points carry position, normal, density, yaw, scale, seed and float attributes (`get_attribute`, `set_attribute`). Every data hashes its content. |
| `PCGContext` | World seed, bounds (AABB), streaming cell, parameter overrides, `height_sampler(x, z) -> float`, `biome_sampler(x, z) -> String`, `water_sampler(x, z) -> bool`, `exclusions` (AABBs or `{center, radius}` cylinders), `user_data` (spline/point sources from the game), `debug`. |
| `PCGNode` | Base node (Resource). Override C++ `execute(inputs, context, seed)` or script `_execute(inputs: Array, context, seed) -> PCGData`, `_get_input_count()`, `_get_category()`. `resolve(property, context)` reads a property with graph-parameter overrides applied (`bind_parameter(property, parameter)`). Nodes must never mutate inputs. |
| `PCGGraph` | Nodes + connections `{from, to, to_port}` + exposed `parameters`. `add_node`, `connect_nodes` (rejects cycles), `compute_order` (dependency order), `validate`. |
| `PCGGraphExecutor` | `execute(graph, context) -> {output, order, timings_usec, total_usec, cache_hits, cache_misses, point_counts, node_outputs (debug)}`; content-addressed cache for incremental recalculation; `execute_async` on the WorkerThreadPool (`job_completed` signal or `wait_for_job`); `format_profile`. |
| `PCGComponent3D` | Scene node running a graph once (`generate`) or streaming cells around a target (`streaming_enabled`, `cell_size`, `streaming_radius`); MultiMesh instances per asset/cluster with `visibility_range_end` (HLOD); signals `cell_generated(cell, points)`, `cell_unloaded(cell)`. |

## Built-in nodes

Samplers: `PCGSurfaceSamplerNode` (jittered world lattice on the height sampler),
`PCGSplineSamplerNode` (points along polylines from input or `user_data[key]`),
`PCGPointSourceNode` (game-provided points with attributes).
Density: `PCGDensityNoiseNode` (deterministic fractal value noise), `PCGDensityFilterNode`.
Filters: `PCGSurfaceFilterNode` (slope/height/water), `PCGBiomeMaskNode`
(biome list + per-biome density), `PCGExclusionFilterNode` (context volumes).
Spatial: `PCGSpatialQueryNode` (keep inside/outside radius of other points or splines),
`PCGSelfPruneNode` (minimum distance). Transform: `PCGTransformNode`.
Asset: `PCGAssetRuleNode` (weighted rule table -> `asset` attribute).
Utility: `PCGMergeNode`, `PCGClusterNode` (`cluster` attribute),
`PCGCountLimitNode` (deterministic budget), `PCGAttributeSetNode`, `PCGOutputNode`.

## Determinism rules for new nodes

* Per-node seed = mix(world seed, node id, seed offset) — never the cell.
* Per-point randomness = `pcg_mix64(point_seed, node_seed)`; point seeds come
  from world-space lattice coordinates or stable source indices.
* Use half-open bounds `[min, max)` when emitting points so neighbouring cells
  never both own a point.
* Override `uses_environment()` to return true when a node reads the context
  samplers, bounds, exclusions or user data (it is then part of the cache key).

Tests: `modules/pcg_graph/tests/test_pcg_graph.h`
(`bin/godot.* --headless --test --test-case="*PCGGraph*,*PCGComponent3D*"`).

## Runtime features

* **Async with script samplers** — `PCGContext.bake_environment(area, step)` reads the
  height/water/biome samplers into grids on the main thread; sampling inside the area
  then never calls scripts, so `execute_async` is thread-safe. `PCGComponent3D.bake_step`
  (default 2 m) does this per async cell. Heights are bilinear between samples.
* **Exclusion volumes** — `PCGExclusionVolume3D` (box or vertical cylinder) in the
  `pcg_exclusion_volumes` group; components gather the volumes overlapping each cell
  (`use_scene_exclusion_volumes`).
* **Persistent procedural cache** — `persistent_cache_dir` (e.g. `user://pcg_cache`)
  stores finished cells (`.pcgcell`, `FileAccess.store_var`); the key covers the graph
  fingerprint, seed, cell, overrides, user data, exclusions and `cache_version`. Script
  samplers cannot be fingerprinted: bump `cache_version` when they change meaning.
  `get_cache_stats()`, `clear_persistent_cache()`.
* **HLOD** — `asset_proxy_meshes` per asset are drawn from `visibility_range_end` to
  `proxy_range_end` (no shadows, cross-faded), per cluster.
* **Runtime debugging** — `debug_draw` draws a cross per point, coloured by asset.

Tests: `tests/test_pcg_runtime_features.h` (`--test-case="*PCGRuntime*"`).
