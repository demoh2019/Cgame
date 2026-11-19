@tool
extends Resource
class_name OWPCGGraph
## A deterministic, acyclic scalar graph evaluated over terrain X/Z coordinates.
## Each link connects the single output of one node to a numbered input of another.

const KINDS := ["Constant", "Noise", "Add", "Multiply", "Clamp", "Terrace", "Output"]
const INPUT_COUNTS := {"Constant": 0, "Noise": 0, "Add": 2, "Multiply": 2, "Clamp": 1, "Terrace": 1, "Output": 1}

@export_storage var nodes: Array[Dictionary] = []
@export_storage var links: Array[Dictionary] = []
@export var seed: int = 1


func _find_index(id: int) -> int:
	for i in nodes.size():
		if int(nodes[i].get("id", -1)) == id:
			return i
	return -1


func get_node_data(id: int) -> Dictionary:
	var index := _find_index(id)
	return nodes[index].duplicate(true) if index >= 0 else {}


func add_node(kind: String, position: Vector2 = Vector2.ZERO) -> int:
	if not INPUT_COUNTS.has(kind) or not position.is_finite():
		return -1
	if kind == "Output":
		for entry in nodes:
			if entry.get("kind") == "Output":
				return -1
	var next_id := 1
	for entry in nodes:
		next_id = maxi(next_id, int(entry.get("id", 0)) + 1)
	var parameters := {}
	match kind:
		"Constant": parameters = {"value": 1.0}
		"Noise": parameters = {"frequency": 0.04, "amplitude": 8.0}
		"Clamp": parameters = {"minimum": -10.0, "maximum": 10.0}
		"Terrace": parameters = {"steps": 4.0}
	nodes.append({"id": next_id, "kind": kind, "position": position, "params": parameters})
	emit_changed()
	return next_id


func remove_node(id: int) -> bool:
	var index := _find_index(id)
	if index < 0:
		return false
	nodes.remove_at(index)
	for i in range(links.size() - 1, -1, -1):
		if int(links[i].get("from", -1)) == id or int(links[i].get("to", -1)) == id:
			links.remove_at(i)
	emit_changed()
	return true


func set_node_position(id: int, position: Vector2) -> bool:
	var index := _find_index(id)
	if index < 0 or not position.is_finite():
		return false
	var updated := nodes[index].duplicate(true)
	updated["position"] = position
	nodes[index] = updated
	emit_changed()
	return true


func set_parameter(id: int, key: String, value: float) -> bool:
	var index := _find_index(id)
	if index < 0 or not is_finite(value):
		return false
	var kind := str(nodes[index].get("kind", ""))
	var allowed := []
	match kind:
		"Constant": allowed = ["value"]
		"Noise": allowed = ["frequency", "amplitude"]
		"Clamp": allowed = ["minimum", "maximum"]
		"Terrace": allowed = ["steps"]
	if not allowed.has(key):
		return false
	if key == "frequency" and value <= 0.0:
		return false
	if key == "steps" and (value < 1.0 or value > 256.0):
		return false
	var updated := nodes[index].duplicate(true)
	var parameters: Dictionary = updated.get("params", {}).duplicate(true)
	parameters[key] = value
	updated["params"] = parameters
	nodes[index] = updated
	emit_changed()
	return true


func connect_nodes(source_id: int, target_id: int, input_port: int) -> bool:
	if source_id == target_id or input_port < 0:
		return false
	var source := get_node_data(source_id)
	var target := get_node_data(target_id)
	if source.is_empty() or target.is_empty() or source.get("kind") == "Output":
		return false
	if input_port >= int(INPUT_COUNTS.get(target.get("kind", ""), 0)):
		return false
	var previous := links.duplicate(true)
	for i in range(links.size() - 1, -1, -1):
		if int(links[i].get("to", -1)) == target_id and int(links[i].get("input", -1)) == input_port:
			links.remove_at(i)
	links.append({"from": source_id, "to": target_id, "input": input_port})
	if not _compile(false).get("error", "").is_empty():
		links = previous
		return false
	emit_changed()
	return true


func disconnect_nodes(source_id: int, target_id: int, input_port: int) -> bool:
	for i in links.size():
		var link := links[i]
		if int(link.get("from", -1)) == source_id and int(link.get("to", -1)) == target_id and int(link.get("input", -1)) == input_port:
			links.remove_at(i)
			emit_changed()
			return true
	return false


func _compile(require_complete: bool = true) -> Dictionary:
	## Kahn traversal: no recursive execution, detects cycles and bad resources.
	var node_by_id := {}
	var incoming := {}
	var outgoing := {}
	var output_count := 0
	var output_id := -1
	for entry in nodes:
		var id := int(entry.get("id", -1))
		var kind := str(entry.get("kind", ""))
		if id <= 0 or node_by_id.has(id) or not INPUT_COUNTS.has(kind):
			return {"error": "Duplicate ID or unknown PCG node"}
		node_by_id[id] = entry
		incoming[id] = 0
		outgoing[id] = []
		if kind == "Output":
			output_count += 1
			output_id = id
	if require_complete and output_count != 1:
		return {"error": "Graph requires exactly one Output node"}
	var inputs := {}
	for link in links:
		var source := int(link.get("from", -1))
		var target := int(link.get("to", -1))
		var port := int(link.get("input", -1))
		if not node_by_id.has(source) or not node_by_id.has(target) or source == target:
			return {"error": "Dangling or self-referential PCG link"}
		if node_by_id[source].get("kind") == "Output" or port < 0 or port >= int(INPUT_COUNTS[node_by_id[target].get("kind")]):
			return {"error": "Invalid PCG port"}
		var key := Vector2i(target, port)
		if inputs.has(key):
			return {"error": "PCG input has multiple connections"}
		inputs[key] = source
		incoming[target] = int(incoming[target]) + 1
		outgoing[source].append(target)
	if require_complete:
		for entry in nodes:
			for port in int(INPUT_COUNTS[entry["kind"]]):
				if not inputs.has(Vector2i(int(entry["id"]), port)):
					return {"error": "Unconnected input on node " + str(entry["id"])}
	var pending: Array[int] = []
	for id in node_by_id:
		if int(incoming[id]) == 0:
			pending.append(id)
	pending.sort()
	var order: Array[int] = []
	while not pending.is_empty():
		var current := pending.pop_front()
		order.append(current)
		for target in outgoing[current]:
			incoming[target] = int(incoming[target]) - 1
			if int(incoming[target]) == 0:
				pending.append(target)
		pending.sort()
	if order.size() != nodes.size():
		return {"error": "Cycle detected in PCG graph"}
	return {"error": "", "order": order, "node_by_id": node_by_id, "inputs": inputs, "output_id": output_id}


func validation_error() -> String:
	return str(_compile(true).get("error", ""))


func _make_noises(compiled: Dictionary) -> Dictionary:
	var generators := {}
	for id in compiled["order"]:
		var data: Dictionary = compiled["node_by_id"][id]
		if data["kind"] != "Noise":
			continue
		var parameters: Dictionary = data.get("params", {})
		var noise := FastNoiseLite.new()
		noise.seed = seed + id * 113
		noise.frequency = maxf(0.000001, float(parameters.get("frequency", 0.04)))
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		generators[id] = noise
	return generators


func _evaluate(x: float, z: float, compiled: Dictionary, noises: Dictionary) -> float:
	var computed := {}
	var inputs: Dictionary = compiled["inputs"]
	for id in compiled["order"]:
		var entry: Dictionary = compiled["node_by_id"][id]
		var parameters: Dictionary = entry.get("params", {})
		var first := float(computed.get(inputs.get(Vector2i(id, 0), -1), 0.0))
		var second := float(computed.get(inputs.get(Vector2i(id, 1), -1), 0.0))
		var value := 0.0
		match entry["kind"]:
			"Constant": value = float(parameters.get("value", 1.0))
			"Noise": value = noises[id].get_noise_2d(x, z) * float(parameters.get("amplitude", 8.0))
			"Add": value = first + second
			"Multiply": value = first * second
			"Clamp":
				var minimum := float(parameters.get("minimum", -10.0))
				var maximum := float(parameters.get("maximum", 10.0))
				value = clampf(first, minf(minimum, maximum), maxf(minimum, maximum))
			"Terrace":
				var steps := maxi(1, int(round(float(parameters.get("steps", 4.0)))))
				value = floorf(first * float(steps)) / float(steps)
			"Output": value = first
		computed[id] = value
	return float(computed.get(compiled["output_id"], 0.0))


func evaluate_point(x: float, z: float) -> float:
	var compiled := _compile(true)
	if not compiled["error"].is_empty() or not is_finite(x) or not is_finite(z):
		return 0.0
	return _evaluate(x, z, compiled, _make_noises(compiled))


func bake_to_heightmap(heightmap: OWHeightmap) -> bool:
	if heightmap == null:
		return false
	var compiled := _compile(true)
	if not compiled["error"].is_empty():
		return false
	heightmap.ensure_storage()
	var heights := PackedFloat32Array()
	heights.resize(heightmap.columns * heightmap.rows)
	var generators := _make_noises(compiled)
	for z in heightmap.rows:
		for x in heightmap.columns:
			var value := _evaluate(float(x) * heightmap.cell_size, float(z) * heightmap.cell_size, compiled, generators)
			if not is_finite(value):
				return false
			heights[z * heightmap.columns + x] = value
	return heightmap.set_snapshots(heights, heightmap.blend)


static func make_default_graph() -> OWPCGGraph:
	var graph := OWPCGGraph.new()
	var noise := graph.add_node("Noise", Vector2(60, 90))
	var output := graph.add_node("Output", Vector2(390, 90))
	graph.connect_nodes(noise, output, 0)
	return graph