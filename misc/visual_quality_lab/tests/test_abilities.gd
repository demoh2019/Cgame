extends SceneTree

const Stats = preload("res://addons/visual_quality/attribute_component.gd")
const Abilities = preload("res://addons/visual_quality/ability_component.gd")


func _initialize() -> void:
	var stats = Stats.new()
	var abilities = Abilities.new()
	abilities.attributes = stats
	assert(not abilities.activate("unknown"))
	assert(abilities.can_activate("dash"))
	assert(abilities.activate("dash"))
	assert(is_equal_approx(stats.stamina, 70.0))
	assert(is_equal_approx(stats.get_stat("move_speed"), 1.85))
	assert(abilities.get_cooldown("dash") == 3.0)
	assert(not abilities.activate("dash"))
	assert(is_equal_approx(stats.stamina, 70.0))
	abilities._physics_process(3.1)
	stats._physics_process(3.1)
	assert(abilities.get_cooldown("dash") == 0.0)
	assert(is_equal_approx(stats.get_stat("move_speed"), 1.0))
	assert(stats.stamina > 70.0)
	assert(abilities.activate("focus"))
	assert(stats.get_stat("stamina_regen") == 41.0)
	assert(not abilities.activate("focus"))
	stats._physics_process(5.1)
	assert(stats.get_stat("stamina_regen") == 16.0)
	var snapshot: Dictionary = abilities.cooldowns_snapshot()
	snapshot["focus"] = 0.0
	assert(abilities.get_cooldown("focus") > 0.0)
	stats.free()
	abilities.free()
	print("WorldAbilitySystem3D: costs, cooldowns, temporary effects and rollback validated")
	quit(0)
