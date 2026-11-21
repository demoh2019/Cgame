extends SceneTree

const Visibility = preload("res://addons/visual_quality/combat_visibility.gd")
const Director = preload("res://addons/visual_quality/combat_controller.gd")


func _initialize() -> void:
	var enemy: StaticBody3D = StaticBody3D.new()
	var wall: StaticBody3D = StaticBody3D.new()
	assert(Visibility.hit_is_clear({}))
	assert(Visibility.hit_is_clear({"collider": enemy}, enemy))
	assert(not Visibility.hit_is_clear({"collider": wall}, enemy))
	assert(not Visibility.hit_is_clear({"collider": wall}))
	assert(not Visibility.hit_is_clear({"collider": null}, enemy))
	var director: WorldCombatDirector3D = Director.new()
	assert(director.max_visibility_checks > 0)
	director.request_strike()
	assert(director._queued_strike)
	director.request_shockwave()
	assert(director._queued_shockwave)
	assert(not Visibility.has_clear_path(null, Vector3.ZERO, Vector3.ONE))
	enemy.free()
	wall.free()
	director.free()
	print("Combat visibility: classification, queueing and invalid world passed")
	quit(0)
