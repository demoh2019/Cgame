extends SceneTree

const Inventory = preload("res://addons/visual_quality/inventory_component.gd")
const Catalog = preload("res://addons/visual_quality/item_catalog.gd")


func _initialize() -> void:
	assert(Catalog.is_valid_item("light_shard"))
	assert(not Catalog.is_valid_item("unknown_item"))
	assert(Catalog.max_stack("forest_lantern") == 1)
	assert(Catalog.get_recipe("spark_core")["inputs"]["light_shard"] == 2)
	var inv = Inventory.new()
	inv.save_enabled = false
	assert(not inv.add_item("bad_item", 1))
	assert(not inv.add_item("light_shard", -1))
	assert(inv.add_item("light_shard", 99))
	assert(not inv.add_item("light_shard", 1), "Stack limit must be enforced")
	assert(inv.get_count("light_shard") == 99)
	assert(not inv.remove_item("light_shard", 100))
	assert(inv.remove_item("light_shard", 97))
	assert(inv.get_count("light_shard") == 2)
	var copy: Dictionary = inv.items_snapshot()
	copy["light_shard"] = 999
	assert(inv.get_count("light_shard") == 2)
	assert(inv.grant_once("beacon:1:2", "forest_essence", 1))
	assert(not inv.grant_once("beacon:1:2", "forest_essence", 1))
	assert(inv.get_count("forest_essence") == 1)
	assert(not inv.grant_once("bad\nsource", "forest_essence", 1))
	var recovered: PackedInt32Array = PackedInt32Array([0, 1, 1, 2])
	assert(inv.import_quest_history(42, recovered) == 3)
	assert(inv.import_quest_history(42, recovered) == 0)
	assert(inv.get_count("light_shard") == 5)
	inv.free()
	print("WorldInventory3D: stack limits, deduplication and migration passed")
	quit(0)
