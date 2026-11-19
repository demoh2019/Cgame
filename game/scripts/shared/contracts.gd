extends RefCounted
## Finite camp contracts that connect survival scavenging, classless crafting
## and infected PvE. All state transitions run on the authoritative server.
## No client-supplied reward, quantity, progress or target ID is trusted.

const Inventory = preload("res://scripts/shared/inventory.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")

const ORDER := ["camp_supplies", "weapon_training", "infected_patrol", "ruin_recovery"]
const CATALOG := {
	"camp_supplies": {
		"title": "Supply the camp",
		"deliver": {"wood_1": 4, "fiber_1": 3},
		"possess": {},
		"kills": 0,
		"reward": {"silver": 12, "bandage": 1},
	},
	"weapon_training": {
		"title": "Arm the survivors",
		"deliver": {},
		"possess": {"club_1": 1},
		"kills": 0,
		"reward": {"silver": 18, "water_bottle": 1},
	},
	"infected_patrol": {
		"title": "Clear the infected",
		"deliver": {},
		"possess": {},
		"kills": 2,
		"reward": {"silver": 35, "canned_food": 2},
	},
	"ruin_recovery": {
		"title": "Recover supplies from the ruins",
		"deliver": {},
		"possess": {},
		"kills": 0,
		"crates": 2,
		"reward": {"silver": 60, "ammo_9mm": 10},
	},
}


static func empty_state() -> Dictionary:
	return {"active": "", "progress": 0, "completed": [], "crate_ids": []}


static func valid_state(data: Variant) -> bool:
	if not (data is Dictionary) or (data.size() != 3 and data.size() != 4):
		return false
	var active: Variant = data.get("active")
	var progress: Variant = data.get("progress")
	var completed: Variant = data.get("completed")
	if not (active is String) or not (completed is Array):
		return false
	if not SaveValidation.valid_counter(progress) or int(progress) > 2:
		return false
	if completed.size() > ORDER.size():
		return false
	# The reward order is a prefix, never an arbitrary client-forged set.
	for i in completed.size():
		if not (completed[i] is String) or completed[i] != ORDER[i]:
			return false
	var next: String = ORDER[completed.size()] if completed.size() < ORDER.size() else ""
	if active != "" and active != next:
		return false
	if active == "" and int(progress) != 0:
		return false
	var visited: Variant = data.get("crate_ids", [])
	if not (visited is Array) or visited.size() > 2:
		return false
	var ids: Dictionary = {}
	for key in visited:
		if not (key is String) or key.is_empty() or key.length() > 24 or ids.has(key):
			return false
		ids[key] = true
	if active != "":
		var goal: int = int(CATALOG[active]["kills"]) + int(CATALOG[active].get("crates", 0))
		if int(progress) > goal:
			return false
		if active == "ruin_recovery":
			if visited.size() != int(progress):
				return false
		elif not visited.is_empty():
			return false
	elif not visited.is_empty():
		return false
	return true


static func description(state: Dictionary) -> String:
	if not valid_state(state):
		return "Contract data invalid"
	var active: String = str(state["active"])
	if active == "":
		if state["completed"].size() >= ORDER.size():
			return "All camp contracts completed"
		return "Visit the camp workbench to accept a contract"
	var rule: Dictionary = CATALOG[active]
	var label: String = str(rule["title"])
	if int(rule["kills"]) > 0:
		label += " (%d/%d infected)" % [int(state["progress"]), int(rule["kills"])]
	elif int(rule.get("crates", 0)) > 0:
		label += " (%d/%d distinct ruin caches)" % [int(state["progress"]), int(rule["crates"])]
	return label


static func accept(state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_state"}
	if str(state["active"]) != "":
		return {"ok": false, "reason": "already_active"}
	var done: Array = state["completed"]
	if done.size() >= ORDER.size():
		return {"ok": false, "reason": "all_complete"}
	var next: String = ORDER[done.size()]
	state["active"] = next
	state["progress"] = 0
	state["crate_ids"] = []
	return {"ok": true, "active": next, "title": str(CATALOG[next]["title"])}


static func record_kill(state: Dictionary) -> bool:
	if not valid_state(state):
		return false
	var active: String = str(state["active"])
	if active == "" or int(CATALOG[active]["kills"]) == 0:
		return false
	var target: int = int(CATALOG[active]["kills"])
	if int(state["progress"]) >= target:
		return false
	state["progress"] = int(state["progress"]) + 1
	return true


## One server-confirmed ruin cache only counts once for the character,
## even if the physical cache refills later.
static func record_crate(state: Dictionary, crate_id: int) -> bool:
	if not valid_state(state) or str(state["active"]) != "ruin_recovery":
		return false
	var key: String = str(crate_id)
	var seen: Array = state.get("crate_ids", [])
	var required: int = int(CATALOG["ruin_recovery"]["crates"])
	if seen.has(key) or int(state["progress"]) >= required:
		return false
	seen.append(key)
	state["crate_ids"] = seen
	state["progress"] = int(state["progress"]) + 1
	return true


static func claim(carried, state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_state"}
	var active: String = str(state["active"])
	if active == "":
		return {"ok": false, "reason": "no_active"}
	var rule: Dictionary = CATALOG[active]
	if int(state["progress"]) < int(rule["kills"]) + int(rule.get("crates", 0)):
		return {"ok": false, "reason": "incomplete"}

	# Use an independent copy to ensure a partial debit or a full backpack
	# cannot consume materials or mint a fraction of the reward.
	var trial = Inventory.new(carried.slots.size())
	trial.load_dict(carried.to_dict())
	for item_id in rule["possess"]:
		if trial.count(str(item_id)) < int(rule["possess"][item_id]):
			return {"ok": false, "reason": "missing_items"}
	for item_id in rule["deliver"]:
		if not trial.remove(str(item_id), int(rule["deliver"][item_id])):
			return {"ok": false, "reason": "missing_items"}
	for item_id in rule["reward"]:
		if trial.add(str(item_id), int(rule["reward"][item_id])) != 0:
			return {"ok": false, "reason": "no_space"}

	carried.load_dict(trial.to_dict())
	carried.unequip_missing()
	var completed: Array = state["completed"]
	completed.append(active)
	state["active"] = ""
	state["progress"] = 0
	state["crate_ids"] = []
	return {"ok": true, "completed": active, "title": str(rule["title"]), "reward": rule["reward"].duplicate(true)}
