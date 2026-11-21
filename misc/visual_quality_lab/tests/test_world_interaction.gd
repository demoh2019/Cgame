extends SceneTree

const Router = preload("res://addons/visual_quality/world_interaction_router.gd")
const Quest = preload("res://addons/visual_quality/exploration_quest.gd")
const Cell = preload("res://world/forest_cell.gd")


func _initialize() -> void:
	var entries: Array[Dictionary] = [
		{"uid": "front", "action_id": "one", "position": Vector3(0, 0, -2), "radius": 3.0, "label": "Front"},
		{"uid": "behind", "action_id": "two", "position": Vector3(0, 0, 1), "radius": 3.0, "label": "Behind"},
		{"uid": "far", "action_id": "three", "position": Vector3(0, 0, -9), "radius": 10.0, "label": "Far"}
	]
	var eye: Vector3 = Vector3.ZERO
	assert(Router.select_best(entries, eye, Vector3.FORWARD, 3.5, 0.15)["uid"] == "front")
	assert(Router.select_best(entries, eye, Vector3.BACK, 3.5, 0.15)["uid"] == "behind")
	assert(Router.select_best(entries, eye, Vector3.RIGHT, 3.5, 0.15).is_empty())
	assert(Router.select_best(entries, eye, Vector3.FORWARD, 1.0, 0.15).is_empty())
	assert(Router.select_best(entries, eye, Vector3.ZERO, 3.5, 0.15).is_empty())
	assert(Router.select_best(entries, eye, Vector3.FORWARD, 0.0, 0.15).is_empty())
	var ties: Array[Dictionary] = [
		{"uid": "b", "position": Vector3(0, 0, -2), "radius": 3.0},
		{"uid": "a", "position": Vector3(0, 0, -2), "radius": 3.0}
	]
	assert(Router.select_best(ties, eye, Vector3.FORWARD, 3.5, 0.15)["uid"] == "a")
	var invalid_text: Array[Dictionary] = [{"uid": "bad", "position": "not a position"}]
	var invalid_nan: Array[Dictionary] = [{"uid": "bad", "position": Vector3(NAN, 0, 0)}]
	assert(Router.select_best(invalid_text, eye, Vector3.FORWARD, 3.5, 0.15).is_empty())
	assert(Router.select_best(invalid_nan, eye, Vector3.FORWARD, 3.5, 0.15).is_empty())
	var quest = Quest.new()
	quest.save_enabled = false
	quest.positions = PackedVector3Array([Vector3(0, 1.4, -2)])
	var player = Node3D.new()
	player.position = Vector3.ZERO
	var offers: Array[Dictionary] = quest.get_interaction_targets(Vector3(0, 1.5, 0), 3.5)
	assert(offers.size() == 1)
	assert(not quest.activate_interaction("shard_oops", player))
	assert(not quest.activate_interaction("shard_2", player))
	assert(quest.activate_interaction("shard_0", player))
	assert(quest.collected_count() == 1)
	assert(not quest.activate_interaction("shard_0", player))
	assert(quest.get_interaction_targets(Vector3(0, 1.5, 0), 3.5).is_empty())
	quest.free()
	player.free()
	print("WorldInteractionRouter3D: selection and quest validation checks passed")
	quit(0)
