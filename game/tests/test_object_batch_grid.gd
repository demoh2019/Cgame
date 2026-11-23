extends RefCounted
## Dense MultiMeshes are partitioned for culling and imported-model mesh LOD.
## Rendering changes must not lose or duplicate any server-authoritative resource id.

const ObjectBatchGrid = preload("res://scripts/client/object_batch_grid.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "dense world geometry batches preserve resource state"
	var trees: Array = []
	for i in 20:
		trees.append({"id": 100 + i, "x": 4.0 + float(i % 5) * 12.0,
			"y": 0.0, "z": 5.0 + float(i / 5) * 12.0})
	var crates: Array = []
	for i in 16:
		crates.append({"id": 900 + i, "x": 5.0 + float(i), "z": 6.0})
	var input := {"tree:0": trees, "crate:0": crates}
	var batches: Dictionary = ObjectBatchGrid.partition(input, Vector2.ZERO, 64.0)
	var ids: Dictionary = {}
	var tree_batches := 0
	var crate_batches := 0
	for batch_id in batches:
		var batch: Dictionary = batches[batch_id]
		var kind: String = batch["kind"]
		if kind == "tree:0":
			tree_batches += 1
		if kind == "crate:0":
			crate_batches += 1
		for node in batch["nodes"]:
			t.check(not ids.has(node["id"]), "one server resource belongs to only one visual batch")
			ids[node["id"]] = true
	t.eq(ids.size(), 36, "partition keeps all objects and stable server ids")
	t.check(tree_batches >= 2 and tree_batches <= 4, "dense trees split into at most four camera-cullable groups")
	t.eq(crate_batches, 1, "loot crates stay in a single batch")
	t.eq(ObjectBatchGrid.key_for("tree:0", Vector2(64.0, 64.0), Vector2.ZERO, 64.0),
		"tree:0|1|1", "cell boundary is clamped inside the chunk")
	t.eq(ObjectBatchGrid.key_for("tree:0", Vector2(-1.0, -1.0), Vector2.ZERO, 64.0),
		"tree:0|0|0", "negative coordinates do not create out-of-range cells")

	t.current = "sparse geometry retains low draw-call count"
	var sparse: Dictionary = ObjectBatchGrid.partition({"rock:1": trees.slice(0, 3)},
		Vector2.ZERO, 64.0)
	t.eq(sparse.size(), 1, "sparse batches are not fragmented")
	t.check(sparse.has("rock:1"), "sparse batch keeps the unmodified key")

	t.current = "large chunk batches retain stable ids, order and cell borders"
	var origin := Vector2(-120.0, 300.0)
	var ore: Array = []
	var expected: Dictionary = {}
	var insertion_order: Array[String] = []
	for i in 2048:
		var local_x: float = float((i * 13) % 64) + 0.25
		var local_z: float = float((i * 29) % 64) + 0.5
		if i % 17 == 0:
			local_x = -2.0
		if i % 19 == 0:
			local_z = 66.0
		var node: Dictionary = {"id": 10000 + i,
			"x": origin.x + local_x, "z": origin.y + local_z}
		ore.append(node)
		var expected_id: String = ObjectBatchGrid.key_for(
			"ore:2", Vector2(float(node["x"]), float(node["z"])), origin, 64.0, 4)
		if not expected.has(expected_id):
			expected[expected_id] = []
			insertion_order.append(expected_id)
		var reference_nodes: Array = expected[expected_id]
		reference_nodes.append(node)
	var actual: Dictionary = ObjectBatchGrid.partition(
		{"ore:2": ore}, origin, 64.0, 12, 4)
	t.eq(actual.keys(), insertion_order,
		"occupied cells retain first-encounter order and exact public keys")
	var actual_count: int = 0
	for expected_id in insertion_order:
		var batch: Dictionary = actual[expected_id]
		t.eq(batch["kind"], "ore:2", "resource type is unchanged in %s" % expected_id)
		var actual_nodes: Array = batch["nodes"]
		t.eq(actual_nodes, expected[expected_id],
			"resource ids and within-cell ordering are preserved in %s" % expected_id)
		actual_count += actual_nodes.size()
	t.eq(actual_count, ore.size(), "all dense ore instances reach the renderer")
	t.eq(ore.size(), 2048, "batching does not mutate the source list")

	t.current = "screen-space LOD presets preserve Ultra geometry"
	var low: Dictionary = GraphicsQuality.profile(0)
	var balanced: Dictionary = GraphicsQuality.profile(1)
	var high: Dictionary = GraphicsQuality.profile(2)
	var ultra: Dictionary = GraphicsQuality.profile(3)
	t.check(float(low["mesh_lod_threshold"]) > float(balanced["mesh_lod_threshold"]),
		"Performance uses lower-detail imported meshes earlier")
	t.check(float(balanced["mesh_lod_threshold"]) > float(high["mesh_lod_threshold"]),
		"Balanced prioritizes speed over High")
	t.check(float(high["mesh_lod_threshold"]) > float(ultra["mesh_lod_threshold"]),
		"Ultra retains the most polygon detail")
