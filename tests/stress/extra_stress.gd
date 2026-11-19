extends RefCounted
## Supplemental CPU and scene workloads for the whole-engine stress suite.


func run(test_case: String, tree: SceneTree, scale: int) -> Dictionary:
	match test_case:
		"geometry_2d":
			return _geometry_2d(scale)
		"mesh_build":
			return _mesh_build(scale)
		"input_dispatch":
			return _input_dispatch(scale)
		"image_codec":
			return _image_codec(scale)
		"group_calls":
			return _group_calls(tree, scale)
	return {"error": "Unknown extended stress case"}


func _geometry_2d(scale: int) -> Dictionary:
	var polygon := PackedVector2Array()
	polygon.resize(40)
	var triangle_count := 0
	var iterations := 250 * scale
	for i in range(iterations):
		var rotation := float(i % 120) * 0.01
		for vertex in range(polygon.size()):
			var theta := TAU * float(vertex) / float(polygon.size()) + rotation
			polygon[vertex] = Vector2(cos(theta), sin(theta)) * 50.0
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.size() != (polygon.size() - 2) * 3:
			return {"error": "Triangulation returned wrong triangle count"}
		if Geometry2D.convex_hull(polygon).size() < 3:
			return {"error": "Convex hull has fewer than three points"}
		triangle_count += int(indices.size() / 3)
	return {"polygons": iterations, "triangles": triangle_count}


func _mesh_build(scale: int) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := 200 * scale
	for i in range(triangles):
		var x := float(i % 128)
		var z := float(i / 128)
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(0.0, 0.0))
		surface.add_vertex(Vector3(x, 0.0, z))
		surface.set_uv(Vector2(1.0, 0.0))
		surface.add_vertex(Vector3(x + 0.5, 0.0, z))
		surface.set_uv(Vector2(0.0, 1.0))
		surface.add_vertex(Vector3(x, 0.0, z + 0.5))
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() != 1:
		return {"error": "Failed to commit SurfaceTool mesh"}
	var arrays := mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_VERTEX].size() != triangles * 3:
		return {"error": "SurfaceTool vertex data truncated"}
	return {"triangles": triangles, "vertices": triangles * 3}


func _input_dispatch(scale: int) -> Dictionary:
	var action := &"cgame_stress_input_dispatch"
	if InputMap.has_action(action):
		return {"error": "Input action unexpectedly registered"}
	InputMap.add_action(action)
	var event := InputEventAction.new()
	event.action = action
	var iterations := 8000 * scale
	for i in range(iterations):
		event.pressed = (i & 1) == 0
		Input.parse_input_event(event)
	Input.action_release(action)
	InputMap.erase_action(action)
	return {"events": iterations}


func _image_codec(scale: int) -> Dictionary:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var bytes_written := 0
	var iterations := 40 * scale
	for i in range(iterations):
		img.fill(Color(float(i % 256) / 255.0, 0.2, 0.7, 1.0))
		var encoded := img.save_png_to_buffer()
		if encoded.is_empty():
			return {"error": "PNG encoding failed"}
		var loaded := Image.new()
		if loaded.load_png_from_buffer(encoded) != OK:
			return {"error": "PNG decoding failed"}
		if loaded.get_width() != 128 or loaded.get_height() != 128:
			return {"error": "Decoded PNG size mismatch"}
		bytes_written += encoded.size()
	return {"png_roundtrips": iterations, "compressed_bytes": bytes_written}


func _group_calls(tree: SceneTree, scale: int) -> Dictionary:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var count := 400 * scale
	for i in range(count):
		var node := Node2D.new()
		parent.add_child(node)
		node.add_to_group("cgame_stress_group_calls")
	var iterations := 10 * scale
	for i in range(iterations):
		tree.call_group("cgame_stress_group_calls", "hide")
		tree.call_group("cgame_stress_group_calls", "show")
	if tree.get_nodes_in_group("cgame_stress_group_calls").size() != count:
		parent.free()
		return {"error": "Unexpected scene group count"}
	parent.free()
	return {"nodes": count, "group_method_calls": iterations * count * 2}
