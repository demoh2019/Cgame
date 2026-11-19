extends RefCounted
## Extra high-pressure scenarios not covered by the core or GPU stress suites.


func scene_reparent(tree: SceneTree, scale: int) -> Dictionary:
	var world := Node3D.new()
	tree.root.add_child(world)
	var left := Node3D.new()
	var right := Node3D.new()
	world.add_child(left)
	world.add_child(right)
	var nodes: Array[Node3D] = []
	for i in range(400 * scale):
		var node := Node3D.new()
		node.name = "Moving%d" % i
		left.add_child(node)
		nodes.append(node)
	var operations := 0
	for iteration in range(6):
		var target := right if iteration % 2 == 0 else left
		for node in nodes:
			node.reparent(target, false)
			if node.get_parent() != target:
				world.free()
				return {"error": "Parent mismatch during scene mutation"}
			operations += 1
	var valid := left.get_child_count() == nodes.size() and right.get_child_count() == 0
	world.free()
	if not valid:
		return {"error": "Scene tree lost nodes after reparenting"}
	return {"nodes": nodes.size(), "reparent_operations": operations}


func scene_move(tree: SceneTree, scale: int) -> Dictionary:
	# Repeated adjacent child moves stress the tree's index update path.
	# Build one large parent so the historical two-tail shift dominates.
	var parent := Node.new()
	tree.root.add_child(parent)
	var children: Array[Node] = []
	var count := 600 * scale
	for i in range(count):
		var child := Node.new()
		child.name = "Move%d" % i
		parent.add_child(child)
		children.append(child)

	var operations := 0
	for iteration in range(10):
		for i in range(0, count - 1, 2):
			var moving := parent.get_child(i)
			parent.move_child(moving, i + 1)
			if moving.get_index() != i + 1 or parent.get_child(i + 1) != moving:
				parent.free()
				return {"error": "Adjacent child move did not preserve indices"}
			operations += 1

	# Ten passes restore the initial ordering; also exercise long moves.
	if parent.get_child(0) != children[0] or parent.get_child(count - 1) != children[count - 1]:
		parent.free()
		return {"error": "Adjacent child moves did not restore original order"}
	for i in range(16):
		var first := parent.get_child(0)
		parent.move_child(first, count - 1)
		if parent.get_child(count - 1) != first:
			parent.free()
			return {"error": "Distant child move failed"}
		operations += 1
	var correct := parent.get_child_count() == count
	parent.free()
	if not correct:
		return {"error": "Child count mismatch after moves"}
	return {"nodes": count, "moves": operations}


func resource_roundtrip(scale: int) -> Dictionary:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	var path := "user://stress_resource_%d.tres" % OS.get_process_id()
	if ResourceSaver.save(curve, path) != OK:
		return {"error": "Could not serialize resource"}
	var checksum := 0.0
	var failure := ""
	for i in range(70 * scale):
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Curve
		if loaded == null or loaded.get_point_count() != 2:
			failure = "ResourceLoader returned invalid curve"
			break
		var value := loaded.sample(0.5)
		if absf(value - 0.5) > 0.05:
			failure = "Resource changed during roundtrip"
			break
		checksum += value
	var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failure != "":
		return {"error": failure}
	if cleanup != OK:
		return {"error": "Failed to clean up the stress resource"}
	return {"loads": 70 * scale, "checksum": checksum}


func audio_bus_churn(scale: int) -> Dictionary:
	var initial := AudioServer.get_bus_count()
	for i in range(100 * scale):
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		var name := "CgameStress%d" % i
		AudioServer.set_bus_name(index, name)
		if AudioServer.get_bus_name(index) != name:
			AudioServer.remove_bus(index)
			return {"error": "Audio bus name roundtrip failed"}
		AudioServer.remove_bus(index)
	if AudioServer.get_bus_count() != initial:
		return {"error": "Audio bus count changed after churn"}
	return {"buses_created_and_removed": 100 * scale}
