extends SceneTree

const Inventory = preload("res://addons/visual_quality/inventory_component.gd")
const Catalog = preload("res://addons/visual_quality/item_catalog.gd")


func _initialize() -> void:
	var inv = Inventory.new()
	inv.save_enabled = false
	assert(not inv.craft("spark_core"), "Cannot craft from missing ingredients")
	assert(inv.add_item("light_shard", 5))
	var before: Dictionary = inv.items_snapshot()
	var simulated: Dictionary = Inventory.simulate_recipe(before, Catalog.get_recipe("spark_core"))
	assert(before["light_shard"] == 5, "Craft simulation must not mutate input")
	assert(simulated["light_shard"] == 3)
	assert(simulated["spark_core"] == 1)
	assert(inv.craft("spark_core"))
	assert(inv.get_count("light_shard") == 3)
	assert(inv.get_count("spark_core") == 1)
	assert(not inv.craft("forest_lantern"))
	assert(inv.get_count("spark_core") == 1, "Failed craft must not consume inputs")
	assert(inv.add_item("forest_essence", 2))
	assert(inv.craft("forest_lantern"))
	assert(inv.get_count("forest_essence") == 0)
	assert(inv.get_count("spark_core") == 0)
	assert(inv.get_count("forest_lantern") == 1)
	assert(not inv.add_item("forest_lantern", 1), "Unique item capacity")
	assert(not inv.craft("forest_lantern"))
	var snapshot: Dictionary = inv.items_snapshot()
	assert(Inventory.simulate_recipe(snapshot, {"inputs": {"bad_item": 1}, "output_id": "spark_core", "output_count": 1}).is_empty())
	inv.free()
	print("WorldInventory3D: atomic crafting and rollback checks passed")
	quit(0)
