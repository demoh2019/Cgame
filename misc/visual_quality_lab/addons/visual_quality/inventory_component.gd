extends Node
class_name WorldInventory3D
## Portable, saveable item stacks, idempotent world rewards and atomic crafting.
## Callers should use stable item IDs, not references to streamed game objects.

signal inventory_changed(item_id: String, new_count: int)
signal item_crafted(recipe_id: String, output_id: String, quantity: int)
signal inventory_error(reason: String)
signal equipment_changed(slot: String, item_id: String)

const Catalog = preload("res://addons/visual_quality/item_catalog.gd")
const FORMAT_VERSION: int = 1
const MAX_REWARD_CLAIMS: int = 8192

@export var world_id: String = "visual_quality_lab_forest_20261120"
@export var save_enabled: bool = true
@export var save_path: String = "user://visual_quality_inventory_v1.cfg"

var _items: Dictionary = {}  # String item_id -> int count, zero entries omitted
var _claimed_sources: Dictionary = {}  # String source_uid -> true
var _equipped: Dictionary = {}  # slot -> owned item ID


func _ready() -> void:
	load_from_disk()


func get_count(item_id: String) -> int:
	return int(_items.get(item_id, 0))


func items_snapshot() -> Dictionary:
	return _items.duplicate(true)


func equipped_snapshot() -> Dictionary:
	return _equipped.duplicate(true)


func get_equipped_item(slot: String) -> String:
	return str(_equipped.get(slot, ""))


func equip_item(item_id: String) -> bool:
	var slot: String = Catalog.equipment_slot(item_id)
	if slot.is_empty() or get_count(item_id) <= 0:
		return false
	if get_equipped_item(slot) == item_id:
		return true
	var old_equipped: Dictionary = _equipped.duplicate(true)
	_equipped[slot] = item_id
	if not _persist_or_rollback(_items, _claimed_sources, old_equipped):
		return false
	equipment_changed.emit(slot, item_id)
	return true


func unequip_slot(slot: String) -> bool:
	if not _equipped.has(slot):
		return false
	var old_equipped: Dictionary = _equipped.duplicate(true)
	_equipped.erase(slot)
	if not _persist_or_rollback(_items, _claimed_sources, old_equipped):
		return false
	equipment_changed.emit(slot, "")
	return true


func claim_count() -> int:
	return _claimed_sources.size()


func has_claimed(source_uid: String) -> bool:
	return _claimed_sources.has(source_uid)


func can_add(item_id: String, quantity: int) -> bool:
	return Catalog.is_valid_item(item_id) and quantity > 0 \
		and get_count(item_id) <= Catalog.max_stack(item_id) - quantity


func add_item(item_id: String, quantity: int = 1) -> bool:
	if not can_add(item_id, quantity):
		inventory_error.emit("Нет места для %s" % item_id)
		return false
	var old_items: Dictionary = _items.duplicate(true)
	_items[item_id] = get_count(item_id) + quantity
	if not _persist_or_rollback(old_items, _claimed_sources, _equipped):
		return false
	inventory_changed.emit(item_id, get_count(item_id))
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not Catalog.is_valid_item(item_id) or quantity <= 0 or get_count(item_id) < quantity:
		return false
	var old_items: Dictionary = _items.duplicate(true)
	var old_equipped: Dictionary = _equipped.duplicate(true)
	var updated: int = get_count(item_id) - quantity
	if updated == 0:
		_items.erase(item_id)
		for slot in _equipped.keys():
			if _equipped[slot] == item_id:
				_equipped.erase(slot)
	else:
		_items[item_id] = updated
	if not _persist_or_rollback(old_items, _claimed_sources, old_equipped):
		return false
	for slot in old_equipped.keys():
		if not _equipped.has(slot):
			equipment_changed.emit(slot, "")
	inventory_changed.emit(item_id, updated)
	return true


func grant_once(source_uid: String, item_id: String, quantity: int = 1) -> bool:
	# Source keys survive streaming and even a quest reset. Never grant twice.
	if not valid_source_uid(source_uid) or has_claimed(source_uid) \
			or _claimed_sources.size() >= MAX_REWARD_CLAIMS or not can_add(item_id, quantity):
		return false
	var old_items: Dictionary = _items.duplicate(true)
	var old_claims: Dictionary = _claimed_sources.duplicate(true)
	_items[item_id] = get_count(item_id) + quantity
	_claimed_sources[source_uid] = true
	if not _persist_or_rollback(old_items, old_claims, _equipped):
		return false
	inventory_changed.emit(item_id, get_count(item_id))
	return true


func import_quest_history(quest_seed: int, collected_ids: PackedInt32Array) -> int:
	# Backward-compatible one-time migration from the v6+ quest save. Already
	# claimed IDs are skipped even if their rewards have since been crafted.
	var old_items: Dictionary = _items.duplicate(true)
	var old_claims: Dictionary = _claimed_sources.duplicate(true)
	var added: int = 0
	for index in collected_ids:
		if index < 0 or index >= 32 or _claimed_sources.size() >= MAX_REWARD_CLAIMS:
			continue
		var uid: String = "quest:%d:%d" % [quest_seed, index]
		if _claimed_sources.has(uid) or not can_add("light_shard", 1):
			continue
		_items["light_shard"] = get_count("light_shard") + 1
		_claimed_sources[uid] = true
		added += 1
	if added > 0:
		if not _persist_or_rollback(old_items, old_claims, _equipped):
			return 0
		inventory_changed.emit("light_shard", get_count("light_shard"))
	return added


func can_craft(recipe_id: String) -> bool:
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	return not simulate_recipe(_items, recipe).is_empty()


func craft(recipe_id: String) -> bool:
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var updated: Dictionary = simulate_recipe(_items, recipe)
	if updated.is_empty():
		inventory_error.emit("Недостаточно ресурсов или места: %s" % recipe_id)
		return false
	var before: Dictionary = _items.duplicate(true)
	var before_equipped: Dictionary = _equipped.duplicate(true)
	_items = updated
	for slot in _equipped.keys():
		if get_count(str(_equipped[slot])) <= 0:
			_equipped.erase(slot)
	if not _persist_or_rollback(before, _claimed_sources, before_equipped):
		return false
	for slot in before_equipped.keys():
		if not _equipped.has(slot):
			equipment_changed.emit(slot, "")
	for item_id in recipe["inputs"].keys():
		inventory_changed.emit(str(item_id), get_count(str(item_id)))
	var produced: String = str(recipe["output_id"])
	inventory_changed.emit(produced, get_count(produced))
	item_crafted.emit(recipe_id, produced, int(recipe["output_count"]))
	return true


func save_now() -> Error:
	if not save_enabled:
		return OK
	if not save_path.begins_with("user://") or world_id.is_empty():
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	config.set_value("inventory", "format_version", FORMAT_VERSION)
	config.set_value("inventory", "world_id", world_id)
	config.set_value("inventory", "items", _items)
	config.set_value("inventory", "claimed_sources", _claimed_sources)
	config.set_value("inventory", "equipped", _equipped)
	var temp: String = save_path + ".tmp"
	var result: Error = config.save(temp)
	if result == OK:
		result = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(save_path))
	if result != OK:
		inventory_error.emit("Ошибка записи инвентаря: %d" % result)
	return result


func load_from_disk() -> bool:
	_items.clear()
	_claimed_sources.clear()
	_equipped.clear()
	if not save_enabled or not save_path.begins_with("user://"):
		return false
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path) != OK:
		return false
	if config.get_value("inventory", "format_version", -1) != FORMAT_VERSION:
		return false
	if config.get_value("inventory", "world_id", "") != world_id:
		return false
	var raw_items: Variant = config.get_value("inventory", "items", {})
	var raw_claims: Variant = config.get_value("inventory", "claimed_sources", {})
	var raw_equipped: Variant = config.get_value("inventory", "equipped", {})
	if typeof(raw_items) != TYPE_DICTIONARY or typeof(raw_claims) != TYPE_DICTIONARY \
			or typeof(raw_equipped) != TYPE_DICTIONARY:
		return false
	if raw_claims.size() > MAX_REWARD_CLAIMS:
		return false
	var checked_items: Dictionary = {}
	for key in raw_items.keys():
		if typeof(key) != TYPE_STRING or not Catalog.is_valid_item(key):
			return false
		if typeof(raw_items[key]) != TYPE_INT:
			return false
		var count: int = raw_items[key]
		if count <= 0 or count > Catalog.max_stack(key):
			return false
		checked_items[key] = count
	var checked_claims: Dictionary = {}
	for uid in raw_claims.keys():
		if typeof(uid) != TYPE_STRING or not valid_source_uid(uid) or raw_claims[uid] != true:
			return false
		checked_claims[uid] = true
	var checked_equipped: Dictionary = {}
	for slot in raw_equipped.keys():
		if typeof(slot) != TYPE_STRING or typeof(raw_equipped[slot]) != TYPE_STRING:
			return false
		var item_id: String = raw_equipped[slot]
		if Catalog.equipment_slot(item_id) != slot or int(checked_items.get(item_id, 0)) <= 0:
			return false
		checked_equipped[slot] = item_id
	_items = checked_items
	_claimed_sources = checked_claims
	_equipped = checked_equipped
	return true


func _persist_or_rollback(old_items: Dictionary, old_claims: Dictionary, old_equipped: Dictionary = {}) -> bool:
	if save_now() == OK:
		return true
	_items = old_items.duplicate(true)
	_claimed_sources = old_claims.duplicate(true)
	_equipped = old_equipped.duplicate(true)
	return false


static func valid_source_uid(uid: String) -> bool:
	return not uid.is_empty() and uid.length() <= 180 and not uid.contains("\n")


## Pure planning: *all* ingredients must exist and the output must fit before
## anything is consumed. A failed craft never mutates the caller's inventory.
static func simulate_recipe(current: Dictionary, recipe: Dictionary) -> Dictionary:
	if recipe.is_empty() or typeof(recipe.get("inputs")) != TYPE_DICTIONARY:
		return {}
	var output_id: String = str(recipe.get("output_id", ""))
	var output_count: int = int(recipe.get("output_count", 0))
	if not Catalog.is_valid_item(output_id) or output_count <= 0:
		return {}
	var updated: Dictionary = current.duplicate(true)
	for ingredient in recipe["inputs"].keys():
		if typeof(ingredient) != TYPE_STRING or not Catalog.is_valid_item(ingredient):
			return {}
		var required: int = int(recipe["inputs"][ingredient])
		if required <= 0 or int(updated.get(ingredient, 0)) < required:
			return {}
		var remaining: int = int(updated[ingredient]) - required
		if remaining == 0:
			updated.erase(ingredient)
		else:
			updated[ingredient] = remaining
	if int(updated.get(output_id, 0)) > Catalog.max_stack(output_id) - output_count:
		return {}
	updated[output_id] = int(updated.get(output_id, 0)) + output_count
	return updated
