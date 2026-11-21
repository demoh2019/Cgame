extends SceneTree

const Store = preload("res://addons/visual_quality/world_state_store.gd")


func _initialize() -> void:
	assert(Store.cell_key(Vector2i(2, -3)) == "2:-3")
	assert(Store.valid_cell_key("2:-3"))
	assert(Store.valid_cell_key("-100:999"))
	assert(not Store.valid_cell_key("2:three"))
	assert(not Store.valid_cell_key("2:3:4"))
	assert(not Store.valid_cell_key(""))
	var sanitized: Dictionary = Store.sanitize_state({
		"activated": true,
		"count": 5,
		"label": "checkpoint",
		"position": Vector3(1.0, 2.0, 3.0),
		"unsafe": RefCounted.new()
	})
	assert(sanitized.size() == 4)
	assert(sanitized["activated"] == true)
	assert(not sanitized.has("unsafe"))
	assert(Store.sanitize_state("not a dictionary").is_empty())
	assert(Store.sanitize_state({"": true}).is_empty())

	var filename: String = "user://visual_lab_state_unit_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	var writer = Store.new()
	writer.save_path = filename
	writer.world_id = "unit_world_v1"
	writer.save_on_exit = false
	writer._states[Store.cell_key(Vector2i(2, -3))] = {"activated": true}
	assert(writer.save_now() == OK)
	var reader = Store.new()
	reader.save_path = filename
	reader.world_id = "unit_world_v1"
	reader.save_on_exit = false
	assert(reader.load_from_disk())
	assert(reader.saved_cell_count() == 1)
	assert(reader.get_saved_state(Vector2i(2, -3)).get("activated", false))
	# A caller cannot modify saved state through the returned dictionary.
	var copy: Dictionary = reader.get_saved_state(Vector2i(2, -3))
	copy["activated"] = false
	assert(reader.get_saved_state(Vector2i(2, -3))["activated"] == true)
	var unrelated = Store.new()
	unrelated.save_path = filename
	unrelated.world_id = "different_world"
	unrelated.save_on_exit = false
	assert(not unrelated.load_from_disk())
	assert(unrelated.saved_cell_count() == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	writer.free()
	reader.free()
	unrelated.free()
	print("WorldStateStore3D: 19 unit checks passed")
	quit(0)
