extends Node3D
## The hub town: a paved plaza with the fountain, a ring of houses, lamp posts and the workbench.
## What stands where comes from WorldGen.hub_structures(), the same list the server collides with.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Meshes = preload("res://scripts/client/meshes.gd")


func build(world) -> void:
	var height: float = WorldGen.HUB_HEIGHT
	var village := Assets.has_village()
	if village:
		_build_cobble_plaza(height)
	else:
		# Plaza: 5 x 5 paving tiles around the fountain.
		var pavement := Assets.mesh("city/pavement")
		for i in range(-2, 3):
			for j in range(-2, 3):
				_place(pavement, Vector3(i * 7.0, height, j * 7.0), 7.0, 0.0)
	for structure in world.hub_structures():
		var position := Vector3(structure["x"], height, structure["z"])
		match structure["kind"]:
			"fountain":
				_place(Assets.mesh("city/pavement-fountain"), position, structure["scale"], 0.0)
			"building":
				if village:
					var house: Dictionary = Assets.pack_building(int(structure["variant"]))
					_place(house["mesh"], position + Vector3(0, -0.05, 0), house["scale"], structure["yaw"])
				else:
					_place(Assets.building_mesh(structure["variant"]), position, structure["scale"], structure["yaw"])
			"workbench":
				if village:
					_place(Assets.village_mesh("EA03_Prop_Tabble_02a"), position, 2.2, 0.0)
					_place(Assets.village_mesh("EA03_Prop_Container_Barrel_01d"), position + Vector3(-1.4, 0, 0.6), 1.4, 0.7)
					_place(Assets.village_mesh("EA03_Prop_Container_Crate_01a"), position + Vector3(1.3, 0, -0.5), 1.4, 0.3)
					_place(Assets.village_mesh("EA03_Prop_Town_Bench_01a"), position + Vector3(0.2, 0, 1.6), 1.5, PI * 0.5)
				else:
					_place(Meshes.get_mesh("workbench"), position, 1.0, 0.0)
				var label := Label3D.new()
				label.text = "Workbench"
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.no_depth_test = true
				label.pixel_size = 0.008
				label.font_size = 28
				label.outline_size = 8
				label.position = position + Vector3(0, 2.0, 0)
				add_child(label)
	if village:
		_build_hub_props(height)
		return
	# Lamp posts along the plaza edge.
	var lamp := Assets.mesh("city/road-straight-lightposts")
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_place(lamp, Vector3(corner.x * 17.5, height, corner.y * 17.5), 4.0, atan2(corner.x, corner.y))


func _place(mesh: Mesh, position: Vector3, scale_factor: float, yaw: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * scale_factor
	add_child(instance)


## The village pack has cobble blocks but no flat paving, so the plaza is a plain stone disc.
func _build_cobble_plaza(height: float) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 17.0
	disc.bottom_radius = 17.5
	disc.height = 0.16
	disc.radial_segments = 48
	disc.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.49, 0.47)
	material.roughness = 0.95
	var instance := MeshInstance3D.new()
	instance.mesh = disc
	instance.material_override = material
	instance.position = Vector3(0, height - 0.05, 0)
	add_child(instance)


## Barrels, crates, benches and baskets around the plaza so the hub looks lived in.
func _build_hub_props(height: float) -> void:
	var props := [
		["EA03_Prop_Container_Barrel_01d", 1.5], ["EA03_Prop_Container_Crate_01a", 1.5], ["EA03_Prop_Town_Bench_01a", 1.6],
		["EA03_Prop_Container_Basket_01a", 1.6], ["EA03_Prop_Stool_01a", 1.5],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 22:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(17.0, 25.0)
		var spot := Vector2.from_angle(angle) * radius
		var entry: Array = props[rng.randi() % props.size()]
		var mesh := Assets.village_mesh(entry[0])
		if mesh != null:
			_place(mesh, Vector3(spot.x, height, spot.y), float(entry[1]), rng.randf() * TAU)
