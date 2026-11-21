extends RefCounted
## Guided first session: eight short goals that teach the core loop (gather -> refine -> craft ->
## arm -> build -> take a risk -> trade/store). Each goal completes by itself from the client's
## own state, so it never needs server changes, and progress is remembered between sessions.
## Shown as the top line of the HUD quest card; F3 skips the guide.

const SAVE_PATH := "user://first_steps.cfg"
const STEPS := [
	{"id": "wood", "text": "Gather wood: walk up to a tree and press E (3 wood)."},
	{"id": "stone", "text": "Gather stone: press E at a rock (2 stone)."},
	{"id": "planks", "text": "At a workbench (the settlement's, or one you build) press C and refine planks."},
	{"id": "tool", "text": "Craft an axe or a pickaxe at the workbench (C): tools gather higher tiers."},
	{"id": "weapon", "text": "Arm yourself: craft a club or spear and press 4 to equip it."},
	{"id": "build", "text": "Build: press U, pick a piece with 1-0, click to place (walls, floor, door, bed...)."},
	{"id": "risk", "text": "Head away from the settlement into the yellow zone: better resources, but death costs your gear."},
	{"id": "store", "text": "Bank your haul: build a chest (U, 9) or visit the settlement workbench and deposit (B)."},
]

static var step := 0
static var skipped := false
static var _loaded := false
static var _deposited := false


static func load_state() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		step = clampi(int(config.get_value("guide", "step", 0)), 0, STEPS.size())
		skipped = bool(config.get_value("guide", "skipped", false))


static func save_state() -> void:
	var config := ConfigFile.new()
	config.set_value("guide", "step", step)
	config.set_value("guide", "skipped", skipped)
	config.save(SAVE_PATH)


static func active() -> bool:
	load_state()
	return not skipped and step < STEPS.size()


static func current_text() -> String:
	if not active():
		return ""
	return "%d/%d  %s" % [step + 1, STEPS.size(), str(STEPS[step]["text"])]


static func skip() -> void:
	skipped = true
	save_state()


## The stash was used (a deposit result came back ok).
static func note_deposit() -> void:
	_deposited = true


static func _owns_any(inventory, prefix: String) -> bool:
	for t in range(1, 9):
		if inventory.count("%s%d" % [prefix, t]) > 0:
			return true
	return false


## Whether the current goal is met by the client's state.
static func goal_met(client) -> bool:
	var inv = client.inventory
	match str(STEPS[step]["id"]):
		"wood":
			return inv.count("wood_1") >= 3
		"stone":
			return inv.count("stone_1") >= 2
		"planks":
			return _owns_any(inv, "plank_")
		"tool":
			return _owns_any(inv, "axe_") or _owns_any(inv, "pickaxe_")
		"weapon":
			return str(inv.weapon) != ""
		"build":
			for item in client.barricades.values():
				if int(item.get("owner", -1)) == client.peer_id:
					return true
			return false
		"risk":
			var p: Vector3 = client.predicted
			return p.is_finite() and client.world.zone_at(p.x, p.z) >= 1
		"store":
			return _deposited
	return false


## Advances past every goal already met. Returns the number of goals just completed.
static func update(client) -> int:
	if not active() or client == null:
		return 0
	var advanced := 0
	while step < STEPS.size() and goal_met(client):
		step += 1
		advanced += 1
	if advanced > 0:
		save_state()
	return advanced
