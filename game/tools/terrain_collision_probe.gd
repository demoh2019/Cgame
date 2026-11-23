extends SceneTree
## godot --headless --path game --script res://tools/terrain_collision_probe.gd
## Optional authoring smoke test. No player, server, or saved world is changed.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const TerrainAuthoring = preload("res://scripts/client/terrain_collision_authoring.gd")


func _initialize() -> void:
	var terrain: Node3D = TerrainAuthoring.build_patch(
		WorldGen.new(1337), Vector2(128, 128), 32, 2.0, 2)
	if terrain == null:
		print("Terrain collision authoring requires native HeightmapTerrain3D.")
		quit(0)
		return
	root.add_child(terrain)
	print("Albion terrain collision preview: %d physics triangles; visual heightmap %dx%d" % [
		int(terrain.call("get_auto_collision_triangle_count")),
		int(terrain.get("heightmap").get_width()),
		int(terrain.get("heightmap").get_depth())])
	quit(0)
