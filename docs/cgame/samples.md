# Sample-project guides

Four step-by-step builds that use the real library APIs. Each guide ends with the existing headless test that
exercises the same calls; those tests are the reference for exact behaviour. The snippets below are assembled
from the function signatures in the [API reference](api/index.md) and those tests. They are not themselves run by CI.

Common setup for every sample: create a scene with a `Node3D` root and a script on it. Load libraries with
`preload` (scripts have no `class_name`):

```gdscript
const WorldPartitionBake = preload("res://scripts/shared/world_partition_bake.gd")
const PCGGraph = preload("res://scripts/shared/pcg_graph.gd")
const PCGPresets = preload("res://scripts/shared/pcg_presets.gd")
const MassEntity = preload("res://scripts/shared/mass_entity.gd")
const CrowdAvoidance = preload("res://scripts/shared/crowd_avoidance.gd")
const Meshlets = preload("res://scripts/shared/meshlets.gd")
const ClusterLod = preload("res://scripts/shared/cluster_lod.gd")
const OcclusionRaster = preload("res://scripts/shared/occlusion_raster.gd")
```

Run any sample headless with
`godot --headless --path game --script res://path/to/sample.gd` (extend `SceneTree`, work in `_initialize()`, call `quit()`).

---

## 1. Large world partition

Goal: split a big list of actors into streamable cells, keep some actors always loaded, switch data layers,
re-bake only what changed, and decide each frame which cells to load. API page: [`world_partition_bake`](api/shared/world_partition_bake.md).
Reference test: `game/tests/test_world_partition_bake.gd`.

1. **Describe actors** as Dictionaries. Keys read by `bake()`: `guid` (String; a stable one is generated from position and index if empty),
   `position` (Vector3), `bounds` (AABB), `layers` (PackedStringArray), `spatially_loaded` (bool, default true), `data` (Dictionary).

   ```gdscript
   func _actor(guid: String, pos: Vector3, size: float, layers: PackedStringArray = PackedStringArray(), loaded: bool = true) -> Dictionary:
   	return {"guid": guid, "position": pos, "bounds": AABB(pos - Vector3.ONE * size * 0.5, Vector3.ONE * size),
   		"layers": layers, "spatially_loaded": loaded, "data": {"name": guid}}
   ```

2. **Generate the actors.** For a large world, loop over a grid, or take them from the [PCG sample](#2-pcg-graph).
   Use `wp.stable_guid("tree|%d|%d" % [x, z])` for reproducible ids. Actors with `spatially_loaded = false` (sky, global managers) go to the always-loaded list.

3. **Bake.** `bake(actors, cell_size, loading_range_by_layer)` returns `{cell_size, cells, always_loaded, layers, actors}`.
   Pass a `"default"` range and optional per-layer ranges; without a range an actor's cell uses twice its level's cell size.

   ```gdscript
   var wp := WorldPartitionBake.new()
   var baked: Dictionary = wp.bake(actors, 64.0, {"default": 200.0, "Night": 120.0})
   var cells: Dictionary = baked["cells"]   # key "group|level|x|z" -> {level, x, z, group, layers, bounds, actors, range}
   ```

   Actors bigger than a cell are placed on a coarser level automatically (up to level 8).

4. **Build HLOD clusters** for far views: `wp.hlod_clusters(cells, 4)` groups 4 x 4 cells per cluster in each cell's own level, keeping layer groups separate.
   The function returns the cluster descriptions; generating proxy meshes is up to you.

5. **Persist one file per actor** so version control and editors touch one actor at a time:
   `wp.split_one_file_per_actor(actors, "user://world/actors")` writes `<guid>.json` through a temp file and rename and returns the number written;
   `wp.load_actors("user://world/actors")` reads them back.

6. **Re-bake incrementally.** After editing, bake again into a second `WorldPartitionBake` instance (or keep the old result) and call
   `wp.diff_bakes(old_bake, new_bake)`. The result has `added`, `removed`, `moved`, `changed` and `dirty_cells`; only the dirty cells need regenerating.

7. **Stream at runtime.** Each frame, ask which cells to hold, passing the player position, velocity (predictive look-ahead along
   `lookahead_seconds`, default 1.5, using `lookahead_samples`, default 3) and the data layers currently enabled. Cells of other layers are skipped; the result is sorted nearest first.

   ```gdscript
   var wanted: Array = wp.cells_to_load(player.global_position, player.velocity, PackedStringArray(["Night"]))
   # diff `wanted` against the set of loaded cells: instantiate the new keys, free the missing ones
   ```

8. **Navigation across cells.** Give each cell a navmesh tile and link them with `navmesh_stitching.gd`
   (tile dictionaries `{origin, size, polygons}`); see the same test file for a worked example.

Things to know: the library produces data, not scenes - you own instancing and freeing. Streaming distance is a plain XZ distance to the cell bounds.
The editor addon `game/addons/cgame_world_partition` provides editor-side tooling for the same concepts.

---

## 2. PCG graph

Goal: scatter trees and rocks over terrain, clear a road corridor, and get engine-ready instance transforms.
API pages: [`pcg_graph`](api/shared/pcg_graph.md), [`pcg_presets`](api/shared/pcg_presets.md). Reference test: `game/tests/test_pcg_graph.gd`.

1. **Make the inputs**, which are typed data Dictionaries:

   ```gdscript
   var land: Dictionary = PCGGraph.make_landscape(func(x: float, z: float) -> float: return sin(x * 0.05) * 3.0 + cos(z * 0.07) * 2.0)
   var vol: Dictionary = PCGGraph.make_volume(AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120)))
   var road: Dictionary = PCGGraph.make_spline(PackedVector3Array([Vector3(-60, 0, 0), Vector3(0, 0, 0), Vector3(60, 0, 0)]))
   ```

   `make_landscape` also accepts a `normal_at` callable; when omitted normals come from finite differences.

2. **Start from a preset.** `PCGPresets.forest_scatter(graph_seed)` has graph inputs `volume`, `landscape`, `road` and outputs `trees`, `rocks`, `floor`.
   Always validate before running:

   ```gdscript
   var forest: PCGGraph = PCGPresets.forest_scatter(1337)
   assert(forest.validate().is_empty())
   var out: Dictionary = forest.execute({"volume": vol, "landscape": land, "road": road})
   ```

3. **Read the outputs.** `out["trees"]` is `{type: "mesh_instances", records: [{mesh_id, transforms: Array[Transform3D]}]}`; feed each record to a `MultiMeshInstance3D`.
   `out["floor"]` is `layer_weights` for material painting; `PCGGraph.point_count(out["floor"])` equals the number of trees (tested).

4. **Or build your own graph.** Nodes are added by type and wired pin to pin. The preset shows the pattern:

   ```gdscript
   var g := PCGGraph.new()
   g.graph_seed = 7
   g.add_graph_input("in_volume", "volume", "volume")
   g.add_graph_input("in_land", "landscape", "landscape")
   g.add_node("sample", "surface_sampler", {"spacing": 4.0, "jitter": 0.8})
   g.add_node("prune", "self_pruning", {"min_distance": 2.5})
   g.add_node("rocks", "static_mesh_spawner", {"mesh_id": "rock_mossy"})
   g.add_graph_output("out_rocks", "rocks", "mesh_instances")
   g.link("in_volume", "out", "sample", "volume")
   g.link("in_land", "out", "sample", "landscape")
   g.link("sample", "out", "prune", "in")
   g.link("prune", "out", "rocks", "in")
   g.link("rocks", "out", "out_rocks", "in")
   ```

   Node types registered by default: `surface_sampler`, `spline_sampler`, `volume_sampler`, `density_noise`, `density_filter`, `self_pruning`, `difference`,
   `transform_points`, `attribute_set`, `merge`, `partition_by_attribute`, `copy_points`, `constant_volume`, `static_mesh_spawner`, `instanced_scene_output`, `material_layer_output`.

5. **Add a custom node** with `register_node(type, input_pins, output_pins, execute)`; the callable takes `(inputs)`, `(inputs, params)` or `(inputs, params, ctx)`
   and returns a Dictionary of output pin name to data. `ctx` carries `node_seed`, `has_bounds`, `bounds`, `node_id`. Never mutate `inputs`.

6. **Iterate quickly.** Change a parameter with `set_param(id, key, value)` and run again: unchanged upstream nodes come from the cache
   (`gi.debug[node_id]["executed"]` tells which ran; set `debug_capture_full = true` to keep full outputs for inspection).

7. **Partition the work.** For a world-partition grid, run one cell at a time:
   `graph.partition_execute(Vector2i(cx, cz), cell_size, {"volume": vol}, margin)`. Sampling is restricted to the cell and outputs are cropped to it,
   so the union of all cells equals an unpartitioned run. Use `margin` (for example `12.0`) when nodes such as `self_pruning` need neighbours.

8. **Feed the world partition sample.** Turn each `transforms` entry into an actor dictionary (guid via `stable_guid`) and bake as in guide 1.

Determinism: results depend only on `graph_seed`, inputs and parameters. The game's own use is in `client/pcg_world_dressing.gd` and `server/pcg_spawns.gd`.

---

## 3. Mass crowd simulation

Goal: simulate a few thousand agents with data-oriented storage and ORCA avoidance, on the CPU.
API pages: [`mass_entity`](api/shared/mass_entity.md), [`crowd_avoidance`](api/shared/crowd_avoidance.md). Reference test: `game/tests/test_mass_crowd.gd`.
The repo does not record an agent-count budget; measure with `trace_capture` or `perf_regression` (see [tools](experimental-systems.md#25-tools-and-diagnostics)) before choosing a number.

1. **Define fragments.** Only three packed types are supported:

   ```gdscript
   var w := MassEntity.new()
   w.define_fragment("pos", TYPE_PACKED_VECTOR3_ARRAY)
   w.define_fragment("vel", TYPE_PACKED_VECTOR3_ARRAY)
   w.define_fragment("goal", TYPE_PACKED_VECTOR3_ARRAY)
   ```

2. **Spawn agents.** `create()` takes `{fragment: initial_value}` and returns an entity id (24-bit index plus generation).
   Entities with the same fragment set share an archetype (the order of keys does not matter).

   ```gdscript
   for i in 2000:
   	var p := Vector3(randf_range(-50.0, 50.0), 0.0, randf_range(-50.0, 50.0))
   	w.create({"pos": p, "vel": Vector3.ZERO, "goal": -p})
   ```

3. **Write processors.** A processor is `Callable(chunk: Dictionary, count: int, delta: float)`. A chunk holds one packed array per fragment
   name (plus `_ids`, `_count`) for one archetype; write through `chunk["pos"][i] = v`.
   Register with `add_processor(name, required_fragments, callable, depends_on, parallel)`; `depends_on` gives ordering (stable topological sort), `parallel = true` runs chunks on the worker pool.

4. **Steer, avoid, integrate.** ORCA works on `PackedVector2Array` (XZ plane): positions, current velocities, preferred velocities, then
   `radius, max_speed, time_horizon, neighbor_dist, max_neighbors, time_step`; it returns new velocities in the same order.

   ```gdscript
   func _avoid(chunk: Dictionary, count: int, delta: float) -> void:
   	var pos2 := PackedVector2Array()
   	var vel2 := PackedVector2Array()
   	var pref := PackedVector2Array()
   	for i in count:
   		var p: Vector3 = chunk["pos"][i]
   		var v: Vector3 = chunk["vel"][i]
   		var g: Vector3 = chunk["goal"][i]
   		pos2.append(Vector2(p.x, p.z))
   		vel2.append(Vector2(v.x, v.z))
   		pref.append((Vector2(g.x, g.z) - Vector2(p.x, p.z)).limit_length(1.4))
   	var nv: PackedVector2Array = CrowdAvoidance.compute_velocities(pos2, vel2, pref, 0.4, 1.4, 5.0, 6.0, 16, 0.1)
   	for i in count:
   		chunk["vel"][i] = Vector3(nv[i].x, 0.0, nv[i].y)

   func _integrate(chunk: Dictionary, count: int, delta: float) -> void:
   	for i in count:
   		chunk["pos"][i] = chunk["pos"][i] + chunk["vel"][i] * delta

   w.add_processor("avoid", PackedStringArray(["pos", "vel", "goal"]), _avoid)
   w.add_processor("integrate", PackedStringArray(["pos", "vel"]), _integrate, PackedStringArray(["avoid"]))
   ```

   ORCA needs all agents of a crowd in one call, so keep the crowd in one archetype and keep `avoid` non-parallel.

5. **Tick at a fixed step** from `_physics_process`: `w.run(delta)`. Use `w.processor_order()` to check ordering; a dependency cycle logs an error.

6. **Render.** Read positions with `w.query(PackedStringArray(["pos"]))` and write them into a `MultiMesh` (`multimesh.set_instance_transform`);
   for animation cost control see the game's tiering in `client/anim_lod.gd` and `tests/test_crowd_animation_tier_planner.gd`.

7. **Remove agents** with `w.destroy(id)`; check `w.is_alive(id)` before touching stored ids (stale ids fail the generation check).

The tests show avoidance behaviour on head-on and 200-agent crossing scenarios and check determinism across runs.

---

## 4. Virtual geometry

Goal: take a high-poly welded mesh, build clusters and an LOD hierarchy, pick a crack-free cut for the camera, and cull clusters.
CPU library: you render the index lists it returns. API pages: [`meshlets`](api/shared/meshlets.md), [`cluster_lod`](api/shared/cluster_lod.md),
[`occlusion_raster`](api/shared/occlusion_raster.md), [`occluder_simplifier`](api/shared/occluder_simplifier.md). Reference test: `game/tests/test_virtual_geometry.gd`.

1. **Get welded geometry.** From an `ArrayMesh` surface take `Mesh.ARRAY_VERTEX` (`PackedVector3Array`) and `Mesh.ARRAY_INDEX` (`PackedInt32Array`).
   Vertices must be shared by index, so neighbouring clusters share ids; weld first if your source duplicates vertices per face.

2. **Build meshlets** (optional on its own): `Meshlets.build_meshlets(vertices, indices, 64, 124)` returns an Array of Dictionaries with
   `indices`, `vertex_ids`, `bounds_center`, `bounds_radius`, `cone_axis`, `cone_cutoff`.

3. **Build the cluster hierarchy:**

   ```gdscript
   var h: Dictionary = ClusterLod.build_hierarchy(vertices, indices, 4)   # keys: vertices, clusters, levels, roots
   ```

4. **Select the cut each frame.** Inputs are the camera position, vertical field of view in radians, the viewport height in pixels and the allowed error in pixels:

   ```gdscript
   var cut: PackedInt32Array = ClusterLod.select_cut(h, cam.global_position, deg_to_rad(cam.fov), viewport_height, 1.0)
   var tris: int = ClusterLod.triangle_count(h, cut)
   ```

   Each id in `cut` indexes `h["clusters"]`; a cluster's `indices` is a global triangle list. Group-shared LOD spheres give a cut without cracks or overlap.

5. **Cull the cut.** `Meshlets.cone_cull(m, cam_pos)` (true = every triangle faces away, skip it) and `Meshlets.frustum_cull(m, cam.get_frustum())`
   (true = fully outside a plane) read the meshlet keys `bounds_center`, `bounds_radius`, `cone_axis`, `cone_cutoff`. Cluster dictionaries from `ClusterLod`
   name the sphere `center` / `radius` instead (and keep `cone_axis` / `cone_cutoff`), so map the keys into a small Dictionary before calling:

   ```gdscript
   var c: Dictionary = h["clusters"][id]
   var m: Dictionary = {"bounds_center": c["center"], "bounds_radius": c["radius"], "cone_axis": c["cone_axis"], "cone_cutoff": c["cone_cutoff"]}
   if not Meshlets.cone_cull(m, cam_pos) and not Meshlets.frustum_cull(m, planes):
   	visible_ids.append(id)
   ```

   `planes` is `Array[Plane]` (outward normals, the `Camera3D.get_frustum()` convention). The tests exercise these culls on meshlets from `build_meshlets`;
   the cluster-key mapping above is derived from the key names in `cluster_lod.gd` and is not covered by a test.

6. **Add occlusion.** Per frame: `occ.begin(proj_matrix_times_view, 256, 128)`, `occ.rasterize_occluder(triangles)` for a few big occluders
   (`OccluderSimplifier` builds cheap ones and ranks candidates), `occ.build_hiz()`, then `occ.is_visible(aabb)` or `occ.test_many(aabbs)`.
   The result is conservative (unsure means visible); perspective projections only.

7. **Draw.** Merge the surviving clusters' triangle lists into one `ArrayMesh` surface (or one per level) and update it only when the cut changes.

What it does not do: no GPU rasterisation, no streaming of cluster data from disk, no software-raster of small triangles. If it is too slow for a mesh, that is the
cost of the CPU implementation; compare with a plain mesh using the project's tracing tools before adopting it.
