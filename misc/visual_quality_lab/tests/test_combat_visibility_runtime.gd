extends SceneTree

const Visibility = preload("res://addons/visual_quality/combat_visibility.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var player: CharacterBody3D = CharacterBody3D.new()
	player.position = Vector3.ZERO
	var player_shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	player_shape.shape = capsule
	player_shape.position.y = 0.9
	player.add_child(player_shape)
	stage.add_child(player)
	var target: StaticBody3D = StaticBody3D.new()
	target.position = Vector3(0, 0, -6)
	var target_shape: CollisionShape3D = CollisionShape3D.new()
	var target_box: BoxShape3D = BoxShape3D.new()
	target_box.size = Vector3(1.0, 2.0, 1.0)
	target_shape.shape = target_box
	target_shape.position.y = 1.0
	target.add_child(target_shape)
	stage.add_child(target)
	var cover: StaticBody3D = StaticBody3D.new()
	cover.position = Vector3(0, 0, -3)
	var cover_shape: CollisionShape3D = CollisionShape3D.new()
	var cover_box: BoxShape3D = BoxShape3D.new()
	cover_box.size = Vector3(3.0, 2.5, 0.8)
	cover_shape.shape = cover_box
	cover_shape.position.y = 1.0
	cover.add_child(cover_shape)
	stage.add_child(cover)
	await physics_frame
	await physics_frame
	var eye: Vector3 = Vector3(0, 1.4, 0)
	var target_eye: Vector3 = Vector3(0, 1.4, -6)
	assert(not Visibility.has_clear_path(stage.get_world_3d(), eye, target_eye,
		player, target), "Solid cover must block an attack")
	cover.collision_layer = 0
	await physics_frame
	assert(Visibility.has_clear_path(stage.get_world_3d(), eye, target_eye,
		player, target), "Target collider is a valid ray hit")
	cover.collision_layer = 1
	cover.position = Vector3(6, 0, -3)
	await physics_frame
	assert(Visibility.has_clear_path(stage.get_world_3d(), eye, target_eye,
		player, target), "Cover outside the line must not block attacks")
	assert(not Visibility.has_clear_path(stage.get_world_3d(), Vector3(NAN, 0, 0), target_eye))
	stage.queue_free()
	print("Combat visibility runtime: solid wall blocks, visible target and off-axis cover passed")
	quit(0)
