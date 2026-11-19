extends RefCounted
## Static game data shared by the server and the client: items, recipes, zones and tuning numbers.
## Everything here is plain data and pure functions, so it can be unit tested without a scene.

const CHUNK_SIZE := 64.0
const WATER_LEVEL := 0.0
const TICK_RATE := 20 # Server simulation ticks per second.
const SNAPSHOT_RATE := 10 # Snapshots per second.
const INTEREST_RADIUS := 90.0 # Entities farther than this from a player are not sent to them.

# --- Zones (Albion style): the farther from the hub, the higher the tier and the danger. -------
const HUB_SAFE_RADIUS := 45.0 # Nobody can be hurt inside it.
const ZONE_RADII := [260.0, 620.0, 1050.0] # Green ends at 260 m, yellow at 620 m, red at 1050 m, then black.
const ZONE_NAMES := ["green", "yellow", "red", "black"]
const MAX_TIER := 4

# --- Player tuning -------------------------------------------------------------------------------
const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.6
const PLAYER_RADIUS := 0.45
const REACH := 2.6 # Gathering / looting distance.
const MELEE_RANGE := 2.2
const PISTOL_RANGE := 40.0
const MAX_HEALTH := 100.0
const HUNGER_PER_SECOND := 0.045
const THIRST_PER_SECOND := 0.07
const STARVE_DAMAGE_PER_SECOND := 1.2
const INVENTORY_SLOTS := 24
const RESPAWN_SECONDS := 4.0

# --- Zombies ---------------------------------------------------------------------------------------
const ZOMBIES := {
	"walker": {"health": 45.0, "speed": 1.7, "damage": 9.0, "attack_range": 1.6, "attack_cooldown": 1.3, "notice": 16.0, "lose": 34.0, "xp": 5},
	"runner": {"health": 28.0, "speed": 4.4, "damage": 7.0, "attack_range": 1.6, "attack_cooldown": 0.9, "notice": 24.0, "lose": 40.0, "xp": 8},
	"brute": {"health": 170.0, "speed": 2.2, "damage": 26.0, "attack_range": 2.0, "attack_cooldown": 1.8, "notice": 14.0, "lose": 30.0, "xp": 25},
}

# --- Items -------------------------------------------------------------------------------------------
# Built once: tiered materials, tools, weapons and armour (Albion style), plus a few Days After
# scavenging items that only exist as loot.

static var _items: Dictionary = {}
static var _recipes: Dictionary = {}


static func items() -> Dictionary:
	if _items.is_empty():
		_build_items()
	return _items


static func recipes() -> Dictionary:
	if _recipes.is_empty():
		_build_items()
	return _recipes


static func item(id: String) -> Dictionary:
	return items().get(id, {})


static func is_item(id: String) -> bool:
	return items().has(id)


static func stack_size(id: String) -> int:
	return int(item(id).get("stack", 1))


static func tier_of(id: String) -> int:
	return int(item(id).get("tier", 0))


static func zone_index_for_distance(distance: float) -> int:
	for i in ZONE_RADII.size():
		if distance < ZONE_RADII[i]:
			return i
	return ZONE_RADII.size()


static func _add_item(id: String, data: Dictionary) -> void:
	data["id"] = id
	if not data.has("stack"):
		data["stack"] = 1
	_items[id] = data


static func _add_recipe(id: String, output: String, count: int, inputs: Dictionary, station: String = "", seconds: float = 2.0) -> void:
	_recipes[id] = {"id": id, "output": output, "count": count, "inputs": inputs, "station": station, "seconds": seconds}


static func _build_items() -> void:
	_items = {}
	_recipes = {}
	for t in range(1, MAX_TIER + 1):
		# Raw materials gathered in the world; they stack high.
		_add_item("wood_%d" % t, {"name": "Wood T%d" % t, "kind": "resource", "tier": t, "stack": 100, "value": 2 * t})
		_add_item("stone_%d" % t, {"name": "Stone T%d" % t, "kind": "resource", "tier": t, "stack": 100, "value": 2 * t})
		_add_item("ore_%d" % t, {"name": "Ore T%d" % t, "kind": "resource", "tier": t, "stack": 100, "value": 3 * t})
		_add_item("fiber_%d" % t, {"name": "Fiber T%d" % t, "kind": "resource", "tier": t, "stack": 100, "value": 2 * t})
		# Refined materials.
		_add_item("plank_%d" % t, {"name": "Plank T%d" % t, "kind": "material", "tier": t, "stack": 100, "value": 5 * t})
		_add_item("bar_%d" % t, {"name": "Metal Bar T%d" % t, "kind": "material", "tier": t, "stack": 100, "value": 8 * t})
		_add_item("cloth_%d" % t, {"name": "Cloth T%d" % t, "kind": "material", "tier": t, "stack": 100, "value": 5 * t})
		_add_recipe("plank_%d" % t, "plank_%d" % t, 1, {"wood_%d" % t: 2}, "workbench")
		_add_recipe("bar_%d" % t, "bar_%d" % t, 1, {"ore_%d" % t: 2}, "workbench")
		_add_recipe("cloth_%d" % t, "cloth_%d" % t, 1, {"fiber_%d" % t: 2}, "workbench")
		# Tools.
		var tool_core: Dictionary = {"stone_1": 2} if t == 1 else {"bar_%d" % t: 2}
		var axe_inputs: Dictionary = {"plank_%d" % t: 2}
		axe_inputs.merge(tool_core)
		_add_item("axe_%d" % t, {"name": "Axe T%d" % t, "kind": "tool", "tool": "axe", "tier": t, "value": 30 * t})
		_add_recipe("axe_%d" % t, "axe_%d" % t, 1, axe_inputs, "workbench", 4.0)
		var pick_inputs: Dictionary = {"plank_%d" % t: 2}
		pick_inputs.merge(tool_core)
		_add_item("pickaxe_%d" % t, {"name": "Pickaxe T%d" % t, "kind": "tool", "tool": "pickaxe", "tier": t, "value": 30 * t})
		_add_recipe("pickaxe_%d" % t, "pickaxe_%d" % t, 1, pick_inputs, "workbench", 4.0)
		# Melee weapons: a club, quick and cheap; damage and durability scale with the tier.
		var club_inputs: Dictionary = {"plank_%d" % t: 3}
		if t > 1:
			club_inputs["bar_%d" % t] = 1
		_add_item("club_%d" % t, {"name": "Club T%d" % t, "kind": "weapon", "weapon": "melee", "tier": t, "damage": 14.0 + 9.0 * (t - 1), "cooldown": 0.7, "value": 40 * t})
		_add_recipe("club_%d" % t, "club_%d" % t, 1, club_inputs, "workbench", 5.0)
		# Armour: reduces incoming damage.
		_add_item("jacket_%d" % t, {"name": "Jacket T%d" % t, "kind": "armor", "tier": t, "armor": 0.08 + 0.07 * (t - 1), "value": 35 * t})
		_add_recipe("jacket_%d" % t, "jacket_%d" % t, 1, {"cloth_%d" % t: 4}, "workbench", 5.0)
	# Consumables.
	_add_item("berries", {"name": "Berries", "kind": "food", "food": 12.0, "stack": 20, "value": 2})
	_add_item("canned_food", {"name": "Canned Food", "kind": "food", "food": 42.0, "stack": 10, "value": 12})
	_add_item("water_bottle", {"name": "Water Bottle", "kind": "drink", "drink": 45.0, "stack": 10, "value": 8})
	_add_item("bandage", {"name": "Bandage", "kind": "medical", "heal": 28.0, "stack": 10, "value": 10})
	_add_recipe("bandage", "bandage", 2, {"cloth_1": 2}, "", 2.0)
	# Days After loot: only found while scavenging ruins.
	_add_item("pistol", {"name": "Pistol", "kind": "weapon", "weapon": "ranged", "tier": 3, "damage": 22.0, "cooldown": 0.45, "ammo": "ammo_9mm", "value": 150})
	_add_item("ammo_9mm", {"name": "9mm Ammo", "kind": "ammo", "stack": 60, "value": 2})
	_add_item("scrap", {"name": "Scrap Metal", "kind": "resource", "tier": 2, "stack": 100, "value": 3})
	_add_item("silver", {"name": "Silver", "kind": "currency", "stack": 100000, "value": 1})


static func tool_tier_for_node(kind: String) -> String:
	# Which tool gathers which node type.
	match kind:
		"tree":
			return "axe"
		"rock", "ore":
			return "pickaxe"
		_:
			return ""


static func node_info(kind: String) -> Dictionary:
	match kind:
		"tree":
			return {"yield": "wood", "amount": 4, "seconds": 3.0, "respawn": 120.0, "radius": 0.5, "blocks": true}
		"rock":
			return {"yield": "stone", "amount": 4, "seconds": 3.5, "respawn": 150.0, "radius": 0.8, "blocks": true}
		"ore":
			return {"yield": "ore", "amount": 3, "seconds": 4.5, "respawn": 200.0, "radius": 0.7, "blocks": true}
		"bush":
			return {"yield": "fiber", "amount": 3, "seconds": 1.6, "respawn": 90.0, "radius": 0.4, "blocks": false}
		"berry":
			return {"yield": "berries", "amount": 3, "seconds": 1.2, "respawn": 90.0, "radius": 0.4, "blocks": false}
	return {}
