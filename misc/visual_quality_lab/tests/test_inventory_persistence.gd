extends SceneTree

const Inventory = preload("res://addons/visual_quality/inventory_component.gd")


func _initialize() -> void:
	var filename: String = "user://visual_inventory_v15_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	var writer = Inventory.new()
	writer.save_path = filename
	writer.world_id = "inventory_test_world"
	assert(writer.grant_once("quest:100:1", "light_shard", 3))
	assert(writer.grant_once("beacon:0:0", "forest_essence", 1))
	assert(FileAccess.file_exists(filename))
	var reader = Inventory.new()
	reader.save_path = filename
	reader.world_id = "inventory_test_world"
	assert(reader.load_from_disk())
	assert(reader.get_count("light_shard") == 3)
	assert(reader.claim_count() == 2)
	assert(not reader.grant_once("quest:100:1", "light_shard"))
	assert(reader.craft("spark_core"))
	assert(reader.get_count("light_shard") == 1)
	var reloaded = Inventory.new()
	reloaded.save_path = filename
	reloaded.world_id = "inventory_test_world"
	assert(reloaded.load_from_disk())
	assert(reloaded.get_count("light_shard") == 1, "Craft results must persist")
	assert(reloaded.get_count("spark_core") == 1)
	assert(not reloaded.grant_once("quest:100:1", "light_shard", 1))
	var other = Inventory.new()
	other.save_path = filename
	other.world_id = "different_world"
	assert(not other.load_from_disk())
	assert(other.items_snapshot().is_empty())
	var malicious = Inventory.new()
	malicious.save_path = "/tmp/outside-save.cfg"
	assert(not malicious.add_item("light_shard", 1))
	assert(malicious.get_count("light_shard") == 0, "Save failures roll back state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	writer.free()
	reader.free()
	reloaded.free()
	other.free()
	malicious.free()
	print("WorldInventory3D: persistent claims, crafting and world isolation passed")
	quit(0)
