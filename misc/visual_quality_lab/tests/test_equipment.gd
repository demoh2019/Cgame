extends SceneTree

const Inventory = preload("res://addons/visual_quality/inventory_component.gd")
const Catalog = preload("res://addons/visual_quality/item_catalog.gd")


func _initialize() -> void:
	assert(Catalog.equipment_slot("trail_boots") == "feet")
	assert(Catalog.equipment_slot("forest_lantern") == "utility")
	assert(Catalog.equipment_slot("light_shard").is_empty())
	assert(Catalog.equipment_modifiers("trail_boots")["move_speed"] == 0.25)
	var inventory = Inventory.new()
	inventory.save_enabled = false
	assert(not inventory.equip_item("trail_boots"))
	assert(inventory.add_item("trail_boots", 1))
	assert(inventory.equip_item("trail_boots"))
	assert(inventory.get_equipped_item("feet") == "trail_boots")
	var copy: Dictionary = inventory.equipped_snapshot()
	copy["feet"] = "invalid"
	assert(inventory.get_equipped_item("feet") == "trail_boots")
	assert(inventory.add_item("forest_lantern", 1))
	assert(inventory.equip_item("forest_lantern"))
	assert(inventory.get_equipped_item("utility") == "forest_lantern")
	assert(inventory.remove_item("trail_boots"))
	assert(inventory.get_equipped_item("feet").is_empty())
	assert(not inventory.equip_item("light_shard"))
	assert(inventory.unequip_slot("utility"))
	assert(not inventory.unequip_slot("utility"))
	inventory.free()
	print("WorldInventory3D: equipment validation, ownership and auto-unequip passed")
	quit(0)
