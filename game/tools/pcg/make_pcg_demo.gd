extends SceneTree
## Writes res://tools/pcg/biome_clutter.tres (the game's clutter graph as a resource) and
## res://tools/pcg/pcg_demo.tscn (a PCGComponent3D using it, with an exclusion volume), so the
## PCG Graph Editor can be opened on a real graph: open the scene, select "PCGDemo".
## godot --headless --path game --script res://tools/pcg/make_pcg_demo.gd
const PcgGraphs = preload("res://scripts/shared/pcg_graphs.gd")


func _init() -> void:
	var graph = PcgGraphs.biome_clutter()
	if graph == null:
		push_error("This engine has no PCG classes.")
		quit(1)
		return
	var x := 0.0
	for id in graph.compute_order():
		graph.get_node_by_id(id).set_graph_position(Vector2(x, 0.0))
		x += 260.0
	ResourceSaver.save(graph, "res://tools/pcg/biome_clutter.tres")
	var root := Node3D.new()
	root.name = "PCGDemoRoot"
	var component = ClassDB.instantiate("PCGComponent3D")
	component.name = "PCGDemo"
	component.set_graph(load("res://tools/pcg/biome_clutter.tres"))
	component.set_extents(Vector3(48, 50, 48))
	component.set_debug_draw(true)
	component.set_generate_on_ready(true)
	component.set_async(false)
	root.add_child(component)
	component.owner = root
	var volume = ClassDB.instantiate("PCGExclusionVolume3D")
	volume.name = "KeepClear"
	volume.set_size(Vector3(16, 8, 16))
	root.add_child(volume)
	volume.owner = root
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(light)
	light.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://tools/pcg/pcg_demo.tscn")
	print("PCG demo written: nodes=%d connections=%d" % [graph.get_node_count(), graph.get_connections().size()])
	quit()
