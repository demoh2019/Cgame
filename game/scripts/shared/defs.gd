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
const MAX_TIER := 8 # T1-T3 in green/yellow/red, T4-T8 deeper and deeper into the black zone.
const CAMP_FISH_STEW := "camp_fish_stew" # Clean fish-and-water camp meal.

# --- Player tuning -------------------------------------------------------------------------------
const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.6
const PLAYER_RADIUS := 0.45
const REACH := 2.6 # Gathering / looting distance.
const MELEE_RANGE := 2.2
const PISTOL_RANGE := 40.0
const MAX_HEALTH := 100.0
const INFECTION_MAX := 100.0
const INFECTION_GROWTH_PER_SECOND := 0.065
const INFECTION_DAMAGE_START := 30.0
const INFECTION_DAMAGE_PER_SECOND := 1.4
const ZOMBIE_INFECTION_PER_HIT := {"walker": 8.0, "runner": 12.0, "brute": 20.0, "spitter": 10.0,
	"stalker": 12.0, "sentinel": 14.0, "howler": 6.0, "crawler": 5.0}
# Persistent wounds: real attacks cause bleeding; untreated bleeding slowly clots but costs HP.
const BLEEDING_MAX := 100.0
const BLEEDING_DAMAGE_PER_SECOND := 1.2
const BLEEDING_DECAY_PER_SECOND := 0.2
const ZOMBIE_BLEEDING_PER_HIT := {"walker": 9.0, "runner": 13.0, "brute": 22.0, "spitter": 3.0,
	"stalker": 15.0, "sentinel": 16.0, "howler": 4.0, "crawler": 7.0}
const PVP_MELEE_BLEEDING_PER_HIT := 12.0
# Brute trauma is a persistent injury instead of extra raw damage.
const FRACTURE_MAX := 100.0
const FRACTURE_DECAY_PER_SECOND := 0.04
const FRACTURE_SPEED_FACTOR := 0.65
const ZOMBIE_FRACTURE_PER_HIT := {"brute": 35.0, "sentinel": 18.0}
const COMBAT_ENERGY_MAX := 100.0
const COMBAT_ENERGY_REGEN := 9.0
# Sprint exhaustion is a server-owned survival mechanic.
const MAX_STAMINA := 100.0
const SPRINT_STAMINA_PER_SECOND := 18.0
const STAMINA_REGEN_PER_SECOND := 11.0
const STAMINA_RECOVERY_DELAY := 0.8
const HUNGER_PER_SECOND := 0.045
const THIRST_PER_SECOND := 0.07
const STARVE_DAMAGE_PER_SECOND := 1.2
# Survival stealth: noise is determined by authoritative movement and fired ammo.
const SPRINT_NOISE_RADIUS := 21.0
const SPRINT_NOISE_SECONDS := 0.8
const GUNSHOT_NOISE_RADIUS := 32.0
const GUNSHOT_NOISE_SECONDS := 3.0
const INVENTORY_SLOTS := 24
# Soft-load encumbrance: past the comfortable weight, walking slows and sprint is disabled.
# No hard pickup cap: existing saves, market trades and full-loot bags remain compatible.
const CARRY_COMFORT_KG := 35.0
const CARRY_HEAVY_KG := 90.0
const CARRY_MIN_SPEED_FACTOR := 0.5
const ITEM_KIND_WEIGHT := {
	"resource": 1.25, "material": 0.8, "tool": 2.5, "weapon": 3.0,
	"armor": 4.0, "food": 0.4, "drink": 0.7, "medical": 0.2,
	"ammo": 0.05, "currency": 0.0,
	"head": 1.0, "cape": 1.2, "hands": 0.5, "feet": 1.2,
}
const STASH_SLOTS := 48 # Account-bound safe-settlement storage; never dropped on death.
const RESPAWN_SECONDS := 4.0
# Craftable, temporary field insulation against fictional weather hazards.
const THERMAL_WRAP_SECONDS := 180.0
const THERMAL_WRAP_REDUCTION := 0.70

# --- Zombies ---------------------------------------------------------------------------------------
const ZOMBIES := {
	# behavior: "roamer" (default) drifts and chases within its leash; "hunter" keeps chasing while it can see
	# you and searches your last position before giving up; "territorial" defends `territory` metres around
	# its home and never follows you out of it.
	"walker": {"health": 45.0, "speed": 1.7, "damage": 9.0, "attack_range": 1.6, "attack_cooldown": 1.3, "notice": 16.0, "lose": 34.0, "xp": 5},
	"runner": {"health": 28.0, "speed": 4.4, "damage": 7.0, "attack_range": 1.6, "attack_cooldown": 0.9, "notice": 24.0, "lose": 40.0, "xp": 8,
		"behavior": "hunter"},
	"brute": {"health": 170.0, "speed": 2.2, "damage": 26.0, "attack_range": 2.0, "attack_cooldown": 1.8, "notice": 14.0, "lose": 30.0, "xp": 25,
		"behavior": "territorial", "territory": 16.0},
	# Relentless tracker: follows a survivor it can see far beyond other infected.
	"stalker": {"health": 62.0, "speed": 3.9, "damage": 13.0, "attack_range": 1.6, "attack_cooldown": 1.0, "notice": 28.0, "lose": 90.0, "xp": 16,
		"behavior": "hunter"},
	# Armoured guardian of ruins and camps: punishing inside its ground, harmless if you leave it.
	"sentinel": {"health": 150.0, "speed": 3.0, "damage": 18.0, "attack_range": 1.8, "attack_cooldown": 1.4, "notice": 24.0, "lose": 32.0, "xp": 22,
		"behavior": "territorial", "territory": 20.0},
	# Weak screamer: its howl wakes every infected nearby.
	"howler": {"health": 40.0, "speed": 2.4, "damage": 6.0, "attack_range": 1.6, "attack_cooldown": 1.2, "notice": 26.0, "lose": 36.0, "xp": 12,
		"behavior": "territorial", "territory": 24.0, "howl_radius": 42.0},
	# Small, fast swarm infected that come in packs.
	"crawler": {"health": 18.0, "speed": 3.3, "damage": 5.0, "attack_range": 1.4, "attack_cooldown": 0.75, "notice": 13.0, "lose": 28.0, "xp": 3},
	"spitter": {"health": 52.0, "speed": 2.0, "damage": 14.0, "attack_range": 1.6, "attack_cooldown": 2.0, "notice": 21.0, "lose": 36.0, "xp": 12},
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
	if id.contains("+"):
		return _quality_item(id)
	return items().get(id, {})


static func is_item(id: String) -> bool:
	if id.contains("+"):
		return not _quality_item(id).is_empty()
	return items().has(id)


# --- Item quality: crafted gear rolls Normal..Masterpiece; id "club_5+3" = Club T5, quality 3. ---
const QUALITY_NAMES := ["", "Normal", "Good", "Outstanding", "Excellent", "Masterpiece"]
const MAX_QUALITY := 5
const QUALITY_KINDS := ["weapon", "armor", "tool"]
static var _quality_cache: Dictionary = {}


static func base_id(id: String) -> String:
	var at: int = id.find("+")
	return id if at < 0 else id.substr(0, at)


static func quality_of(id: String) -> int:
	var at: int = id.find("+")
	if at < 0:
		return 1
	var q: String = id.substr(at + 1)
	return int(q) if q.is_valid_int() else 0


static func with_quality(id: String, quality: int) -> String:
	return base_id(id) if quality <= 1 else "%s+%d" % [base_id(id), mini(quality, MAX_QUALITY)]


static func can_have_quality(id: String) -> bool:
	return str(items().get(base_id(id), {}).get("kind", "")) in QUALITY_KINDS


static func _quality_item(id: String) -> Dictionary:
	if _quality_cache.has(id):
		return _quality_cache[id]
	var q: int = quality_of(id)
	var base: Dictionary = items().get(base_id(id), {})
	if q < 2 or q > MAX_QUALITY or base.is_empty() or not str(base.get("kind", "")) in QUALITY_KINDS \
			or id != with_quality(id, q):
		return {}
	var data: Dictionary = base.duplicate(true)
	var bonus: float = 1.0 + 0.08 * float(q - 1)
	for key in ["damage", "armor"]:
		if data.has(key):
			data[key] = float(data[key]) * bonus
	data["value"] = int(round(float(data.get("value", 1)) * (1.0 + 0.6 * float(q - 1))))
	data["quality"] = q
	data["name"] = "%s (%s)" % [str(data.get("name", id)), QUALITY_NAMES[q]]
	_quality_cache[id] = data
	return data


## Crafting quality roll: skill and luck push toward Masterpiece. Returns 1..5.
static func roll_quality(rng: RandomNumberGenerator, skill_bonus: float = 0.0) -> int:
	var r: float = rng.randf() / (1.0 + maxf(0.0, skill_bonus))
	if r < 0.006:
		return 5
	if r < 0.035:
		return 4
	if r < 0.12:
		return 3
	if r < 0.36:
		return 2
	return 1


static func stack_size(id: String) -> int:
	return int(item(id).get("stack", 1))


static func item_weight(id: String) -> float:
	return float(item(id).get("weight", 0.0))


static func carry_speed_factor(weight_kg: float) -> float:
	# Saturated soft penalty. The server derives weight from its own inventory.
	if not is_finite(weight_kg):
		return CARRY_MIN_SPEED_FACTOR
	if weight_kg <= CARRY_COMFORT_KG:
		return 1.0
	var fraction := clampf((weight_kg - CARRY_COMFORT_KG) / (CARRY_HEAVY_KG - CARRY_COMFORT_KG), 0.0, 1.0)
	return lerpf(1.0, CARRY_MIN_SPEED_FACTOR, fraction)


static func tier_of(id: String) -> int:
	return int(item(id).get("tier", 0))


## Resource tier at a distance from the hub: the black zone keeps getting richer outward.
const BLACK_TIER_STEP := 450.0
static func tier_for_distance(distance: float) -> int:
	var zone: int = zone_index_for_distance(distance)
	if zone < ZONE_RADII.size():
		return zone + 1
	return clampi(4 + int((distance - float(ZONE_RADII[-1])) / BLACK_TIER_STEP), 4, MAX_TIER)


static func zone_index_for_distance(distance: float) -> int:
	for i in ZONE_RADII.size():
		if distance < ZONE_RADII[i]:
			return i
	return ZONE_RADII.size()


static func _add_item(id: String, data: Dictionary) -> void:
	data["id"] = id
	if not data.has("stack"):
		data["stack"] = 1
	if not data.has("weight"):
		var kind: String = str(data.get("kind", ""))
		var weight: float = float(ITEM_KIND_WEIGHT.get(kind, 1.0))
		if id.begins_with("stone_") or id.begins_with("ore_"):
			weight = 2.0
		elif id.begins_with("fiber_"):
			weight = 0.35
		elif id == "scrap":
			weight = 1.5
		data["weight"] = weight
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
		# Craftable reach weapon across all existing gathering/crafting tiers.
		var spear_inputs: Dictionary = {
			"plank_%d" % t: 2, "bar_%d" % t: 1, "fiber_%d" % t: 2}
		_add_item("spear_%d" % t, {"name": "Survival Spear T%d" % t,
			"kind": "weapon", "weapon": "melee", "tier": t,
			"damage": 12.0 + 8.0 * (t - 1), "cooldown": 0.86,
			"reach": 3.5, "weight": 3.6, "value": 54 * t})
		_add_recipe("spear_%d" % t, "spear_%d" % t, 1,
			spear_inputs, "workbench", 6.0)
		# Salvaged steel and tiered metalwork create a short-range sweeper:
		# unlike a spear's narrow pierce, its skill can strike a small melee arc.
		_add_item("machete_%d" % t, {"name": "Ruin Machete T%d" % t,
			"kind": "weapon", "weapon": "melee", "tier": t,
			"damage": 13.0 + 8.0 * (t - 1), "cooldown": 0.8,
			"weight": 2.8 + 0.2 * t, "value": 50 * t})
		_add_recipe("machete_%d" % t, "machete_%d" % t, 1,
			{"plank_%d" % t: 2, "bar_%d" % t: 2, "scrap": 1},
			"workbench", 6.0)
		# Armor sundering creates a support role for raid damage dealers.
		# The debuff is applied only after a confirmed infected melee hit.
		_add_item("sunder_axe_%d" % t, {"name": "Ruin Sunder Axe T%d" % t,
			"kind": "weapon", "weapon": "melee", "tier": t,
			"damage": 15.0 + 9.0 * float(t - 1), "cooldown": 0.94,
			"weight": 4.0 + 0.25 * float(t), "value": 61 * t})
		_add_recipe("sunder_axe_%d" % t, "sunder_axe_%d" % t, 1,
			{"bar_%d" % t: 3, "plank_%d" % t: 1,
				"fiber_%d" % t: 2, "scrap": 1},
			"workbench", 6.5)
		# Swift scavenger blades give a fragile melee combatant a paid
		# precision finisher against an already wounded infected.
		_add_item("dagger_%d" % t, {"name": "Ruin Dagger T%d" % t,
			"kind": "weapon", "weapon": "melee", "tier": t,
			"damage": 11.0 + 6.0 * float(t - 1), "cooldown": 0.55,
			"weight": 1.5 + 0.15 * float(t), "value": 49 * t})
		_add_recipe("dagger_%d" % t, "dagger_%d" % t, 1,
			{"bar_%d" % t: 2, "plank_%d" % t: 1,
				"cloth_%d" % t: 1, "scrap": 1},
			"workbench", 5.0)
		# Weighted metal head: slower than a club, but its equipment-granted
		# blow can briefly stagger living infected (never raid bosses).
		_add_item("sledgehammer_%d" % t, {"name": "Salvage Sledgehammer T%d" % t,
			"kind": "weapon", "weapon": "melee", "tier": t,
			"damage": 16.0 + 10.0 * (t - 1), "cooldown": 1.1,
			"weight": 5.0 + 0.35 * t, "value": 67 * t})
		_add_recipe("sledgehammer_%d" % t, "sledgehammer_%d" % t, 1,
			{"plank_%d" % t: 1, "bar_%d" % t: 3, "scrap": 2},
			"workbench", 7.0)
		# Classless field medicine: a low-damage weapon that supports nearby
		# party allies through an energy-limited restorative ability.
		_add_item("restoration_staff_%d" % t, {
			"name": "Expedition Restoration Staff T%d" % t,
			"kind": "weapon", "weapon": "melee", "tier": t,
			"damage": 5.0 + 3.0 * float(t - 1), "cooldown": 1.0,
			"weight": 2.0 + 0.2 * t, "value": 62 * t})
		_add_recipe("restoration_staff_%d" % t,
			"restoration_staff_%d" % t, 1,
			{"plank_%d" % t: 2, "cloth_%d" % t: 2,
				"bar_%d" % t: 1, "field_antiseptic": 1},
			"workbench", 7.0)
		# Lightweight classless archery: affordable arrows, limited distance and noise.
		_add_item("bow_%d" % t, {"name": "Survival Bow T%d" % t,
			"kind": "weapon", "weapon": "ranged", "tier": t,
			"damage": 10.0 + 7.0 * (t - 1), "cooldown": 1.05,
			"range": 27.0, "ammo": "arrow",
			"shot_noise_radius": 9.0, "shot_noise_seconds": 0.8,
			"weight": 2.2, "value": 38 * t})
		_add_recipe("bow_%d" % t, "bow_%d" % t, 1,
			{"plank_%d" % t: 2, "fiber_%d" % t: 2,
				"cloth_%d" % t: 1}, "workbench", 5.0)
		# Mechanical crossbows trade fire rate and noise for powerful bolts.
		# Their equipped skill pins infected in place, never PvP players.
		_add_item("crossbow_%d" % t, {"name": "Salvage Crossbow T%d" % t,
			"kind": "weapon", "weapon": "ranged", "tier": t,
			"damage": 18.0 + 10.0 * float(t - 1), "cooldown": 1.55,
			"range": 25.0, "ammo": "arrow",
			"shot_noise_radius": 12.0, "shot_noise_seconds": 1.0,
			"weight": 3.6 + 0.2 * float(t), "value": 60 * t})
		_add_recipe("crossbow_%d" % t, "crossbow_%d" % t, 1,
			{"plank_%d" % t: 2, "bar_%d" % t: 2,
				"fiber_%d" % t: 2, "scrap": 1},
			"workbench", 7.0)
		# Armour: reduces incoming damage.
		_add_item("jacket_%d" % t, {"name": "Jacket T%d" % t, "kind": "armor", "tier": t, "armor": 0.08 + 0.07 * (t - 1), "value": 35 * t})
		_add_recipe("jacket_%d" % t, "jacket_%d" % t, 1, {"cloth_%d" % t: 4}, "workbench", 5.0)
		# Worn pieces for the other gear slots: each adds a little protection on top of the body armor.
		_add_item("hood_%d" % t, {"name": "Survivor Hood T%d" % t, "kind": "head", "tier": t, "armor": 0.03 + 0.02 * (t - 1), "value": 18 * t})
		_add_recipe("hood_%d" % t, "hood_%d" % t, 1, {"cloth_%d" % t: 2}, "workbench", 4.0)
		_add_item("cloak_%d" % t, {"name": "Travel Cloak T%d" % t, "kind": "cape", "tier": t, "armor": 0.02 + 0.015 * (t - 1), "value": 20 * t})
		_add_recipe("cloak_%d" % t, "cloak_%d" % t, 1, {"cloth_%d" % t: 3}, "workbench", 4.0)
		_add_item("gloves_%d" % t, {"name": "Work Gloves T%d" % t, "kind": "hands", "tier": t, "armor": 0.02 + 0.015 * (t - 1), "value": 16 * t})
		_add_recipe("gloves_%d" % t, "gloves_%d" % t, 1, {"cloth_%d" % t: 1, "bar_%d" % t: 1}, "workbench", 4.0)
		_add_item("boots_%d" % t, {"name": "Trail Boots T%d" % t, "kind": "feet", "tier": t, "armor": 0.03 + 0.02 * (t - 1), "value": 20 * t})
		_add_recipe("boots_%d" % t, "boots_%d" % t, 1, {"cloth_%d" % t: 2, "bar_%d" % t: 1}, "workbench", 4.0)
		# Environmental armor for expedition gatherers: better insulation than
		# combat jackets, but weaker against attacks of the same tier.
		if t >= 2:
			var storm_id: String = "storm_coat_%d" % t
			var cold_protection: float = 0.55 if t == 2 else (0.67 if t == 3 else 0.78)
			_add_item(storm_id, {"name": "Expedition Stormcoat T%d" % t,
				"kind": "armor", "tier": t, "armor": 0.05 + 0.07 * float(t - 1),
				"insulation": cold_protection, "weight": 3.4 + 0.3 * float(t),
				"value": 48 * t})
			_add_recipe(storm_id, storm_id, 1,
				{"cloth_%d" % t: 6, "fiber_%d" % t: 4},
				"workbench", 6.0 + float(t))
			# The sealed suit trades PvP armor and warmth for environmental protection.
			var sealed_id: String = "sealed_suit_%d" % t
			var spore_resistance: float = minf(0.95, 0.65 + 0.1 * float(t - 2))
			_add_item(sealed_id, {"name": "Sealed Expedition Suit T%d" % t,
				"kind": "armor", "tier": t, "armor": 0.04 + 0.015 * float(t - 2),
				"spore_resistance": spore_resistance, "insulation": 0.25,
				"weight": 4.0 + 0.4 * float(t - 2), "value": 68 * t})
			_add_recipe(sealed_id, sealed_id, 1,
				{"cloth_%d" % t: 5, "bar_%d" % t: 2,
					"fiber_%d" % t: 3}, "workbench", 6.0 + float(t))
			# Lightweight stealth clothing: weak in combat but breaks visual
			# acquisition by idle infected. Noise and blood scent are unchanged.
			var ghillie_id: String = "ghillie_cloak_%d" % t
			var sight_factor: float = 0.62 if t == 2 else (0.55 if t == 3 else 0.48)
			_add_item(ghillie_id, {"name": "Ghillie Cloak T%d" % t,
				"kind": "armor", "tier": t, "armor": 0.045 + 0.025 * float(t - 2),
				"visual_signature": sight_factor, "weight": 2.2 + 0.15 * float(t),
				"value": 65 * t})
			_add_recipe(ghillie_id, ghillie_id, 1,
				{"cloth_%d" % t: 4, "fiber_%d" % t: 6,
				"plank_%d" % t: 1}, "workbench", 6.0 + float(t))
	# Consumables.
	# Shore fishing: scavenging food supports the classless artisan loop.
	_add_item("fishing_rod", {"name": "Fishing Rod", "kind": "tool", "tool": "fishing",
		"tier": 1, "value": 24, "weight": 1.2})
	_add_recipe("fishing_rod", "fishing_rod", 1, {"plank_1": 2, "fiber_1": 3},
		"workbench", 4.0)
	# Optional bait increases fish count, never the region/rod/skill tier.
	_add_item("shore_fish_trap", {"name": "Shore Fish Trap",
		"kind": "deployable", "tier": 1, "stack": 5, "weight": 1.5, "value": 35})
	_add_recipe("shore_fish_trap", "shore_fish_trap", 1,
		{"plank_1": 2, "fiber_1": 3, "scrap": 1}, "workbench", 4.0)
	_add_item("shore_bait", {"name": "Shore Fishing Bait", "kind": "material",
		"stack": 20, "weight": 0.1, "value": 4})
	_add_recipe("shore_bait", "shore_bait", 2,
		{"berries": 2, "fiber_1": 1}, "", 1.5)
	_add_item("raw_fish", {"name": "Raw Fish", "kind": "resource", "tier": 1,
		"stack": 20, "value": 5, "weight": 0.7, "unsafe_food": true})
	_add_item("cooked_fish", {"name": "Cooked Fish", "kind": "food", "food": 35.0,
		"stack": 10, "value": 13, "weight": 0.5})
	_add_recipe("cooked_fish", "cooked_fish", 1, {"raw_fish": 1, "wood_1": 1},
		"campfire", 3.0)
	# Smoked trail rations cost more fuel plus fiber wrapping. Real campfires
	# and the hub workbench use the existing atomic crafting transaction.
	_add_item("smoked_fish", {"name": "Smoked Trail Fish T1", "kind": "food",
		"tier": 1, "food": 26.0, "stack": 10, "value": 22, "weight": 0.45})
	_add_recipe("smoked_fish", "smoked_fish", 1,
		{"raw_fish": 1, "wood_1": 2, "fiber_1": 1}, "campfire", 5.0)
	# T2-T4 coastal professions: stronger rods and valuable fish require
	# matching crafting/gathering mastery and higher-risk shorelines.
	for tier in range(2, MAX_TIER + 1):
		_add_item("fishing_rod_%d" % tier, {
			"name": "Fishing Rod T%d" % tier, "kind": "tool", "tool": "fishing",
			"tier": tier, "value": 24 * tier, "weight": 1.0 + 0.2 * tier,
		})
		_add_recipe("fishing_rod_%d" % tier, "fishing_rod_%d" % tier, 1,
			{"plank_%d" % tier: 2, "cloth_%d" % tier: 2, "bar_%d" % tier: 1},
			"workbench", 3.0 + float(tier))
		_add_item("raw_fish_%d" % tier, {
			"name": "Raw Coastal Fish T%d" % tier, "kind": "resource",
			"tier": tier, "stack": 20, "value": 5 * tier, "weight": 0.7 + 0.15 * tier,
			"unsafe_food": true,
		})
		_add_item("cooked_fish_%d" % tier, {
			"name": "Cooked Coastal Fish T%d" % tier, "kind": "food",
			"tier": tier, "food": 25.0 + 10.0 * tier, "stack": 10,
			"value": 13 * tier, "weight": 0.5 + 0.1 * tier,
		})
		_add_recipe("cooked_fish_%d" % tier, "cooked_fish_%d" % tier, 1,
			{"raw_fish_%d" % tier: 1, "wood_%d" % tier: 1},
			"campfire", 2.0 + float(tier))
		_add_item("smoked_fish_%d" % tier, {
			"name": "Smoked Trail Fish T%d" % tier, "kind": "food",
			"tier": tier, "food": 18.0 + 8.0 * float(tier), "stack": 10,
			"value": 22 * tier, "weight": 0.45 + 0.05 * float(tier),
		})
		_add_recipe("smoked_fish_%d" % tier, "smoked_fish_%d" % tier, 1,
			{"raw_fish_%d" % tier: 1, "wood_%d" % tier: 2, "fiber_1": 1},
			"campfire", 4.0 + float(tier))

	# No permanent class or spell: craft and carry insulation for expeditions.
	_add_item("thermal_wrap", {"name": "Emergency Heat Pack", "kind": "thermal",
		"stack": 5, "weight": 0.5, "value": 22, "warmth": THERMAL_WRAP_SECONDS})
	_add_recipe("thermal_wrap", "thermal_wrap", 1,
		{"cloth_1": 1, "fiber_1": 2, "wood_1": 1}, "", 2.5)
	# Craftable melee preparation uses existing Cgame script APIs.
	# Reinforced survival armor for three confirmed ordinary infected melee strikes.
	_add_item("field_armor_plate", {"name": "Field Armor Plate", "kind": "armor_plate",
		"tier": 1, "stack": 5, "weight": 1.1, "value": 38})
	_add_recipe("field_armor_plate", "field_armor_plate", 1,
		{"bar_1": 1, "cloth_1": 2, "scrap": 2}, "workbench", 4.0)
	# Classless ranged preparation, bound to one owned equipped weapon.
	_add_item("field_sighting_kit", {"name": "Salvaged Sighting Kit", "kind": "sighting_kit",
		"tier": 1, "stack": 5, "weight": 0.65, "value": 32})
	_add_recipe("field_sighting_kit", "field_sighting_kit", 1,
		{"bar_1": 1, "fiber_1": 2, "scrap": 2}, "workbench", 4.0)
	_add_item("field_whetstone", {"name": "Salvaged Whetstone", "kind": "whetstone",
		"tier": 1, "stack": 10, "weight": 0.35, "value": 18})
	_add_recipe("field_whetstone", "field_whetstone", 1,
		{"stone_1": 2, "scrap": 1}, "workbench", 3.0)
	# Paid scout preparation: one crafted scan reveals a living elite or
	# raid boss farther away than the normal 90m replication radius.
	_add_item("field_threat_scanner", {"name": "Salvaged Threat Scanner",
		"kind": "threat_scanner", "tier": 2, "stack": 5,
		"weight": 0.6, "value": 42})
	_add_recipe("field_threat_scanner", "field_threat_scanner", 1,
		{"scrap": 3, "bar_2": 1, "charcoal_filter": 1}, "workbench", 5.0)
	# One-use wilderness prospecting; points at a live high-tier ore/rock node.
	_add_item("prospecting_chart", {"name": "Geological Prospecting Chart",
		"kind": "prospecting_chart", "tier": 1, "stack": 10,
		"weight": 0.2, "value": 28})
	_add_recipe("prospecting_chart", "prospecting_chart", 1,
		{"cloth_1": 1, "scrap": 2, "stone_1": 1}, "", 3.0)
	# A real chart can reveal a rare deposit to authenticated party members.
	_add_item("surveyor_signal", {"name": "Cooperative Mineral Signal",
		"kind": "survey_signal", "tier": 1, "stack": 10,
		"weight": 0.3, "value": 29})
	_add_recipe("surveyor_signal", "surveyor_signal", 1,
		{"scrap": 2, "cloth_1": 1, "charcoal_filter": 1}, "", 3.0)
	# Mining specialisation: three paid T2+ ore/rock bonuses, but louder work.
	_add_item("mining_wedges", {"name": "Reinforced Mining Wedges",
		"kind": "mining_wedges", "tier": 2, "stack": 5,
		"weight": 0.9, "value": 72})
	_add_recipe("mining_wedges", "mining_wedges", 1,
		{"bar_2": 1, "scrap": 3, "stone_1": 2}, "workbench", 5.0)
	_add_item("berries", {"name": "Berries", "kind": "food", "food": 12.0, "stack": 20, "value": 2})
	_add_item("canned_food", {"name": "Canned Food", "kind": "food", "food": 42.0, "stack": 10, "value": 12})
	_add_item("water_bottle", {"name": "Water Bottle", "kind": "drink", "drink": 45.0, "stack": 10, "value": 8})
	# A hot expedition meal trades a clean bottle and fish for both nourishment
	# and hydration in one backpack item. No raw or infected water is accepted.
	_add_item(CAMP_FISH_STEW, {"name": "Camp Fish Stew", "kind": "food",
		"tier": 1, "food": 40.0, "drink": 38.0, "stack": 10,
		"weight": 0.85, "value": 25})
	_add_recipe(CAMP_FISH_STEW, CAMP_FISH_STEW, 1,
		{"raw_fish": 1, "water_bottle": 1, "wood_1": 1}, "campfire", 4.0)

	# Unsafe lake water is a physical item, never a drink. Craft a pouch in the
	# field, fill it at a real shore, then boil it at a live campfire or workbench.
	_add_item("empty_water_pouch", {"name": "Empty Water Pouch", "kind": "water_pouch",
		"tier": 1, "stack": 10, "weight": 0.15, "value": 4})
	_add_recipe("empty_water_pouch", "empty_water_pouch", 1,
		{"cloth_1": 1, "fiber_1": 1}, "", 2.0)
	_add_item("murky_water", {"name": "Unboiled Lake Water", "kind": "raw_water",
		"tier": 1, "stack": 10, "weight": 0.8, "value": 1})
	_add_recipe("boiled_water", "water_bottle", 1,
		{"murky_water": 1, "wood_1": 1}, "campfire", 4.0)
	# Workbench-made storm shock lining: a paid alternative to dodging bolts.
	_add_item("storm_insulator", {"name": "Copper Storm Insulation Kit",
		"kind": "storm_insulator", "tier": 2, "stack": 5, "weight": 0.7, "value": 55})
	_add_recipe("storm_insulator", "storm_insulator", 1,
		{"bar_2": 1, "cloth_2": 2, "scrap": 2}, "workbench", 5.0)
	# Durable camp craft: owners may anchor one live field tarp once, never a permanent base.
	# Shared field-fire survival: paid storm-resistant fuel, without permanent heating.
	_add_item("camp_alarm_kit", {"name": "Camp Sentry Alarm Kit",
		"kind": "material", "tier": 1, "stack": 5, "weight": 0.65, "value": 32})
	_add_recipe("camp_alarm_kit", "camp_alarm_kit", 1,
		{"wood_1": 1, "fiber_1": 2, "scrap": 2}, "", 3.0)
	_add_item("stormproof_briquette", {"name": "Stormproof Ember Briquette",
		"kind": "fire_briquette", "tier": 1, "stack": 5, "weight": 0.65, "value": 29})
	_add_recipe("stormproof_briquette", "stormproof_briquette", 1,
		{"wood_1": 3, "fiber_1": 2, "scrap": 1}, "", 3.0)
	_add_item("storm_tarp_anchors", {"name": "Storm Tarp Anchor Kit",
		"kind": "tarp_anchor", "tier": 2, "stack": 5, "weight": 1.2, "value": 65})
	_add_recipe("storm_tarp_anchors", "storm_tarp_anchors", 1,
		{"bar_2": 1, "fiber_2": 2, "cloth_2": 2}, "workbench", 5.0)
	# Automatically consumes one filter when drinking directly from a lake.
	_add_item("rain_tarp", {"name": "Expedition Rain Catcher", "kind": "rain_catcher",
		"stack": 5, "weight": 1.1, "value": 24})
	_add_recipe("rain_tarp", "rain_tarp", 1,
		{"cloth_1": 2, "fiber_1": 2, "plank_1": 1}, "", 3.0)
	_add_item("charcoal_filter", {"name": "Field Water Filter", "kind": "material",
		"stack": 10, "value": 14, "weight": 0.25})
	_add_recipe("charcoal_filter", "charcoal_filter", 1,
		{"cloth_1": 1, "wood_1": 1, "stone_1": 1}, "", 2.5)
	# One paid 120-second expedition filter against ambient swamp infection.
	# Does not mitigate bites, spitter acid, combat damage or PvP.
	_add_item("spore_filter", {"name": "Expedition Spore Filter",
		"kind": "spore_filter", "stack": 5, "weight": 0.35, "value": 35})
	_add_recipe("spore_filter", "spore_filter", 1,
		{"charcoal_filter": 1, "cloth_1": 2, "field_antiseptic": 1}, "", 3.0)
	# Permanent T1 expedition tool; each bottled-water refill still consumes
	# one carbon filter and a real timed stop at a natural shoreline.
	_add_item("field_canteen", {"name": "Reusable Field Canteen",
		"kind": "tool", "tool": "canteen", "tier": 1,
		"stack": 1, "weight": 0.75, "value": 26})
	_add_recipe("field_canteen", "field_canteen", 1,
		{"cloth_1": 2, "fiber_1": 3, "wood_1": 1}, "", 4.0)
	# Field-craftable salve hides only blood scent; no visual invisibility.
	# Field-crafted wraps quiet only footfalls while sprinting: not weapons, bikes or blood.
	_add_item("soft_sole_wraps", {"name": "Soft-Sole Trail Wraps", "kind": "footstep_wrap",
		"tier": 1, "stack": 5, "weight": 0.35, "value": 26})
	_add_recipe("soft_sole_wraps", "soft_sole_wraps", 1,
		{"cloth_1": 2, "fiber_1": 2, "scrap": 1}, "", 3.0)
	_add_item("herbal_scent_mask", {"name": "Herbal Scent Salve", "kind": "scent_mask",
		"stack": 5, "weight": 0.2, "value": 18})
	_add_recipe("herbal_scent_mask", "herbal_scent_mask", 1,
		{"fiber_1": 2, "cloth_1": 1, "water_bottle": 1}, "", 3.0)
	# Forest and swamp foraging yields tradeable medicinal plants. These are
	# rarer than ordinary fiber/berries and have no independent client action.
	_add_item("wild_herbs", {"name": "Wild Medicinal Herbs", "kind": "resource",
		"tier": 1, "stack": 20, "weight": 0.15, "value": 8})
	_add_item("herbal_poultice", {"name": "Field Herbal Poultice",
		"kind": "medical", "tier": 1, "heal": 10.0, "cure": 18.0,
		"stop_bleeding": true, "stack": 5, "weight": 0.30, "value": 30})
	_add_recipe("herbal_poultice", "herbal_poultice", 1,
		{"wild_herbs": 2, "cloth_1": 1, "water_bottle": 1}, "", 3.0)
	# Preparatory dressing against physical infected bites, not acid or spores.
	_add_item("wound_sealant", {"name": "Antiseptic Wound Sealant",
		"kind": "wound_seal", "tier": 1, "stack": 5, "weight": 0.25, "value": 38})
	_add_recipe("wound_sealant", "wound_sealant", 1,
		{"wild_herbs": 2, "field_antiseptic": 1, "cloth_1": 1}, "", 4.0)
	_add_item("field_splint", {"name": "Field Splint", "kind": "medical",
		"fracture_treatment": 100.0, "stack": 5, "value": 24, "weight": 0.6})
	_add_recipe("field_splint", "field_splint", 1,
		{"plank_1": 1, "fiber_1": 2, "cloth_1": 1}, "", 3.0)
	_add_item("bandage", {"name": "Bandage", "kind": "medical", "heal": 28.0, "stop_bleeding": true, "stack": 10, "value": 10})
	_add_recipe("bandage", "bandage", 2, {"cloth_1": 2}, "", 2.0)
	# Common crafted wound care and scarce medical loot from infected ruins.
	_add_item("field_antiseptic", {"name": "Field Antiseptic", "kind": "medical",
		"heal": 8.0, "cure": 40.0, "stop_bleeding": true, "stack": 5, "value": 20})
	_add_recipe("field_antiseptic", "field_antiseptic", 1,
		{"bandage": 1, "cloth_1": 1, "water_bottle": 1}, "", 3.0)
	# Raw fish offers desperate field calories but causes food poisoning.
	# This herbal tonic is the existing safe medicine/crafting counterplay.
	_add_item("herbal_gut_tonic", {"name": "Herbal Stomach Remedy", "kind": "medical",
		"tier": 1, "food_poison_treatment": 75.0, "stack": 5, "value": 38, "weight": 0.25})
	_add_recipe("herbal_gut_tonic", "herbal_gut_tonic", 1,
		{"wild_herbs": 2, "charcoal_filter": 1, "water_bottle": 1}, "", 3.0)
	# Tier-two expedition triage turns real wound supplies into one mixed-injury
	# treatment. Both self-use and party aid follow existing paid medical rules.
	_add_item("expedition_trauma_kit", {"name": "Expedition Trauma Kit",
		"kind": "medical", "tier": 2, "heal": 38.0, "cure": 15.0,
		"stop_bleeding": true, "fracture_treatment": 45.0,
		"stack": 5, "weight": 0.85, "value": 95})
	_add_recipe("expedition_trauma_kit", "expedition_trauma_kit", 1,
		{"bandage": 2, "field_splint": 1, "field_antiseptic": 1, "cloth_2": 2},
		"workbench", 6.0)
	# Dangerous swamps produce rare cultures for an infection medicine.
	_add_item("spore_sampler", {"name": "Sealed Spore Sample Kit", "kind": "sampler",
		"tier": 1, "stack": 5, "weight": 0.4, "value": 30})
	_add_recipe("spore_sampler", "spore_sampler", 1,
		{"cloth_1": 2, "bar_1": 1, "charcoal_filter": 1}, "workbench", 4.0)
	_add_item("spore_culture", {"name": "Hazardous Spore Culture", "kind": "resource",
		"tier": 2, "stack": 20, "weight": 0.2, "value": 30})
	# Prepared monster-hunting consumable: real swamp resources become
	# a brief, bounded melee boost; raid bosses and survivors stay immune.
	_add_item("antiseptic_edge_oil", {"name": "Antiseptic Edge Oil",
		"kind": "weapon_coating", "tier": 2, "stack": 10,
		"value": 65, "weight": 0.15})
	_add_recipe("antiseptic_edge_oil", "antiseptic_edge_oil", 1,
		{"spore_culture": 1, "field_antiseptic": 1, "scrap": 1},
		"workbench", 4.0)
	_add_item("spore_antidote", {"name": "Distilled Swamp Antidote",
		"kind": "medical", "tier": 2, "cure": 75.0, "stack": 5,
		"weight": 0.25, "value": 85})
	_add_recipe("spore_antidote", "spore_antidote", 1,
		{"spore_culture": 2, "bandage": 1, "water_bottle": 1}, "workbench", 6.0)
	# A single material-paid squad treatment; no free healing or item duplication.
	_add_item("field_triage_pack", {"name": "Expedition Triage Pack",
		"kind": "party_medical", "tier": 1, "stack": 5, "weight": 0.8, "value": 42})
	_add_recipe("field_triage_pack", "field_triage_pack", 1,
		{"bandage": 2, "field_antiseptic": 1, "cloth_1": 2, "water_bottle": 1},
		"workbench", 5.0)
	# Spitter counterplay: consumes real survival supplies instead of
	# granting immunity to the initial splash or healing past wounds.
	_add_item("field_alkali_kit", {"name": "Field Alkali Kit",
		"kind": "acid_neutralizer", "stack": 5, "weight": 0.5, "value": 32})
	_add_recipe("field_alkali_kit", "field_alkali_kit", 1,
		{"stone_1": 2, "water_bottle": 1, "cloth_1": 1}, "", 3.0)
	_add_item("antibiotics", {"name": "Antibiotics", "kind": "medical",
		"cure": 100.0, "stack": 5, "value": 80})
	# Lineage-style elite hunts feed back into survival via medical crafting.
	_add_item("infected_core", {"name": "Infected Core", "kind": "resource",
		"tier": 3, "stack": 20, "value": 48, "weight": 0.4})
	_add_item("purified_serum", {"name": "Purified Survivor Serum", "kind": "medical",
		"tier": 3, "heal": 16.0, "cure": 65.0, "stack": 5,
		"value": 110, "weight": 0.2})
	_add_recipe("purified_serum", "purified_serum", 1,
		{"infected_core": 2, "bandage": 1, "water_bottle": 1},
		"workbench", 6.0)
	# A single-use expedition stimulant: elite trophy + field medicine.
	_add_item("frontier_stim", {"name": "Frontier Adrenaline Shot",
		"kind": "stimulant", "tier": 3, "stack": 5, "value": 95, "weight": 0.25})
	_add_recipe("frontier_stim", "frontier_stim", 1,
		{"infected_core": 1, "field_antiseptic": 1, "water_bottle": 1},
		"workbench", 5.0)
	# Rare raid equipment: no loot-table bypass. Earn cores through real elite
	# infected and raid kills, then craft it with tier 3 artisan mastery.
	_add_item("purifier_maul_3", {"name": "Purifier Maul T3", "kind": "weapon",
		"weapon": "melee", "tier": 3, "damage": 32.0, "cooldown": 0.78,
		"infected_bonus": 0.25, "weight": 4.8, "value": 260})
	_add_recipe("purifier_maul_3", "purifier_maul_3", 1,
		{"infected_core": 4, "bar_3": 3, "plank_3": 2, "cloth_3": 1},
		"workbench", 9.0)
	# Specialized expedition protection forged from genuine elite trophies.
	# The ordinary T3 jacket has the same base armor; this one mitigates only
	# secondary wounds inflicted by infected, never bleeding from PvP.
	_add_item("warden_jacket_3", {"name": "Infected Warden Jacket T3",
		"kind": "armor", "tier": 3, "armor": 0.22,
		"infection_resistance": 0.4, "bleeding_resistance": 0.3,
		"weight": 4.5, "value": 220})
	_add_recipe("warden_jacket_3", "warden_jacket_3", 1,
		{"infected_core": 3, "cloth_3": 4, "bar_3": 1},
		"workbench", 8.0)
	# Days After loot: only found while scavenging ruins.
	_add_item("pistol", {"name": "Pistol", "kind": "weapon", "weapon": "ranged", "tier": 3, "damage": 22.0, "cooldown": 0.45, "ammo": "ammo_9mm", "value": 150})
	# Rebuild one scavenged pistol into a quieter but weaker exploration weapon.
	# Reduced sound is server-owned and fed into existing infected hearing logic.
	_add_item("suppressed_pistol", {"name": "Improvised Suppressed Pistol",
		"kind": "weapon", "weapon": "ranged", "tier": 3,
		"damage": 18.0, "cooldown": 0.7, "range": 32.0,
		"ammo": "ammo_9mm", "shot_noise_radius": 12.0,
		"shot_noise_seconds": 1.1, "weight": 3.3, "value": 260})
	_add_recipe("suppressed_pistol", "suppressed_pistol", 1,
		{"pistol": 1, "bar_3": 2, "cloth_3": 2, "scrap": 6},
		"workbench", 10.0)
	# Ranged fighting can be sustained through scavenging and T2 metalworking.
	# Recipes use the existing authoritative bench and crafting mastery rules.
	_add_item("arrow", {"name": "Wooden Arrows", "kind": "ammo",
		"tier": 1, "stack": 80, "value": 1, "weight": 0.06})
	_add_recipe("arrow", "arrow", 16, {"wood_1": 2, "fiber_1": 2}, "", 2.5)
	_add_item("ammo_9mm", {"name": "9mm Ammo", "kind": "ammo",
		"tier": 2, "stack": 60, "value": 2})
	_add_recipe("ammo_9mm", "ammo_9mm", 12,
		{"scrap": 2, "bar_2": 1}, "workbench", 4.0)
	_add_item("scrap", {"name": "Scrap Metal", "kind": "resource", "tier": 2, "stack": 100, "value": 3})
	# Reusable scrap economy: one consumable pick unlocks a sealed compartment
	# only when its owner searches an actual red/black ruin crate.
	_add_item("lockpick_kit", {"name": "Improvised Lockpick Kit", "kind": "material",
		"tier": 2, "stack": 10, "value": 24, "weight": 0.25})
	_add_recipe("lockpick_kit", "lockpick_kit", 1,
		{"scrap": 2, "bar_1": 1, "fiber_1": 2}, "workbench", 4.0)
	# Consumable wilderness survey: reveals one still-unlooted high-risk
	# ruin; actual loot and opponents stay server-owned and unchanged.
	_add_item("ruin_survey_chart", {"name": "Ruin Survey Chart",
		"kind": "material", "tier": 1, "stack": 10, "weight": 0.2, "value": 18})
	_add_recipe("ruin_survey_chart", "ruin_survey_chart", 1,
		{"cloth_1": 1, "fiber_1": 2, "scrap": 1}, "", 3.0)
	# T2 non-full-loot expedition return. PvP full-loot zones always deny it.
	_add_item("return_charm", {"name": "Settler's Return Charm", "kind": "recall",
		"tier": 2, "stack": 5, "value": 90, "weight": 0.15})
	_add_recipe("return_charm", "return_charm", 1,
		{"bar_2": 1, "cloth_2": 2, "silver": 30}, "workbench", 6.0)
	# Crafted noise maker: brief diversion for stealth runs, not free aggro.
	# A tactical consumable: gathering + scavenged scrap become a squad buff.
	_add_item("field_standard", {"name": "Expedition Rally Standard",
		"kind": "standard", "tier": 1, "stack": 3, "weight": 2.0, "value": 55})
	_add_recipe("field_standard", "field_standard", 1,
		{"plank_1": 2, "cloth_1": 2, "scrap": 1}, "workbench", 5.0)
	_add_item("smoke_charge", {"name": "Improvised Smoke Charge",
		"kind": "smoke_charge", "tier": 1, "stack": 10,
		"value": 30, "weight": 0.35})
	_add_recipe("smoke_charge", "smoke_charge", 1,
		{"cloth_1": 2, "scrap": 1}, "workbench", 3.0)
	# A moving emergency night light that sacrifices stealth for visibility.
	_add_item("signal_flare", {"name": "Handheld Signal Flare", "kind": "hand_flare",
		"tier": 1, "stack": 10, "weight": 0.25, "value": 22})
	_add_recipe("signal_flare", "signal_flare", 1,
		{"wood_1": 2, "cloth_1": 1, "scrap": 1}, "", 3.0)
	_add_item("noise_decoy", {"name": "Clattering Decoy", "kind": "decoy",
		"tier": 1, "stack": 10, "value": 14, "weight": 0.25})
	_add_recipe("noise_decoy", "noise_decoy", 1,
		{"wood_1": 2, "scrap": 1}, "", 2.5)
	_add_item("flash_charge", {"name": "Improvised Flash Charge", "kind": "flash",
		"tier": 2, "stack": 5, "weight": 0.5, "value": 42})
	_add_recipe("flash_charge", "flash_charge", 1,
		{"scrap": 2, "bar_2": 1, "cloth_1": 1, "stone_1": 1}, "workbench", 5.0)
	# Workbench-made burning-ground flask: tactical PvE, never PvP.
	_add_item("ember_flask", {"name": "Scavenged Ember Flask",
		"kind": "ember_flask", "tier": 2, "stack": 5, "weight": 0.75, "value": 55})
	_add_recipe("ember_flask", "ember_flask", 1,
		{"bar_2": 1, "cloth_1": 2, "wood_1": 3, "scrap": 1},
		"workbench", 5.5)
	# Risk-zone base sieges use a real short-fused workbench-made consumable.
	# The server chooses the adjacent rival barricade; players cannot aim at IDs.
	_add_item("siege_charge", {"name": "Improvised Siege Charge",
		"kind": "siege_charge", "tier": 3, "stack": 5, "weight": 1.4, "value": 125})
	_add_recipe("siege_charge", "siege_charge", 1,
		{"bar_3": 2, "scrap": 8, "cloth_2": 2, "stone_2": 2},
		"workbench", 9.0)
	# Physical workbench-made countermeasure, one kit per successful defusal.
	_add_item("siege_defusal_kit", {"name": "Field Siege Defusal Kit",
		"kind": "siege_defusal", "tier": 2, "stack": 5,
		"weight": 0.75, "value": 65})
	_add_recipe("siege_defusal_kit", "siege_defusal_kit", 1,
		{"bar_2": 1, "scrap": 4, "cloth_2": 1, "fiber_2": 1},
		"workbench", 5.0)
	# One paid pre-siege brace absorbs a single hostile explosion.
	_add_item("siege_blast_brace", {"name": "Siege Blast Brace T2",
		"kind": "siege_brace", "tier": 2, "stack": 5,
		"weight": 1.8, "value": 90})
	_add_recipe("siege_blast_brace", "siege_blast_brace", 1,
		{"bar_2": 2, "plank_2": 3, "scrap": 5, "cloth_2": 1},
		"workbench", 7.0)
	# Defensive disposable wire snare; only the PvE server can trigger it.
	_add_item("infected_snare", {"name": "Infected Tripwire Snare",
		"kind": "deployable", "tier": 1, "stack": 10, "weight": 0.9, "value": 28})
	_add_recipe("infected_snare", "infected_snare", 1,
		{"wood_1": 2, "fiber_1": 2, "scrap": 1}, "", 3.0)
	# Field-fitted chain wrap lowers the noise from an otherwise rattling bike.
	_add_item("bike_chain_wrap", {"name": "Quiet Chain Wrap", "kind": "bike_wrap",
		"tier": 1, "stack": 5, "weight": 0.3, "value": 24})
	_add_recipe("bike_chain_wrap", "bike_chain_wrap", 1,
		{"cloth_1": 2, "fiber_1": 2, "scrap": 2}, "workbench", 4.0)
	# Physical T2 hiking pack distributes 14 kg on foot; full loot, no slots.
	_add_item("trail_backpack_2", {"name": "Woven Trail Backpack T2",
		"kind": "carry_pack", "tier": 2, "stack": 1,
		"weight": 2.5, "value": 85})
	_add_recipe("trail_backpack_2", "trail_backpack_2", 1,
		{"cloth_2": 4, "fiber_2": 4, "plank_2": 1, "scrap": 2},
		"workbench", 6.0)
	# Tradeable, crafted saddle panniers support limited load only while mounted.
	_add_item("bike_panniers", {"name": "Expedition Bike Panniers", "kind": "bike_cargo",
		"tier": 2, "weight": 3.0, "value": 95})
	_add_recipe("bike_panniers", "bike_panniers", 1,
		{"cloth_2": 4, "plank_2": 2, "scrap": 3, "fiber_2": 3},
		"workbench", 7.0)
	# Specialized consumable off-road tire kit, uses existing network item RPC.
	_add_item("trail_tire_grips", {"name": "Trail Tire Grips", "kind": "tire_grips",
		"tier": 2, "stack": 5, "weight": 0.65, "value": 54})
	_add_recipe("trail_tire_grips", "trail_tire_grips", 1,
		{"cloth_2": 2, "fiber_2": 2, "scrap": 2}, "workbench", 5.0)
	# Paid chain service lasts for an actual travelled distance.
	_add_item("bike_service_kit", {"name": "Bicycle Drive Service Kit",
		"kind": "bike_service", "tier": 1, "stack": 5, "weight": 0.8, "value": 35})
	_add_recipe("bike_service_kit", "bike_service_kit", 1,
		{"bar_1": 1, "scrap": 2, "cloth_1": 1}, "workbench", 4.0)
	# Repairable bicycle frame: a patch restores 45 integrity points while dismounted.
	_add_item("bike_frame_patch", {"name": "Salvaged Bike Frame Patch",
		"kind": "bike_frame_repair", "tier": 2, "stack": 5, "weight": 1.5, "value": 75})
	_add_recipe("bike_frame_patch", "bike_frame_patch", 1,
		{"bar_2": 2, "scrap": 4, "cloth_2": 2}, "workbench", 6.0)
	# A permanently craftable bike lamp trades night vision for infected attention.
	_add_item("bike_dynamo_lamp", {"name": "Trail Bike Dynamo Lantern",
		"kind": "bike_light", "tier": 2, "weight": 1.0, "value": 90})
	_add_recipe("bike_dynamo_lamp", "bike_dynamo_lamp", 1,
		{"bar_2": 1, "scrap": 3, "cloth_2": 1}, "workbench", 7.0)
	# Crafted travel vehicle; ownership and cooldowns are checked by the server.
	# Boat: carried in the pack; in deep water you paddle it instead of swimming.
	_add_item("raft", {"name": "Driftwood Raft", "kind": "boat", "tier": 1, "weight": 9.0, "value": 70,
		"desc": "In deep water you paddle across the surface at speed instead of swimming. Cannot dive."})
	_add_recipe("raft", "raft", 1, {"plank_1": 10, "fiber_1": 8}, "workbench", 6.0)
	_add_item("salvage_bike", {"name": "Salvaged Trail Bike", "kind": "mount",
		"tier": 2, "weight": 12.0, "value": 180})
	_add_recipe("salvage_bike", "salvage_bike", 1,
		{"bar_2": 4, "plank_2": 3, "scrap": 5, "fiber_2": 4},
		"workbench", 12.0)
	_add_item("silver", {"name": "Silver", "kind": "currency", "stack": 100000, "value": 1})
	# Homestead farming (see farming.gd): seeds from the hub trader, crops from personal plots.
	_add_item("carrot_seeds", {"name": "Carrot Seeds", "kind": "seed", "stack": 50, "value": 3, "weight": 0.01})
	_add_item("potato_seeds", {"name": "Potato Seeds", "kind": "seed", "stack": 50, "value": 4, "weight": 0.01})
	_add_item("wheat_seeds", {"name": "Wheat Seeds", "kind": "seed", "stack": 50, "value": 4, "weight": 0.01})
	_add_item("carrot", {"name": "Carrot", "kind": "food", "food": 14.0, "stack": 30, "value": 3, "weight": 0.1})
	_add_item("potato", {"name": "Potato", "kind": "food", "food": 20.0, "stack": 30, "value": 4, "weight": 0.2})
	_add_item("wheat", {"name": "Wheat", "kind": "material", "stack": 60, "value": 2, "weight": 0.1})
	_add_item("farm_bread", {"name": "Farm Bread", "kind": "food", "food": 45.0, "stack": 20, "value": 12, "weight": 0.3})
	_add_recipe("farm_bread", "farm_bread", 1, {"wheat": 3}, "campfire", 3.0)
	# Albion-style enchantment materials, dropped by infected (runes), elites (souls)
	# and raid bosses (relics). Spent at a workbench to raise gear to .1 / .2 / .3.
	_add_item("rune", {"name": "Rune", "kind": "enchant_material", "stack": 999, "value": 6, "weight": 0.02})
	_add_item("soul", {"name": "Soul", "kind": "enchant_material", "stack": 999, "value": 24, "weight": 0.02})
	_add_item("relic", {"name": "Relic", "kind": "enchant_material", "stack": 999, "value": 90, "weight": 0.02})
	_build_enchantments()


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
		"pebble":
			return {"yield": "stone", "amount": 1, "seconds": 0.0, "respawn": 90.0, "radius": 0.25, "blocks": false}
		"ore":
			return {"yield": "ore", "amount": 3, "seconds": 4.5, "respawn": 200.0, "radius": 0.7, "blocks": true}
		"bush":
			return {"yield": "fiber", "amount": 3, "seconds": 1.6, "respawn": 90.0, "radius": 0.4, "blocks": false}
		"berry":
			return {"yield": "berries", "amount": 3, "seconds": 1.2, "respawn": 90.0, "radius": 0.4, "blocks": false}
	return {}


# --- Enchantment and item power (Albion Online style) ----------------------------------------------------------

const MAX_ENCHANT := 3
const ENCHANT_KINDS := ["weapon", "armor", "head", "cape", "hands", "feet", "tool"]
const ENCHANT_STAT_BONUS := 0.10 # +10% damage / protection per enchant level.
const ENCHANT_MATERIALS := ["", "rune", "soul", "relic"] # Material to reach .1 / .2 / .3.


## Adds `<base>@1..@3` variants for every piece of gear. Same item, stronger stats.
static func _build_enchantments() -> void:
	var bases: Array = []
	for id in _items.keys():
		if ENCHANT_KINDS.has(str(_items[id].get("kind", ""))) and not str(id).contains("@"):
			bases.append(str(id))
	for base in bases:
		var info: Dictionary = _items[base]
		for level in range(1, MAX_ENCHANT + 1):
			var variant: Dictionary = info.duplicate(true)
			var mult: float = 1.0 + ENCHANT_STAT_BONUS * float(level)
			for stat in ["damage", "armor"]:
				if variant.has(stat):
					variant[stat] = float(variant[stat]) * mult
			variant["name"] = "%s .%d" % [str(info.get("name", base)), level]
			variant["value"] = int(round(float(info.get("value", 1)) * (1.0 + float(level))))
			variant["enchant"] = level
			variant["base"] = base
			variant.erase("id")
			_add_item(enchanted_id(base, level), variant)


## "club_2" + 1 -> "club_2@1"; level 0 is the base item.
static func enchanted_id(base: String, level: int) -> String:
	return base if level <= 0 else "%s@%d" % [base, level]


## The unenchanted item an id belongs to ("club_2@3" -> "club_2").
static func unenchanted_id(id: String) -> String:
	return base_id(id).get_slice("@", 0)


static func enchant_of(id: String) -> int:
	return int(item(id).get("enchant", 0))


## Albion item power: 300 + 100 per tier + 100 per enchantment level (T4.1 = 800),
## plus the quality bonus (Good +20, Outstanding +40, Excellent +60, Masterpiece +100).
static func item_power(id: String) -> int:
	var tier: int = tier_of(id)
	if tier <= 0:
		return 0
	var quality_bonus: int = [0, 0, 20, 40, 60, 100][clampi(int(item(id).get("quality", 1)), 0, 5)]
	return 300 + 100 * tier + 100 * enchant_of(id) + quality_bonus


## What enchanting `id` one level further costs: {material: count, "silver": n}, or {} if it cannot be enchanted.
static func enchant_cost(id: String) -> Dictionary:
	var info := item(id)
	if info.is_empty() or not ENCHANT_KINDS.has(str(info.get("kind", ""))):
		return {}
	var level: int = enchant_of(id)
	if level >= MAX_ENCHANT:
		return {}
	var tier: int = maxi(1, tier_of(id))
	var material: String = ENCHANT_MATERIALS[level + 1]
	return {material: tier * 4, "silver": 25 * tier * (level + 1)}
