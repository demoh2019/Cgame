extends SceneTree
## Writes res://tools/pcg/scatter_demo.tres (a self-contained scatter graph that needs no world samplers, so it
## previews inside the editor) and res://tools/pcg/pcg_demo.tscn (a PCGComponent3D using it, two primitive meshes,
## debug points and an exclusion volume that clears a square). Open the scene and select "PCGDemo": the PCG Graph
## panel opens with the graph; edit any node and the 3D view regenerates (Live Preview).
## godot --headless --path game --script res://tools/pcg/make_pcg_demo.gd


func _node(graph, cls: String, title: String, props: Dictionary) -> int:
	var node = ClassDB.instantiate(cls)
	node.set_title(title)
	for key in props:
		node.set(key, props[key])
	return graph.add_node(node)


func _init() -> void:
	if not ClassDB.class_exists("PCGGraph"):
		push_error("This engine has no PCG classes.")
		quit(1)
		return
	var graph = ClassDB.instantiate("PCGGraph")
	graph.set_parameter("spacing", 2.5)
	var ids := [
		_node(graph, "PCGSurfaceSamplerNode", "Ground lattice", {"spacing": 2.5, "jitter": 0.9}),
		_node(graph, "PCGDensityNoiseNode", "Patchiness", {"frequency": 0.06, "octaves": 3, "contrast": 2.2}),
		_node(graph, "PCGDensityFilterNode", "Roll density", {"random_threshold": true}),
		_node(graph, "PCGExclusionFilterNode", "Exclusion volumes", {"margin": 0.5}),
		_node(graph, "PCGSelfPruneNode", "Spacing", {"min_distance": 2.0}),
		_node(graph, "PCGTransformNode", "Random yaw/scale", {"scale_min": 0.6, "scale_max": 1.4}),
		_node(graph, "PCGAssetRuleNode", "Crates or rocks", {"rules": [{"asset": 0, "weight": 1.0, "min_density": 0.55}, {"asset": 1, "weight": 3.0}]}),
		_node(graph, "PCGClusterNode", "HLOD clusters", {"cluster_size": 24.0}),
		_node(graph, "PCGOutputNode", "Output", {}),
	]
	graph.get_node_by_id(ids[0]).bind_parameter("spacing", "spacing")
	for i in range(1, ids.size()):
		graph.connect_nodes(ids[i - 1], ids[i])
	var x := 0.0
	for id in ids:
		graph.get_node_by_id(id).set_graph_position(Vector2(x, (int(x / 240.0) % 2) * 90.0))
		x += 240.0
	ResourceSaver.save(graph, "res://tools/pcg/scatter_demo.tres")

	var root := Node3D.new()
	root.name = "PCGDemoRoot"
	var component = ClassDB.instantiate("PCGComponent3D")
	component.name = "PCGDemo"
	component.set_graph(load("res://tools/pcg/scatter_demo.tres"))
	component.set_extents(Vector3(32, 20, 32))
	component.set_generate_on_ready(true)
	component.set_async(false)
	component.set_debug_draw(true)
	var crate := BoxMesh.new()
	crate.size = Vector3(0.9, 0.9, 0.9)
	var crate_material := StandardMaterial3D.new()
	crate_material.albedo_color = Color(0.62, 0.42, 0.22)
	crate.material = crate_material
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 0.7
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.52, 0.53, 0.55)
	rock.material = rock_material
	var meshes: Array[Mesh] = [crate, rock]
	component.set_asset_meshes(meshes)
	root.add_child(component)
	component.owner = root
	var volume = ClassDB.instantiate("PCGExclusionVolume3D")
	volume.name = "KeepClear"
	volume.set_size(Vector3(12, 8, 12))
	volume.position = Vector3(8, 0, -6)
	root.add_child(volume)
	volume.owner = root
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(64, 64)
	ground.mesh = plane
	root.add_child(ground)
	ground.owner = root
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://tools/pcg/pcg_demo.tscn")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tools/pcg/biome_clutter.tres"))
	print("PCG demo written: nodes=%d connections=%d" % [graph.get_node_count(), graph.get_connections().size()])
	quit()
