@tool
extends RefCounted
class_name PCGGenerator
## Evaluates a DAG of point processors into a deterministic Array[Vector3].
## All graphs (including edited/corrupted resources) are checked at runtime.

const MAX_POINTS := 10000


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "points": []}


static func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return not is_nan(float(value)) and not is_inf(float(value))


static func _numeric(params: Dictionary, key: String, minimum: float, maximum: float) -> bool:
	var value: Variant = params.get(key)
	return _finite_number(value) and float(value) >= minimum and float(value) <= maximum


static func _process(kind: String, params: Dictionary, source: Array, seed: int, node_id: int) -> Dictionary:
	var result: Array[Vector3] = []
	match kind:
		"GRID":
			var columns: Variant = params.get("columns")
			var rows: Variant = params.get("rows")
			if typeof(columns) != TYPE_INT or typeof(rows) != TYPE_INT:
				return _failure("GRID requires integer columns and rows")
			if columns < 1 or rows < 1 or columns > MAX_POINTS or rows > MAX_POINTS:
				return _failure("GRID dimensions must be in the range 1..10000")
			if columns * rows > MAX_POINTS:
				return _failure("GRID exceeds the point budget")
			if not _numeric(params, "spacing", 0.001, 100000.0):
				return _failure("GRID requires finite, positive spacing")
			var spacing: float = float(params["spacing"])
			for z in rows:
				for x in columns:
					result.append(Vector3(x * spacing, 0.0, z * spacing))
		"JITTER":
			if not _numeric(params, "radius", 0.0, 100000.0):
				return _failure("JITTER radius is invalid")
			var radius: float = float(params["radius"])
			var rng := RandomNumberGenerator.new()
			rng.seed = seed ^ (node_id * 2654435761)
			for point in source:
				result.append(point + Vector3(
					rng.randf_range(-radius, radius),
					0.0,
					rng.randf_range(-radius, radius)
				))
		"RANDOM_FILTER":
			if not _numeric(params, "chance", 0.0, 1.0):
				return _failure("RANDOM_FILTER chance must be within 0..1")
			var chance: float = float(params["chance"])
			var rng := RandomNumberGenerator.new()
			rng.seed = seed ^ (node_id * 2246822519)
			for point in source:
				if rng.randf() < chance:
					result.append(point)
		"NOISE_FILTER":
			if not _numeric(params, "frequency", 0.000001, 100.0):
				return _failure("NOISE_FILTER frequency is invalid")
			if not _numeric(params, "threshold", -1.0, 1.0):
				return _failure("NOISE_FILTER threshold is invalid")
			var noise := FastNoiseLite.new()
			noise.seed = seed ^ (node_id * 31337)
			noise.frequency = float(params["frequency"])
			var threshold: float = float(params["threshold"])
			for point in source:
				if noise.get_noise_2d(point.x, point.z) >= threshold:
					result.append(point)
		"OFFSET":
			for axis in ["x", "y", "z"]:
				if not _numeric(params, axis, -100000.0, 100000.0):
					return _failure("OFFSET component %s is invalid" % axis)
			var delta := Vector3(float(params["x"]), float(params["y"]), float(params["z"]))
			for point in source:
				result.append(point + delta)
		"OUTPUT":
			for point in source:
				result.append(point)
		_:
			return _failure("Unknown processor: %s" % kind)
	if result.size() > MAX_POINTS:
		return _failure("Graph exceeds the point budget")
	return {"ok": true, "error": "", "points": result}


static func evaluate(graph: PCGGraph) -> Dictionary:
	if graph == null:
		return _failure("Graph is missing")
	if graph.nodes.is_empty():
		return _failure("Graph has no nodes")
	if graph.nodes.size() > PCGGraph.MAX_NODES:
		return _failure("Graph has too many nodes")

	var by_id := {}
	var output_id := -1
	for entry in graph.nodes:
		var id: Variant = entry.get("id")
		var kind: Variant = entry.get("kind")
		if typeof(id) != TYPE_INT or id <= 0 or by_id.has(id):
			return _failure("Invalid or duplicate node ID")
		if typeof(kind) != TYPE_STRING or not PCGGraph.NODE_KINDS.has(kind):
			return _failure("Unknown node kind")
		if typeof(entry.get("params")) != TYPE_DICTIONARY:
			return _failure("Node parameters must be a Dictionary")
		if kind == "OUTPUT":
			if output_id != -1:
				return _failure("Graph must have exactly one OUTPUT")
			output_id = id
		by_id[id] = entry
	if output_id == -1:
		return _failure("Graph needs an OUTPUT")

	var inputs := {}
	for edge in graph.connections:
		var from_id: Variant = edge.get("from")
		var to_id: Variant = edge.get("to")
		if typeof(from_id) != TYPE_INT or typeof(to_id) != TYPE_INT:
			return _failure("Connection IDs must be integers")
		if from_id == to_id or not by_id.has(from_id) or not by_id.has(to_id):
			return _failure("Connection targets a missing node or itself")
		if inputs.has(to_id):
			return _failure("Multiple inputs are not supported")
		if by_id[from_id]["kind"] == "OUTPUT" or by_id[to_id]["kind"] == "GRID":
			return _failure("Invalid connection direction")
		inputs[to_id] = from_id

	var evaluated := {}
	var left: int = graph.nodes.size()
	while left > 0:
		var progress := false
		for entry in graph.nodes:
			var id: int = entry["id"]
			if evaluated.has(id):
				continue
			var kind: String = entry["kind"]
			var has_input := inputs.has(id)
			if kind != "GRID" and not has_input:
				return _failure("Node %d (%s) has no input" % [id, kind])
			if has_input and not evaluated.has(inputs[id]):
				continue
			var source: Array = evaluated[inputs[id]] if has_input else []
			var processed := _process(kind, entry["params"], source, graph.seed, id)
			if not processed["ok"]:
				return _failure("Node %d: %s" % [id, processed["error"]])
			evaluated[id] = processed["points"]
			progress = true
			left -= 1
		if not progress:
			return _failure("Graph contains a cycle")
	return {"ok": true, "error": "", "points": evaluated[output_id]}
