extends RefCounted
## A fixed number of slots holding stacks of items, plus one slot each for the weapon, armour and
## tool in use. Pure data: no scene, so the server owns it and the client gets copies.

const Defs = preload("res://scripts/shared/defs.gd")
const TrailBackpack = preload("res://scripts/shared/trail_backpack.gd")
const GearDurability = preload("res://scripts/shared/gear_durability.gd")

var slots: Array = [] # Each is {} or {"id": String, "count": int}.
var weapon: String = ""
var armor: String = ""
# Worn pieces besides the body armor: slot -> item id. Each slot takes items of the kind with the same name.
const GEAR_SLOTS := ["head", "cape", "hands", "feet"]
var gear: Dictionary = {}
var wear: Dictionary = {} # item id -> durability 0..100 (absent = pristine). Shared by a stack.


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


## Equipped gear remains physically in its backpack slot, so it is counted only once.
func total_weight() -> float:
	var weight := 0.0
	for slot in slots:
		if not slot.is_empty():
			weight += Defs.item_weight(str(slot["id"])) * float(int(slot["count"]))
	return weight


## Only physically owned foot support and trained capacity adjust load comfort.
func movement_factor(capacity_bonus: float = 0.0) -> float:
	return Defs.carry_speed_factor(TrailBackpack.effective_weight(self) /
		(1.0 + maxf(capacity_bonus, 0.0)))


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
	# Equipment and durability belong to items still physically carried.
	# Dropping the final copy must not leave a phantom equipped weapon or
	# give a later, freshly acquired item the old one's damage.
	if count(id) == 0:
		wear.erase(id)
		if is_equipped(id):
			unequip_missing()
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
		"head", "cape", "hands", "feet":
			gear[str(data["kind"])] = id
			return true
	return false


## Everything worn for protection: the body armor and the pieces in the gear slots.
func worn() -> Array:
	var pieces: Array = []
	if armor != "" and count(armor) > 0:
		pieces.append(armor)
	for slot in GEAR_SLOTS:
		var piece: String = str(gear.get(slot, ""))
		if piece != "" and count(piece) > 0: # Only what is still carried protects.
			pieces.append(piece)
	return pieces


func is_equipped(id: String) -> bool:
	return id != "" and (id == weapon or id == armor or gear.values().has(id))


func unequip_missing() -> void:
	# Called after items leave the inventory: drop equipment that is no longer carried.
	if weapon != "" and count(weapon) < 1:
		weapon = ""
	if armor != "" and count(armor) < 1:
		armor = ""
	for slot in gear.keys():
		if count(str(gear[slot])) < 1:
			gear.erase(slot)


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
	gear = {}
	wear.clear()
	return result


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "weapon": weapon, "armor": armor, "gear": gear.duplicate(), "wear": wear.duplicate()}


func load_dict(data: Dictionary) -> void:
	slots = data.get("slots", []).duplicate(true)
	weapon = data.get("weapon", "")
	armor = data.get("armor", "")
	gear = (data.get("gear", {}) as Dictionary).duplicate() if data.get("gear", {}) is Dictionary else {}
	wear = {}
	var saved_wear: Variant = data.get("wear", {})
	if saved_wear is Dictionary:
		for id in saved_wear:
			if not Defs.item(str(id)).is_empty():
				wear[str(id)] = GearDurability.clamp_durability(float(saved_wear[id]))


## Durability of an item (100 when never damaged).
func durability(id: String) -> float:
	return float(wear.get(id, GearDurability.MAX))


## 1.0 normally, 0.5 for broken (0%) gear.
func effectiveness(id: String) -> float:
	return GearDurability.effectiveness(durability(id))


func damage_item(id: String, amount: float) -> void:
	if id == "" or amount <= 0.0 or count(id) < 1:
		return
	var left: float = GearDurability.clamp_durability(durability(id) - amount)
	if left >= GearDurability.MAX:
		wear.erase(id)
	else:
		wear[id] = left


## Wear on everything worn for protection (one received hit).
func wear_worn(amount: float = GearDurability.ARMOR_WEAR_PER_HIT) -> void:
	for piece in worn():
		damage_item(str(piece), amount)


## Wear on every equipped item (weapon and protection), e.g. on a kept-gear death.
func wear_equipped(amount: float) -> void:
	damage_item(weapon, amount)
	wear_worn(amount)


## Silver needed to repair every damaged carried item.
func repair_cost() -> int:
	var total := 0
	for id in wear.keys():
		if count(str(id)) > 0:
			total += GearDurability.repair_cost(float(Defs.item(str(id)).get("value", 1)), GearDurability.MAX - durability(str(id)))
	return total


## Restores every carried damaged item to 100%. Returns the item ids repaired.
func repair_all() -> Array:
	var repaired: Array = []
	for id in wear.keys():
		if count(str(id)) > 0:
			repaired.append(str(id))
	for id in repaired:
		wear.erase(id)
	return repaired
