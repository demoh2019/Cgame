# Native batched nearest neighbors for procedural road graphs

Cgame extends the engine singleton `Geometry2D`:

```gdscript
var neighbors: Array[PackedInt32Array] = Geometry2D.get_nearest_neighbors(
    positions: PackedVector2Array, neighbor_count: int, max_distance: float)
```

The result has one packed index array per input point. Self indices are excluded, other points at the same location are valid, distance is Euclidean in 2D, and a candidate exactly at `max_distance` is included. Indices are ordered by squared distance, ties by original input index; rows with no matches are empty. Empty input yields an empty outer array; `neighbor_count = 0` yields empty rows.

This is a **batch all-points k-nearest** scan with a fixed-size per-query top-k buffer, no full distance matrix, no caching or shared mutable index. It runs in `O(n² × k)` with `O(k + n*k)` result memory. Validate up to 4,096 finite points and 0–32 neighbors, finite nonnegative radius with finite square. For recurrent dynamic 100k-point queries, spatial hashing or a kd-tree remains preferable.

The design follows the goal of 2D proximity queries in [Unreal TPointHashGrid2](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/GeometryCore/TPointHashGrid2?application_version=5.8) and Unreal PCG's [nearest point from other point](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/PCG/UPCGOctreeQueries/GetClosestPointFromOtherPoint). The Cgame method is deliberately a bounded CPU batch rather than a persistent hash-grid index.

## Integration in Albion After

`game/scripts/shared/world_roads.gd` previously looped over all settlements, built a temporary full nearest list per settlement and sorted it in GDScript. It now packs deterministic seed-derived XZ settlement positions once, evaluates up to 4 nearest points in one native call, then adds undirected graph edges: four choices from the hub, two from other sites, only within 720 metres. Native output is used only when the engine supports the API; a parity-matched GDScript fallback remains on stock Godot. Ties in the fallback now resolve by original point index to match native behavior.

The same shared graph is built on client and server; the previous cached road segments, road mask renderer, grip queries, signposts and underlying path layout are unchanged. No new on-wire state or save format is introduced.

## Tests

- `tests/core/math/test_geometry_2d.cpp`: equal-distance ties, exact radius, duplicate coordinates, zero neighbors, isolated points, empty input and invalid caps.
- `game/tests/test_world_roads.gd`: synthetic tie/radius parity, direct native array contract when present, and seed-derived region road graph comparison with scalar fallback.
- These game checks run in the existing `game/tests/run_all.gd` suite.

Build/test from a Cgame checkout with the correct native executable:

```sh
godot --headless --test --test-case="*batched nearest neighbors*"
godot --headless --path game --script res://tests/run_all.gd
```

Measure road graph build time on a real game seed before claiming performance gains. No C++ compiler or Godot executable is available in this connector session.
