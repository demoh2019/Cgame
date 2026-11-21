extends SceneTree

const Character = preload("res://addons/visual_quality/character_controller.gd")


func _initialize() -> void:
	var value: Vector3 = Character.step_horizontal_velocity(Vector3.ZERO, Vector3(4, 0, 0), 5.0, 0.1)
	assert(value.is_equal_approx(Vector3(0.5, 0, 0)))
	value = Character.step_horizontal_velocity(Vector3(0, 3, 0), Vector3(4, 0, 0), 100.0, 0.1)
	assert(value.is_equal_approx(Vector3(4, 3, 0)), "Vertical motion must be preserved")
	value = Character.step_horizontal_velocity(Vector3(4, -2, 0), Vector3.ZERO, 4.0, 0.25)
	assert(value.is_equal_approx(Vector3(3, -2, 0)), "Braking should be predictable")
	value = Character.step_horizontal_velocity(Vector3(4, -2, 0), Vector3(8, 0, 0), -4.0, 1.0)
	assert(value.is_equal_approx(Vector3(4, -2, 0)), "Negative acceleration cannot accelerate")
	assert(Character.should_jump(0.10, 0.05))
	assert(not Character.should_jump(0.0, 0.05))
	assert(not Character.should_jump(0.10, 0.0))
	var player = Character.new()
	player.set_fly_mode(true)
	assert(player.is_flying)
	assert(player.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING)
	assert(player.velocity == Vector3.ZERO)
	player.set_fly_mode(false)
	assert(not player.is_flying)
	assert(player.motion_mode == CharacterBody3D.MOTION_MODE_GROUNDED)
	player.free()
	print("VisualLabCharacter3D: 12 checks passed")
	quit(0)
