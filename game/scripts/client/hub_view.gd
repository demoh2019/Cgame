extends Node3D
## The hub town: a paved plaza with the fountain, a ring of houses, lamp posts and the workbench.
## What stands where comes from WorldGen.hub_structures(), the same list the server collides with.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Meshes = preload("res://scripts/client/meshes.gd")


func build(world) -> void:
	var height: float = WorldGen.HUB_HEIGHT
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
				_place(Assets.building_mesh(structure["variant"]), position, structure["scale"], structure["yaw"])
			"workbench":
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
