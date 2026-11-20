extends SceneTree

const Cell = preload("res://world/forest_cell.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var cell = Cell.new()
	cell.configure_stream_cell(Vector2i(1, 0))
	cell.position = Vector3(14, 0, 0)
	stage.add_child(cell)
	var tile: NavigationRegion3D = cell.get_node("NavigationTile")
	var rock: StaticBody3D = cell.get_node("NavigationRock")
	assert(tile.navigation_mesh.get_polygon_count() == 8)
	assert(rock.get_node("CollisionShape3D") is CollisionShape3D)
	assert(cell.get_active_npc() is CharacterBody3D)
	# A scene-root NavigationMesh is registered to the navigation server after
	# at least one physics frame. This confirms route follows the rock's hole.
	for _frame in range(5):
		await physics_frame
	var start: Vector3 = Vector3(9, 0, 0)
	var target: Vector3 = Vector3(19, 0, 0)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(tile.get_navigation_map(), start, target, true)
	assert(path.size() >= 3, "Path from opposite sides of rock should detour")
	stage.queue_free()
	print("Obstacle-aware navigation: 4 runtime checks passed")
	quit(0)
