extends SceneTree

const Inventory = preload("res://addons/visual_quality/inventory_component.gd")


func _initialize() -> void:
	var path: String = "user://v16_equipment_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var inv = Inventory.new()
	inv.save_path = path
	inv.world_id = "equipment_test"
	assert(inv.add_item("trail_boots"))
	assert(inv.add_item("forest_lantern"))
	assert(inv.equip_item("trail_boots"))
	assert(inv.equip_item("forest_lantern"))
	var loaded = Inventory.new()
	loaded.save_path = path
	loaded.world_id = "equipment_test"
	assert(loaded.load_from_disk())
	assert(loaded.get_equipped_item("feet") == "trail_boots")
	assert(loaded.get_equipped_item("utility") == "forest_lantern")
	assert(loaded.remove_item("trail_boots"))
	var updated = Inventory.new()
	updated.save_path = path
	updated.world_id = "equipment_test"
	assert(updated.load_from_disk())
	assert(updated.get_equipped_item("feet").is_empty())
	assert(updated.get_equipped_item("utility") == "forest_lantern")
	# v15 save with no 'equipped' key must continue to load.
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("inventory", "format_version", 1)
	legacy.set_value("inventory", "world_id", "equipment_test")
	legacy.set_value("inventory", "items", {"forest_lantern": 1})
	legacy.set_value("inventory", "claimed_sources", {})
	assert(legacy.save(path) == OK)
	assert(updated.load_from_disk())
	assert(updated.get_equipped_item("utility").is_empty())
	# Reject a forged equipment slot without accepting partially valid state.
	legacy.set_value("inventory", "equipped", {"feet": "forest_lantern"})
	assert(legacy.save(path) == OK)
	assert(not updated.load_from_disk())
	assert(updated.equipped_snapshot().is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	inv.free()
	loaded.free()
	updated.free()
	print("WorldInventory3D: persisted equipment, rollback and v15 save compatibility passed")
	quit(0)
