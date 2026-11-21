extends SceneTree

const Quest = preload("res://addons/visual_quality/exploration_quest.gd")
const Forest = preload("res://world/forest_cell.gd")
const Inventory = preload("res://addons/visual_quality/inventory_component.gd")


func _initialize() -> void:
	var inventory = Inventory.new()
	inventory.save_enabled = false
	var quest = Quest.new()
	quest.save_enabled = false
	quest.world_seed = 100
	quest.positions = PackedVector3Array([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)])
	quest.shard_collected.connect(func(index: int) -> void:
		inventory.grant_once("quest:%d:%d" % [quest.world_seed, index], "light_shard", 1)
	)
	assert(quest.collect_shard(0))
	assert(quest.collect_shard(1))
	assert(inventory.get_count("light_shard") == 2)
	assert(inventory.craft("spark_core"))
	assert(inventory.get_count("light_shard") == 0)
	quest.reset_quest()
	assert(quest.collect_shard(0))
	assert(inventory.get_count("light_shard") == 0, "Quest reset must not duplicate materials")
	var first = Forest.new()
	first.configure_stream_cell(Vector2i(1, 0))
	first.resource_awarded.connect(func(item_id: String, uid: String) -> void:
		inventory.grant_once(uid, item_id, 1)
	)
	assert(first.try_activate_beacon(first.get_beacon_world_position()))
	assert(inventory.get_count("forest_essence") == 1)
	first.load_stream_state({})
	assert(first.try_activate_beacon(first.get_beacon_world_position()))
	assert(inventory.get_count("forest_essence") == 1, "Reactivation must not mint duplicate reward")
	var second = Forest.new()
	second.configure_stream_cell(Vector2i(2, 0))
	second.resource_awarded.connect(func(item_id: String, uid: String) -> void:
		inventory.grant_once(uid, item_id, 1)
	)
	assert(second.try_activate_beacon(second.get_beacon_world_position()))
	assert(inventory.craft("forest_lantern"))
	assert(inventory.get_count("forest_lantern") == 1)
	first.free()
	second.free()
	quest.free()
	inventory.free()
	print("WorldInventory3D: shard/forest reward and crafting game flow passed")
	quit(0)
