extends SceneTree
## Headless integration tests: run with
## godot --headless --path misc/pcg_graph --script res://tests/test_pcg_graph.gd

const Graph := preload("res://addons/pcg_graph/pcg_graph.gd")
const Generator := preload("res://addons/pcg_graph/pcg_generator.gd")
const Spawner := preload("res://addons/pcg_graph/pcg_spawner_3d.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _check(ok: bool, reason: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: %s" % reason)


func _grid(columns: int = 3, rows: int = 2, spacing: float = 2.0) -> PCGGraph:
	var graph := Graph.make_default()
	var node: Dictionary = graph.nodes[0]
	graph.update_parameters(int(node["id"]), {
		"columns": columns, "rows": rows, "spacing": spacing,
	})
	return graph


func _append(graph: PCGGraph, kind: String, parameters: Dictionary) -> int:
	var original_output: int = graph.nodes[1]["id"]
	var input_id: int = graph.connections[0]["from"]
	graph.remove_connection(input_id, original_output)
	var new_id := graph.add_graph_node(kind)
	graph.update_parameters(new_id, parameters)
	_check(graph.add_connection(input_id, new_id), "connecting GRID to %s" % kind)
	_check(graph.add_connection(new_id, original_output), "connecting %s to OUTPUT" % kind)
	return new_id


func _ok(graph: PCGGraph) -> Dictionary:
	var result: Dictionary = Generator.evaluate(graph)
	_check(result["ok"], "expected successful graph: %s" % result["error"])
	return result


func _fails(graph: PCGGraph, reason: String) -> void:
	var result: Dictionary = Generator.evaluate(graph)
	_check(not result["ok"], reason)
	_check(not str(result["error"]).is_empty(), reason + " reports an error")


func _test_default_graph() -> void:
	var graph := Graph.make_default()
	_check(graph.nodes.size() == 2, "new graph has two nodes")
	_check(graph.connections.size() == 1, "default graph connects GRID and OUTPUT")
	_check(graph.get_graph_node(100).is_empty(), "unknown node lookup is empty")
	var result := _ok(graph)
	_check(result["points"].size() == 64, "default grid creates 64 points")
	_check(result["points"][0] == Vector3.ZERO, "first point at origin")
	_check(result["points"][63] == Vector3(14, 0, 14), "last point uses grid spacing")


func _test_grid_sampling() -> void:
	var graph := _grid(3, 2, 2.5)
	var points: Array = _ok(graph)["points"]
	_check(points.size() == 6, "3x2 grid count")
	_check(points[0] == Vector3(0, 0, 0), "first grid point")
	_check(points[1] == Vector3(2.5, 0, 0), "X spacing")
	_check(points[2] == Vector3(5, 0, 0), "last point on row")
	_check(points[3] == Vector3(0, 0, 2.5), "second row begins at expected Z")
	_check(points[5] == Vector3(5, 0, 2.5), "last grid point")
	_check(_ok(_grid(1, 1, 1))["points"].size() == 1, "single-cell grid")


func _test_graph_mutations() -> void:
	var graph := Graph.new()
	_check(graph.add_graph_node("NOT_A_NODE") == -1, "reject unknown node types")
	var source: int = graph.add_graph_node("GRID")
	var jitter: int = graph.add_graph_node("JITTER")
	var output: int = graph.add_graph_node("OUTPUT")
	_check(source > 0 and jitter > source and output > jitter, "unique increasing node ids")
	_check(graph.get_node_kind(jitter) == "JITTER", "stored type lookup")
	_check(not graph.add_connection(output, jitter), "reject outgoing OUTPUT")
	_check(not graph.add_connection(jitter, source), "reject incoming GRID")
	_check(not graph.add_connection(jitter, jitter), "reject self-loop")
	_check(graph.add_connection(source, jitter), "connect source to modifier")
	_check(not graph.add_connection(source, jitter), "reject duplicate link")
	_check(graph.add_connection(jitter, output), "connect modifier to output")
	_check(not graph.add_connection(source, output), "reject second incoming edge")
	_check(not graph.add_connection(output, source), "reject reverse direction")
	_check(graph.set_node_position(jitter, Vector2(40, 65)), "set node position")
	_check(graph.get_graph_node(jitter)["position"] == Vector2(40, 65), "position saved")
	_check(not graph.set_node_position(900, Vector2.ZERO), "reject position for nonexistent node")
	_check(not graph.update_parameters(900, {}), "reject parameters for nonexistent node")
	_check(graph.remove_connection(source, jitter), "remove existing edge")
	_check(not graph.remove_connection(source, jitter), "removing missing edge is safe")
	_check(graph.remove_graph_node(jitter), "remove node")
	_check(graph.connections.is_empty(), "remove node cleans up incident edges")
	_check(not graph.remove_graph_node(jitter), "removing missing node returns false")
	graph.clear_graph()
	_check(graph.nodes.is_empty() and graph.connections.is_empty(), "clear graph")


func _test_cycle_prevention() -> void:
	# The reverse edge would have a free input, so rejection must be caused
	# by cycle detection rather than the duplicate-input guard.
	var standalone := Graph.new()
	var first := standalone.add_graph_node("JITTER")
	var second := standalone.add_graph_node("OFFSET")
	_check(standalone.add_connection(first, second), "first cycle-test edge")
	_check(not standalone.add_connection(second, first), "real cycle is rejected")
	var graph := Graph.new()
	var source := graph.add_graph_node("GRID")
	var a := graph.add_graph_node("JITTER")
	var b := graph.add_graph_node("OFFSET")
	_check(graph.add_connection(source, a), "cycle graph source link")
	_check(graph.add_connection(a, b), "cycle graph second link")
	_check(not graph.add_connection(b, a), "editor API rejects back edge")
	var output := graph.add_graph_node("OUTPUT")
	_check(graph.add_connection(b, output), "remaining DAG still connectable")


func _test_repeatable_jitter() -> void:
	var graph := _grid(5, 4, 3.0)
	_append(graph, "JITTER", {"radius": 1.5})
	var first: Array = _ok(graph)["points"]
	var second: Array = _ok(graph)["points"]
	_check(first == second, "jitter deterministic across evaluations")
	_check(first.size() == 20, "jitter keeps count")
	_check(first != _ok(_grid(5, 4, 3.0))["points"], "jitter affects positions")
	var untouched: Array = _ok(_grid(5, 4, 3.0))["points"]
	for i in first.size():
		_check(absf(first[i].x - untouched[i].x) <= 1.5, "jitter X radius")
		_check(absf(first[i].z - untouched[i].z) <= 1.5, "jitter Z radius")
		_check(is_zero_approx(first[i].y), "jitter leaves Y unchanged")
	graph.seed = 12345
	_check(first != _ok(graph)["points"], "changing seed changes jitter")


func _test_zero_jitter() -> void:
	var graph := _grid(3, 3, 1.0)
	_append(graph, "JITTER", {"radius": 0.0})
	_check(_ok(graph)["points"] == _ok(_grid(3, 3, 1.0))["points"],
			"zero radius does not move points")


func _test_random_filter() -> void:
	var graph := _grid(10, 10, 1.0)
	var filter_id := _append(graph, "RANDOM_FILTER", {"chance": 0.0})
	_check(_ok(graph)["points"].is_empty(), "zero chance removes all points")
	graph.update_parameters(filter_id, {"chance": 1.0})
	_check(_ok(graph)["points"].size() == 100, "chance one retains all points")
	graph.update_parameters(filter_id, {"chance": 0.5})
	var first: Array = _ok(graph)["points"]
	_check(first == _ok(graph)["points"], "random filter deterministic")
	_check(first.size() > 0 and first.size() < 100, "half chance filters some points")
	graph.seed = 999
	_check(first != _ok(graph)["points"], "filter responds to seed")


func _test_noise_filter() -> void:
	var graph := _grid(8, 7, 1.0)
	var id := _append(graph, "NOISE_FILTER", {"frequency": 0.1, "threshold": -1.0})
	_check(_ok(graph)["points"].size() == 56, "noise threshold -1 keeps all")
	graph.update_parameters(id, {"frequency": 0.1, "threshold": 1.0})
	_check(_ok(graph)["points"].size() <= 56, "noise threshold 1 never adds points")
	graph.update_parameters(id, {"frequency": 0.1, "threshold": 0.0})
	_check(_ok(graph)["points"] == _ok(graph)["points"], "noise deterministic")


func _test_offset() -> void:
	var graph := _grid(2, 2, 1.0)
	_append(graph, "OFFSET", {"x": -6.0, "y": 11.0, "z": 2.5})
	var points: Array = _ok(graph)["points"]
	_check(points.size() == 4, "offset keeps count")
	_check(points[0] == Vector3(-6, 11, 2.5), "offset moves origin")
	_check(points[3] == Vector3(-5, 11, 3.5), "offset moves final point")
	_check(_ok(_grid(2, 2, 1))["points"][0] == Vector3.ZERO,
			"offset does not mutate unrelated graph")


func _test_invalid_graphs() -> void:
	_fails(Graph.new(), "empty graph")
	_fails(_grid(0, 1), "zero columns")
	_fails(_grid(-1, 2), "negative columns")
	_fails(_grid(3, -1), "negative rows")
	_fails(_grid(101, 101), "over-budget grid")
	_fails(_grid(1, 2, 0.0), "zero spacing")
	_fails(_grid(1, 2, -1.0), "negative spacing")
	_fails(_grid(1, 2, NAN), "NaN spacing")
	_fails(_grid(1, 2, INF), "infinite spacing")

	var no_output := Graph.new()
	no_output.add_graph_node("GRID")
	_fails(no_output, "missing OUTPUT")
	var extra_output := Graph.make_default()
	extra_output.add_graph_node("OUTPUT")
	_fails(extra_output, "multiple outputs")
	var missing_connection := Graph.make_default()
	missing_connection.connections.clear()
	_fails(missing_connection, "missing OUTPUT input")
	var missing_node := Graph.make_default()
	missing_node.connections[0] = {"from": 10, "to": 2}
	_fails(missing_node, "dangling edge")
	var same_node := Graph.make_default()
	same_node.connections[0] = {"from": 1, "to": 1}
	_fails(same_node, "self-loop")
	var wrong_direction := Graph.make_default()
	wrong_direction.connections[0] = {"from": 2, "to": 1}
	_fails(wrong_direction, "OUTPUT cannot send to GRID")
	var duplicate_id := Graph.make_default()
	var duplicate: Dictionary = duplicate_id.nodes[0].duplicate(true)
	duplicate_id.nodes.append(duplicate)
	_fails(duplicate_id, "duplicate ID")
	var unknown := Graph.make_default()
	var entry: Dictionary = unknown.nodes[0].duplicate(true)
	entry["kind"] = "UNKNOWN"
	unknown.nodes[0] = entry
	_fails(unknown, "unknown node kind")
	var non_integer_id := Graph.make_default()
	var bad_entry: Dictionary = non_integer_id.nodes[0].duplicate(true)
	bad_entry["id"] = "one"
	non_integer_id.nodes[0] = bad_entry
	_fails(non_integer_id, "noninteger ID")

	var extra_connection := Graph.make_default()
	var offset := extra_connection.add_graph_node("OFFSET")
	extra_connection.connections.append({"from": 1, "to": offset})
	extra_connection.connections.append({"from": offset, "to": 2})
	_fails(extra_connection, "multiple incoming edges")


func _test_bad_parameters() -> void:
	var graph := _grid()
	var id := _append(graph, "JITTER", {"radius": -0.01})
	_fails(graph, "negative jitter")
	graph.update_parameters(id, {"radius": NAN})
	_fails(graph, "NaN jitter")
	graph.update_parameters(id, {"radius": 100001.0})
	_fails(graph, "excessive jitter")

	graph = _grid()
	id = _append(graph, "RANDOM_FILTER", {"chance": -0.1})
	_fails(graph, "negative chance")
	graph.update_parameters(id, {"chance": 1.1})
	_fails(graph, "chance over one")
	graph.update_parameters(id, {"chance": INF})
	_fails(graph, "infinite chance")

	graph = _grid()
	id = _append(graph, "NOISE_FILTER", {"frequency": 0.0, "threshold": 0.0})
	_fails(graph, "zero noise frequency")
	graph.update_parameters(id, {"frequency": 1.0, "threshold": 2.0})
	_fails(graph, "threshold beyond one")

	graph = _grid()
	id = _append(graph, "OFFSET", {"x": NAN, "y": 0.0, "z": 0.0})
	_fails(graph, "offset invalid component")
	graph.update_parameters(id, {"x": 0.0, "y": INF, "z": 0.0})
	_fails(graph, "offset infinite component")


func _test_raw_cycles_and_excess() -> void:
	var graph := Graph.make_default()
	var a := graph.add_graph_node("JITTER")
	var b := graph.add_graph_node("OFFSET")
	graph.remove_connection(1, 2)
	graph.connections.append({"from": b, "to": a})
	graph.connections.append({"from": a, "to": b})
	graph.connections.append({"from": b, "to": 2})
	_fails(graph, "malformed cyclic resource")
	var oversized := Graph.make_default()
	while oversized.nodes.size() < Graph.MAX_NODES:
		oversized.add_graph_node("JITTER")
	# add_graph_node correctly refuses over limit; insert malformed extra resource data.
	oversized.nodes.append({"id": 257, "kind": "GRID", "params": Graph.default_parameters("GRID")})
	_fails(oversized, "resource with too many nodes")


func _test_serialization() -> void:
	var graph := _grid(4, 3, 1.25)
	var id := _append(graph, "OFFSET", {"x": 4.0, "y": 7.0, "z": -2.0})
	graph.set_node_position(id, Vector2(-50, 100))
	graph.seed = 748
	var path := "user://pcg_graph_test.tres"
	_check(ResourceSaver.save(graph, path) == OK, "graph ResourceSaver writes .tres")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PCGGraph
	_check(loaded != null, "serialized PCGGraph loads")
	if loaded != null:
		_check(loaded.seed == graph.seed, "seed persists")
		_check(loaded.get_graph_node(id)["position"] == Vector2(-50, 100),
				"visual positions persist")
		_check(_ok(loaded)["points"] == _ok(graph)["points"], "serialized graph yields same points")
		_check(loaded.connections == graph.connections, "connections persist")


func _test_spawner() -> void:
	var spawner: PCGSpawner3D = Spawner.new()
	root.add_child(spawner)
	spawner.graph = _grid(3, 2)
	spawner.instance_mesh = BoxMesh.new()
	_check(spawner.generate(), "MultiMesh generation succeeds")
	_check(spawner.get_generated_count() == 6, "MultiMesh instance count")
	var generated := spawner.get_node_or_null("_PCGGenerated") as MultiMeshInstance3D
	_check(generated != null, "generated child is a MultiMeshInstance3D")
	if generated != null:
		_check(generated.multimesh.get_instance_transform(5).origin == Vector3(4, 0, 2),
				"instance transform matches last graph point")
	spawner.graph = _grid(2, 1)
	_check(spawner.generate(), "repeated generation succeeds")
	_check(spawner.get_generated_count() == 2, "regeneration replaces existing MultiMesh")
	spawner.max_instances = 1
	_check(not spawner.generate(), "instance budget enforced")
	_check(spawner.get_generated_count() == 2, "failed generation preserves existing instances")
	spawner.clear_generated()
	_check(spawner.get_generated_count() == 0, "clearing instances")
	_check(not spawner.generate(), "budget failure on empty spawner")
	spawner.instance_mesh = null
	_check(not spawner.generate(), "mesh is required")
	spawner.graph = null
	_check(not spawner.generate(), "graph is required")
	spawner.queue_free()


func _test_null_and_shared_graph_data() -> void:
	var result := Generator.evaluate(null)
	_check(not result["ok"], "null graph rejected")
	var graph := _grid()
	var data := graph.get_graph_node(1)
	data["params"]["columns"] = 9000
	_check(graph.get_graph_node(1)["params"]["columns"] == 3,
			"node lookup returns a deep copy")
	var params := {"radius": 1.0}
	var id := graph.add_graph_node("JITTER")
	graph.update_parameters(id, params)
	params["radius"] = -99.0
	_check(graph.get_graph_node(id)["params"]["radius"] == 1.0,
			"parameter updates keep a separate copy")


func _run_all() -> void:
	_test_default_graph()
	_test_grid_sampling()
	_test_graph_mutations()
	_test_cycle_prevention()
	_test_repeatable_jitter()
	_test_zero_jitter()
	_test_random_filter()
	_test_noise_filter()
	_test_offset()
	_test_invalid_graphs()
	_test_bad_parameters()
	_test_raw_cycles_and_excess()
	_test_serialization()
	_test_spawner()
	_test_null_and_shared_graph_data()
	print("PCG Graph: %d checks; %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
