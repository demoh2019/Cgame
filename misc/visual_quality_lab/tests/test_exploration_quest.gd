extends SceneTree

const Quest = preload("res://addons/visual_quality/exploration_quest.gd")


func _initialize() -> void:
	var positions: PackedVector3Array = Quest.generate_positions(123, 12, 15.0, 35.0)
	assert(positions.size() == 12)
	assert(positions == Quest.generate_positions(123, 12, 15.0, 35.0))
	assert(positions != Quest.generate_positions(124, 12, 15.0, 35.0))
	for pos in positions:
		assert(is_equal_approx(pos.y, 1.4))
		assert(Vector2(pos.x, pos.z).length() >= 14.99)
		assert(Vector2(pos.x, pos.z).length() <= 35.01)
	assert(Quest.generate_positions(0, 0, 3.0, 15.0).is_empty())
	assert(Quest.generate_positions(0, 99, 3.0, 15.0).size() == 32)
	assert(Quest.generate_positions(0, 3, NAN, 15.0).is_empty())
	var local_positions: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(5.0, 0.0, 0.0)])
	assert(Quest.nearest_pickup_id(Vector3(0.3, 0.0, 0.0), local_positions, PackedInt32Array(), 2.5) == 0)
	assert(Quest.nearest_pickup_id(Vector3(0.3, 0.0, 0.0), local_positions, PackedInt32Array([0]), 2.5) == -1)
	assert(Quest.nearest_pickup_id(Vector3(5.1, 0.0, 0.0), local_positions, PackedInt32Array([0]), 2.5) == 1)
	assert(Quest.nearest_pickup_id(Vector3(7.6, 0.0, 0.0), local_positions, PackedInt32Array(), 2.5) == -1)

	var instance = Quest.new()
	instance.save_enabled = false
	instance.positions = local_positions
	assert(instance.collect_shard(0))
	assert(not instance.collect_shard(0))
	assert(not instance.collect_shard(-1))
	assert(not instance.collect_shard(2))
	assert(instance.collected_count() == 1)
	instance.reset_quest()
	assert(instance.collected_count() == 0)
	instance.free()

	# Save/load validation does not depend on a scene tree or a GPU renderer.
	var first = Quest.new()
	first.save_path = "user://visual_lab_quest_test.cfg"
	first.positions = local_positions
	assert(first.collect_shard(1))
	var restored = Quest.new()
	restored.save_path = first.save_path
	restored.positions = local_positions
	restored.load_progress()
	assert(restored.collected_count() == 1)
	assert(restored.collected_ids[0] == 1)
	restored.world_seed += 1
	restored.load_progress()
	assert(restored.collected_count() == 0, "Different worlds must not share quest progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first.save_path))
	first.free()
	restored.free()
	print("ExplorationQuest3D: 21 verification groups passed")
	quit(0)
