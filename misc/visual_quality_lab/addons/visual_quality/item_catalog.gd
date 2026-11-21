extends RefCounted
class_name VisualItemCatalog
## Stable item identifiers and recipes. Data can later be replaced by Resources.
## Gameplay/inventory state stores IDs and counts, never Node references.

const DEFINITIONS: Dictionary = {
	"light_shard": {"display_name": "Световой осколок", "max_stack": 99},
	"forest_essence": {"display_name": "Лесная эссенция", "max_stack": 99},
	"spark_core": {"display_name": "Искровое ядро", "max_stack": 20},
	"forest_lantern": {"display_name": "Лесной фонарь", "max_stack": 1, "slot": "utility", "modifiers": {"max_stamina": 20.0}},
	"trail_boots": {"display_name": "Сапоги следопыта", "max_stack": 1, "slot": "feet", "modifiers": {"move_speed": 0.25}}
}

const RECIPES: Dictionary = {
	"spark_core": {
		"inputs": {"light_shard": 2},
		"output_id": "spark_core", "output_count": 1
	},
	"forest_lantern": {
		"inputs": {"spark_core": 1, "forest_essence": 2},
		"output_id": "forest_lantern", "output_count": 1
	},
	"trail_boots": {
		"inputs": {"light_shard": 1, "forest_essence": 2},
		"output_id": "trail_boots", "output_count": 1
	}
}


static func is_valid_item(item_id: String) -> bool:
	return DEFINITIONS.has(item_id)


static func max_stack(item_id: String) -> int:
	return int(DEFINITIONS.get(item_id, {}).get("max_stack", 0))


static func equipment_slot(item_id: String) -> String:
	return str(DEFINITIONS.get(item_id, {}).get("slot", ""))


static func equipment_modifiers(item_id: String) -> Dictionary:
	return DEFINITIONS.get(item_id, {}).get("modifiers", {}).duplicate(true)


static func item_name(item_id: String) -> String:
	return str(DEFINITIONS.get(item_id, {}).get("display_name", item_id))


static func get_recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {}).duplicate(true)


static func all_item_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for item_id in DEFINITIONS.keys():
		ids.append(item_id)
	ids.sort()
	return ids
