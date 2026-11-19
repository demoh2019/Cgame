@tool
extends Resource
class_name PCGGraph
## Serializable, deterministic point-processing graph.
## Each node has one input/output port; GRID is a source and OUTPUT is a sink.

const NODE_KINDS := ["GRID", "JITTER", "RANDOM_FILTER", "NOISE_FILTER", "OFFSET", "OUTPUT"]
const MAX_NODES := 256

@export var seed: int = 1
@export var nodes: Array[Dictionary] = []
@export var connections: Array[Dictionary] = []


static func default_parameters(kind: String) -> Dictionary:
	match kind:
		"GRID":
			return {"columns": 8, "rows": 8, "spacing": 2.0}
		"JITTER":
			return {"radius": 0.5}
		"RANDOM_FILTER":
			return {"chance": 0.75}
		"NOISE_FILTER":
			return {"frequency": 0.08, "threshold": 0.0}
		"OFFSET":
			return {"x": 0.0, "y": 0.0, "z": 0.0}
		"OUTPUT":
			return {}
	return {}


func add_graph_node(kind: String, position: Vector2 = Vector2.ZERO) -> int:
	if not NODE_KINDS.has(kind) or nodes.size() >= MAX_NODES:
		return -1
	var next_id := 1
	for entry in nodes:
		next_id = maxi(next_id, int(entry.get("id", 0)) + 1)
	nodes.append({
		"id": next_id,
		"kind": kind,
		"params": default_parameters(kind),
		"position": position,
	})
	emit_changed()
	return next_id


func get_graph_node(node_id: int) -> Dictionary:
	for entry in nodes:
		if entry.get("id") == node_id:
			return entry.duplicate(true)
	return {}


func get_node_kind(node_id: int) -> String:
	return str(get_graph_node(node_id).get("kind", ""))


func update_parameters(node_id: int, parameters: Dictionary) -> bool:
	for i in nodes.size():
		if nodes[i].get("id") == node_id:
			var edited: Dictionary = nodes[i].duplicate(true)
			edited["params"] = parameters.duplicate(true)
			nodes[i] = edited
			emit_changed()
			return true
	return false


func set_node_position(node_id: int, position: Vector2) -> bool:
	for i in nodes.size():
		if nodes[i].get("id") == node_id:
			var edited: Dictionary = nodes[i].duplicate(true)
			edited["position"] = position
			nodes[i] = edited
			emit_changed()
			return true
	return false


func _is_reachable(start_id: int, target_id: int) -> bool:
	var pending: Array[int] = [start_id]
	var visited := {}
	while not pending.is_empty():
		var current: int = pending.pop_back()
		if current == target_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for edge in connections:
			if edge.get("from") == current:
				pending.append(int(edge.get("to", -1)))
	return false


func add_connection(from_id: int, to_id: int) -> bool:
	if from_id == to_id or from_id <= 0 or to_id <= 0:
		return false
	if get_node_kind(from_id) in ["", "OUTPUT"]:
		return false
	if get_node_kind(to_id) in ["", "GRID"]:
		return false
	for edge in connections:
		if edge.get("to") == to_id:
			# A point processor has exactly one input.
			return false
	if _is_reachable(to_id, from_id):
		return false
	connections.append({"from": from_id, "to": to_id})
	emit_changed()
	return true


func remove_connection(from_id: int, to_id: int) -> bool:
	for i in connections.size():
		if connections[i].get("from") == from_id and connections[i].get("to") == to_id:
			connections.remove_at(i)
			emit_changed()
			return true
	return false


func remove_graph_node(node_id: int) -> bool:
	var found := false
	for i in range(nodes.size() - 1, -1, -1):
		if nodes[i].get("id") == node_id:
			nodes.remove_at(i)
			found = true
	for i in range(connections.size() - 1, -1, -1):
		if connections[i].get("from") == node_id or connections[i].get("to") == node_id:
			connections.remove_at(i)
	if found:
		emit_changed()
	return found


func clear_graph() -> void:
	nodes.clear()
	connections.clear()
	emit_changed()


static func make_default() -> PCGGraph:
	var graph := PCGGraph.new()
	var grid := graph.add_graph_node("GRID", Vector2(50, 150))
	var output := graph.add_graph_node("OUTPUT", Vector2(400, 150))
	graph.add_connection(grid, output)
	return graph
