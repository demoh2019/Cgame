extends RefCounted
## A fixed number of slots holding stacks of items, plus one slot each for the weapon, armour and
## tool in use. Pure data: no scene, so the server owns it and the client gets copies.

const Defs = preload("res://scripts/shared/defs.gd")

var slots: Array = [] # Each is {} or {"id": String, "count": int}.
var weapon: String = ""
var armor: String = ""


func _init(p_slots: int = Defs.INVENTORY_SLOTS) -> void:
	slots.resize(p_slots)
	for i in p_slots:
		slots[i] = {}


func count(id: String) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot["id"] == id:
			total += int(slot["count"])
	return total


func has_all(inputs: Dictionary) -> bool:
	for id in inputs:
		if count(id) < int(inputs[id]):
			return false
	return true


func free_space_for(id: String) -> int:
	# How many more of this item fit: room in matching stacks plus empty slots.
	if not Defs.is_item(id):
		return 0
	var stack := Defs.stack_size(id)
	var room := 0
	for slot in slots:
		if slot.is_empty():
			room += stack
		elif slot["id"] == id:
			room += stack - int(slot["count"])
	return room


## Adds as many as fit and returns the number that did not.
func add(id: String, amount: int) -> int:
	if amount <= 0 or not Defs.is_item(id):
		return maxi(amount, 0)
	var stack := Defs.stack_size(id)
	var left := amount
	for slot in slots:
		if left == 0:
			break
		if not slot.is_empty() and slot["id"] == id and int(slot["count"]) < stack:
			var moved := mini(left, stack - int(slot["count"]))
			slot["count"] = int(slot["count"]) + moved
			left -= moved
	for i in slots.size():
		if left == 0:
			break
		if slots[i].is_empty():
			var moved := mini(left, stack)
			slots[i] = {"id": id, "count": moved}
			left -= moved
	return left


## Removes exactly `amount` or nothing. Returns whether it succeeded.
func remove(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if count(id) < amount:
		return false
	var left := amount
	# Take from the smallest stacks first so big stacks stay together.
	var order: Array = []
	for i in slots.size():
		if not slots[i].is_empty() and slots[i]["id"] == id:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return slots[a]["count"] < slots[b]["count"])
	for i in order:
		if left == 0:
			break
		var taken := mini(left, int(slots[i]["count"]))
		slots[i]["count"] = int(slots[i]["count"]) - taken
		left -= taken
		if int(slots[i]["count"]) == 0:
			slots[i] = {}
	return true


func equip(id: String) -> bool:
	var data := Defs.item(id)
	if data.is_empty() or count(id) < 1:
		return false
	match data.get("kind", ""):
		"weapon":
			weapon = id
			return true
		"armor":
			armor = id
			return true
	return false


func unequip_missing() -> void:
	# Called after items leave the inventory: drop equipment that is no longer carried.
	if weapon != "" and count(weapon) < 1:
		weapon = ""
	if armor != "" and count(armor) < 1:
		armor = ""


## Best tool of a kind that is carried (the highest tier).
func best_tool(tool_kind: String) -> String:
	var best := ""
	var best_tier := 0
	for slot in slots:
		if slot.is_empty():
			continue
		var data := Defs.item(slot["id"])
		if data.get("kind", "") == "tool" and data.get("tool", "") == tool_kind and int(data["tier"]) > best_tier:
			best = slot["id"]
			best_tier = int(data["tier"])
	return best


## Empties the inventory (including equipment) and returns everything as {id: count}.
func take_everything() -> Dictionary:
	var result: Dictionary = {}
	for i in slots.size():
		if not slots[i].is_empty():
			result[slots[i]["id"]] = int(result.get(slots[i]["id"], 0)) + int(slots[i]["count"])
			slots[i] = {}
	weapon = ""
	armor = ""
	return result


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "weapon": weapon, "armor": armor}


func load_dict(data: Dictionary) -> void:
	slots = data.get("slots", []).duplicate(true)
	weapon = data.get("weapon", "")
	armor = data.get("armor", "")
