# cgame_worldgen

Native C++ port of the Cgame GDScript terrain and procedural generation libraries
(`game/scripts/shared/*.gd`). Same behaviour and determinism as the GDScript originals,
without per-cell interpreter cost, and with `WorkerThreadPool` parallelism for the heavy
loops that stay deterministic.

| Class | Port of | Notes |
|-------|---------|-------|
| `CgameHydraulicErosion` | `hydraulic_erosion.gd` | static `erode` (droplets, sequential), `thermal` (parallel, gather form), `max_slope` |
| `CgameTerrainEditLayers` | `terrain_edit_layers.gd` | layers, brushes, splat, undo/redo, dirty chunks, collision queue, chunk export/mesh, **public per-texel delta API** |
| `CgameTerrainSplines` | `terrain_splines.gd` | static `catmull_rom`, `deform` (parallel rows), `bridge_spans` |
| `CgameProceduralCaves` | `procedural_caves.gd` | static `generate` (parallel smoothing), `regions`, `chambers` |
| `CgameProceduralBuildings` | `procedural_buildings.gd` | static `building`, `settlement` |
| `CgameRoadNetwork` | `road_network.gd` | static `connect_sites`, `route_cost` |
| `CgamePCGGraph` | `pcg_graph.gd`, `pcg_presets.gd` | typed pins, subgraphs, `Callable` custom nodes, incremental cache, debugger, partition execution, presets |

## Determinism

All randomness goes through `RandomNumberGenerator` with the same seeding and call order as
the scripts, hashes use the same signed 64-bit `mix64`, and `Variant::hash()` is used where
the scripts call `hash()`. Parallel loops only write memory owned by one row/iteration and
preserve the serial floating point order (thermal erosion uses a gather formulation that
applies contributions in the order the serial scatter loop would), so results do not depend on
thread scheduling. Droplet erosion, the PCG graph evaluation (user callables run on the
calling thread) and the undo stack stay single-threaded.

Numeric parity is by construction (double precision math, float32 storage like GDScript
`Packed*Array`), but bit-identical output against the GDScript runs has not been compared
automatically.

## Terrain edit layer delta API

Editor tools no longer touch private fields. Use `add_layer_from_region`,
`write_layer_region`, `set_layer_texel`, `get_layer_region_deltas/alphas`,
`layer_delta_at`, `layer_alpha_at`, `get_layer_bounds`. These keep layer bounds and dirty
chunks consistent and are not on the undo stack (brush strokes and `fill_layer_rect` are).

## PCG data model

Identical to the GDScript runtime: `Dictionary` values tagged by `"type"` (`points`,
`spline`, `volume`, `landscape`, `mesh_instances`, `scene_instances`, `layer_weights`).
`FastNoiseLite` from the `noise` module drives `density_noise`; if the noise module is
disabled a deterministic hash value noise is used instead (results then differ from the
GDScript runtime).

## GDScript facades

`game_facade/` (repository root) contains facades that prefer these native classes and fall
back to the GDScript implementation in `res://scripts/shared/`:
`hydraulic_erosion.gd`, `terrain_splines.gd`, `procedural_caves.gd`,
`procedural_buildings.gd`, `road_network.gd`, `terrain_edit_layers.gd`, `pcg_graph.gd`.
Static native methods are called through a cached instance (`game_facade/cgame_native.gd`),
so the scripts still parse on engines built without this module.

## Tests

`tests/` holds doctest cases mirroring `tests/test_terrain_authoring.gd`,
`test_terrain_edit_layers.gd`, `test_procedural_graphs.gd` and `test_pcg_graph.gd` plus
cases for the new delta API and the threaded paths. Run with `--test --test-case="*Cgame*"`.
