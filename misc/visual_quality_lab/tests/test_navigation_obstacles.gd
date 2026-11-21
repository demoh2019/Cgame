extends SceneTree

const Tile = preload("res://addons/visual_quality/navigation_tile.gd")


func _initialize() -> void:
	var rock: Array[Rect2] = [Rect2(Vector2(-1.1, -1.1), Vector2(2.2, 2.2))]
	var mesh: NavigationMesh = Tile.make_obstacle_tile(14.0, rock, 0.35)
	assert(mesh.get_polygon_count() == 8, "A central rectangular hole must leave 8 walkable quads")
	assert(mesh.vertices.size() == 16)
	var hole: Rect2 = Rect2(Vector2(-1.45, -1.45), Vector2(2.90, 2.90))
	for i in range(mesh.get_polygon_count()):
		var corners: PackedInt32Array = mesh.get_polygon(i)
		assert(corners.size() == 4)
		var center: Vector3 = Vector3.ZERO
		for vertex_index in corners:
			center += mesh.vertices[vertex_index]
		center /= float(corners.size())
		assert(not hole.has_point(Vector2(center.x, center.z)), "Navmesh must avoid the rock")
	assert(Tile.make_obstacle_tile(14.0, [], 0.35).get_polygon_count() == 1)
	assert(Tile.make_obstacle_tile(0.0, rock, 0.35).get_polygon_count() == 0)
	assert(Tile.make_obstacle_tile(14.0, rock, NAN).get_polygon_count() == 0)
	var outside: Array[Rect2] = [Rect2(Vector2(20, 20), Vector2(2, 2))]
	assert(Tile.make_obstacle_tile(14.0, outside, 0.35).get_polygon_count() == 1)
	var obstacles: Array[Rect2] = [
		Rect2(Vector2(-3, -3), Vector2(1, 1)),
		Rect2(Vector2(3, 3), Vector2(1, 1))
	]
	var multi: NavigationMesh = Tile.make_obstacle_tile(14.0, obstacles, 0.35)
	assert(multi.get_polygon_count() > 0)
	assert(multi.get_polygon_count() <= 25)
	assert(Tile.deduplicate_breaks(PackedFloat32Array([-1.0, -1.0, 0.0, 1.0])).size() == 3)
	print("Obstacle-aware navigation: 12 geometry/check groups passed")
	quit(0)
