extends SceneTree

const Planner = preload("res://addons/visual_quality/world_streaming_planner.gd")


func _initialize() -> void:
	assert(Planner.cell_for_position(Vector3(-0.01, 1.0, -14), 14.0) == Vector2i(-1, -1))
	assert(Planner.cell_for_position(Vector3(28.0, 0, 1.0), 14.0) == Vector2i(2, 0))
	assert(Planner.predict_cell(Vector3(1, 0, 1), Vector3(28, 0, 0), 14, 1.0, 2) == Vector2i(2, 0))
	assert(Planner.predict_cell(Vector3(1, 0, 1), Vector3(100, 0, 0), 14, 1.0, 1) == Vector2i(1, 0))
	assert(Planner.predict_cell(Vector3(1, 0, 1), Vector3.ZERO, 14, 1.0, 2) == Vector2i.ZERO)
	assert(Planner.predict_cell(Vector3(1, 0, 1), Vector3(12, 0, 0), 0.0, 1.0, 2) == Vector2i.ZERO)
	assert(Planner.predict_cell(Vector3(1, 0, 1), Vector3(12, 0, 0), 14.0, NAN, 2) == Vector2i.ZERO)
	assert(Planner.in_radius(Vector2i(1, 1), Vector2i.ZERO, 1))
	assert(not Planner.in_radius(Vector2i(2, 0), Vector2i.ZERO, 1))
	var registered: Dictionary = {}
	for y in range(-3, 4):
		for x in range(-3, 4):
			registered[Vector2i(x, y)] = "res://world/forest_cell.tscn"
	var none: Dictionary = {}
	var basic: Array[Vector2i] = Planner.build_load_queue(registered, none, Vector2i.ZERO,
		Vector2i.ZERO, 1, 2, 1, 3)
	assert(basic.size() == 9, "No movement must never prefetch extra scenes")
	assert(basic[0] == Vector2i.ZERO)
	var ahead: Array[Vector2i] = Planner.build_load_queue(registered, none, Vector2i.ZERO,
		Vector2i(2, 0), 0, 2, 1, 2)
	assert(ahead.size() == 3)
	assert(ahead[0] == Vector2i.ZERO, "Critical local cell must come first")
	assert(ahead[1] == Vector2i(2, 0), "Next cells are ordered by prediction distance")
	assert(ahead[2] != Vector2i.ZERO)
	var long_prediction: Array[Vector2i] = Planner.build_load_queue(registered, none, Vector2i.ZERO,
		Vector2i(9, 0), 0, 2, 1, 6)
	assert(long_prediction == [Vector2i.ZERO], "Speculative cells must be in keep radius")
	var currently_loaded: Dictionary = {Vector2i.ZERO: true}
	var active: Array[Vector2i] = Planner.build_load_queue(registered, currently_loaded, Vector2i.ZERO,
		Vector2i.ZERO, 1, 2, 1, 3)
	assert(active.size() == 8)
	assert(not active.has(Vector2i.ZERO))
	var registered_reverse: Dictionary = {}
	for key in registered.keys():
		registered_reverse[Vector2i(-key.x, -key.y)] = registered[key]
	assert(Planner.build_load_queue(registered_reverse, none, Vector2i.ZERO,
		Vector2i.ZERO, 1, 2, 1, 3) == basic)
	assert(Planner.is_speculative(Vector2i(2, 0), Vector2i.ZERO, 1))
	assert(not Planner.is_speculative(Vector2i(1, 0), Vector2i.ZERO, 1))
	print("WorldStreamingPlanner3D: 18 cases passed")
	quit(0)
