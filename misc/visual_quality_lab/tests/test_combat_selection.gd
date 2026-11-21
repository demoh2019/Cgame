extends SceneTree

const CombatDirector = preload("res://addons/visual_quality/combat_controller.gd")


func _initialize() -> void:
	var candidates: Array[Dictionary] = [
		{"uid": "front", "position": Vector3(0, 1, -2)},
		{"uid": "behind", "position": Vector3(0, 1, 1)},
		{"uid": "far", "position": Vector3(0, 1, -20)}
	]
	var origin: Vector3 = Vector3(0, 1, 0)
	assert(CombatDirector.choose_facing_target(candidates, origin, Vector3.FORWARD,
		4.0, 0.25)["uid"] == "front")
	assert(CombatDirector.choose_facing_target(candidates, origin, Vector3.BACK,
		4.0, 0.25)["uid"] == "behind")
	assert(CombatDirector.choose_facing_target(candidates, origin, Vector3.RIGHT,
		4.0, 0.25).is_empty())
	assert(CombatDirector.choose_facing_target(candidates, origin, Vector3.FORWARD,
		1.0, 0.25).is_empty())
	assert(CombatDirector.choose_facing_target(candidates, origin, Vector3.ZERO,
		4.0, 0.25).is_empty())
	var tie: Array[Dictionary] = [
		{"uid": "b", "position": Vector3(0, 1, -3)},
		{"uid": "a", "position": Vector3(0, 1, -3)}
	]
	assert(CombatDirector.choose_facing_target(tie, origin, Vector3.FORWARD,
		4.0, 0.25)["uid"] == "a")
	var invalid: Array[Dictionary] = [{"uid": "bad", "position": Vector3(NAN, 0, -1)}]
	assert(CombatDirector.choose_facing_target(invalid, origin, Vector3.FORWARD,
		4.0, 0.25).is_empty())
	print("WorldCombatDirector3D: targeting cone/radius/tie safety passed")
	quit(0)
