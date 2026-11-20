extends SceneTree

const Character = preload("res://addons/visual_quality/character_controller.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var ground: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(50.0, 0.4, 50.0)
	collision.shape = box
	ground.position.y = -0.2
	ground.add_child(collision)
	stage.add_child(ground)
	var character = Character.new()
	character.name = "TestCharacter"
	character.position = Vector3(0.0, 3.5, 0.0)
	stage.add_child(character)
	for _frame in range(120):
		await physics_frame
	assert(character.is_on_floor(), "Capsule should land on static ground")
	assert(character.global_position.y > -0.05, "Ground collider prevents tunneling")
	assert(character.global_position.y < 0.25, "Grounded character should settle close to floor")
	assert(character.get_view_camera() != null, "Player must have a camera")
	character.set_fly_mode(true)
	assert(character.is_flying)
	character.set_fly_mode(false)
	assert(not character.is_flying)
	stage.queue_free()
	print("VisualLabCharacter3D: 6 physics integration checks passed")
	quit(0)
