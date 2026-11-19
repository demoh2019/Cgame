extends RefCounted
## The skill tree: every kind of action trains its own skill, levels give passive bonuses, and every level
## also gives a skill point to spend on perks in that skill's branch. Server-owned and persisted; nothing
## here trusts a client: levels come from XP, perks are bought with points the XP earned.
##
## Branches and skills
##   Gathering : woodcutting, mining, foraging
##   Combat    : melee, marksman, slayer (zombie kills), toughness (damage taken)
##   Survival  : athletics (running), survivalist (eating and drinking), medic (healing)
##   Craft     : crafting, scavenging (searching crates and bags)
##   Explorer  : explorer (distance and new regions)
## Bonus names (see BONUS_CAPS) are plain numbers the rest of the game asks for with `bonus("name")`.

const MAX_LEVEL := 50
const XP_BASE := 40.0
const XP_EXPONENT := 1.55
const MAX_XP := 400000
const SAVE_VERSION := 1

const BRANCHES := {
	"gathering": {"name": "Gathering", "skills": ["woodcutting", "mining", "foraging"]},
	"combat": {"name": "Combat", "skills": ["melee", "marksman", "slayer", "toughness"]},
	"survival": {"name": "Survival", "skills": ["athletics", "survivalist", "medic"]},
	"craft": {"name": "Craft", "skills": ["crafting", "scavenging"]},
	"explorer": {"name": "Explorer", "skills": ["explorer"]},
}

# Passive bonus per level above 1 for each skill.
const SKILLS := {
	"woodcutting": {"name": "Woodcutting", "branch": "gathering", "trained_by": "Chopping trees", "passive": {"gather_speed.woodcutting": 0.012, "gather_yield.woodcutting": 0.004}},
	"mining": {"name": "Mining", "branch": "gathering", "trained_by": "Breaking rock and ore", "passive": {"gather_speed.mining": 0.012, "gather_yield.mining": 0.004}},
	"foraging": {"name": "Foraging", "branch": "gathering", "trained_by": "Picking bushes and berries", "passive": {"gather_speed.foraging": 0.012, "gather_yield.foraging": 0.005}},
	"melee": {"name": "Melee", "branch": "combat", "trained_by": "Hitting enemies in close combat", "passive": {"melee_damage": 0.008, "crit_chance": 0.002}},
	"marksman": {"name": "Marksman", "branch": "combat", "trained_by": "Hitting enemies with firearms", "passive": {"ranged_damage": 0.008, "ammo_save": 0.003}},
	"slayer": {"name": "Slayer", "branch": "combat", "trained_by": "Killing the infected", "passive": {"zombie_damage": 0.006, "zombie_silver": 0.01}},
	"toughness": {"name": "Toughness", "branch": "combat", "trained_by": "Surviving damage", "passive": {"damage_reduction": 0.004, "max_health": 0.6}},
	"athletics": {"name": "Athletics", "branch": "survival", "trained_by": "Running", "passive": {"move_speed": 0.003, "stamina_drain": 0.008}},
	"survivalist": {"name": "Survivalist", "branch": "survival", "trained_by": "Eating and drinking", "passive": {"hunger_rate": 0.006, "thirst_rate": 0.006, "food_power": 0.005}},
	"medic": {"name": "Medic", "branch": "survival", "trained_by": "Treating wounds", "passive": {"heal_power": 0.01}},
	"crafting": {"name": "Crafting", "branch": "craft", "trained_by": "Making things at the workbench", "passive": {"craft_refund": 0.004}},
	"scavenging": {"name": "Scavenging", "branch": "craft", "trained_by": "Searching crates and bags", "passive": {"loot_silver": 0.01, "loot_extra": 0.003}},
	"explorer": {"name": "Explorer", "branch": "explorer", "trained_by": "Travelling and finding new regions", "passive": {"carry_capacity": 0.008, "xp_gain": 0.002}},
}

# Bonuses never exceed these, however they are earned.
const BONUS_CAPS := {
	"gather_speed.woodcutting": 2.0, "gather_speed.mining": 2.0, "gather_speed.foraging": 2.0,
	"gather_yield.woodcutting": 0.8, "gather_yield.mining": 0.8, "gather_yield.foraging": 0.8,
	"melee_damage": 2.0, "ranged_damage": 2.0, "zombie_damage": 2.0, "crit_chance": 0.5, "crit_damage": 1.5,
	"ammo_save": 0.6, "zombie_silver": 3.0, "damage_reduction": 0.4, "max_health": 100.0,
	"move_speed": 0.35, "stamina_drain": 0.7, "stamina_regen": 1.0,
	"hunger_rate": 0.7, "thirst_rate": 0.7, "food_power": 1.5, "heal_power": 3.0,
	"craft_refund": 0.5, "loot_silver": 3.0, "loot_extra": 0.5, "carry_capacity": 1.5, "xp_gain": 0.6,
}
const MAX_HEALTH_BONUS := 100.0 # Same as BONUS_CAPS["max_health"]; used for save validation.

# Perks. Rank r (1-based) needs skill level `level + level_step * (r - 1)`. `requires` names another perk that
# must already have at least `requires_rank` ranks. Costs are per rank.
const PERKS := {
	"sharp_axe": {"skill": "woodcutting", "name": "Sharp Axe", "desc": "Chop trees faster", "bonus": "gather_speed.woodcutting", "per_rank": 0.06, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"timber_luck": {"skill": "woodcutting", "name": "Timber Luck", "desc": "Chance for extra wood", "bonus": "gather_yield.woodcutting", "per_rank": 0.05, "max_rank": 4, "level": 10, "level_step": 8, "cost": 2},
	"forest_master": {"skill": "woodcutting", "name": "Forest Master", "desc": "Mighty strokes", "bonus": "gather_speed.woodcutting", "per_rank": 0.25, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "sharp_axe", "requires_rank": 3},
	"deep_miner": {"skill": "mining", "name": "Deep Miner", "desc": "Break rock and ore faster", "bonus": "gather_speed.mining", "per_rank": 0.06, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"rich_vein": {"skill": "mining", "name": "Rich Vein", "desc": "Chance for extra stone and ore", "bonus": "gather_yield.mining", "per_rank": 0.05, "max_rank": 4, "level": 10, "level_step": 8, "cost": 2},
	"mountain_king": {"skill": "mining", "name": "Mountain King", "desc": "Mighty strokes", "bonus": "gather_speed.mining", "per_rank": 0.25, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "deep_miner", "requires_rank": 3},
	"nimble_fingers": {"skill": "foraging", "name": "Nimble Fingers", "desc": "Pick faster", "bonus": "gather_speed.foraging", "per_rank": 0.06, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"bountiful_harvest": {"skill": "foraging", "name": "Bountiful Harvest", "desc": "Chance for extra fiber and berries", "bonus": "gather_yield.foraging", "per_rank": 0.06, "max_rank": 4, "level": 10, "level_step": 8, "cost": 2},
	"green_thumb": {"skill": "foraging", "name": "Green Thumb", "desc": "Mighty picking", "bonus": "gather_yield.foraging", "per_rank": 0.2, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "nimble_fingers", "requires_rank": 3},
	"heavy_hands": {"skill": "melee", "name": "Heavy Hands", "desc": "Melee hits harder", "bonus": "melee_damage", "per_rank": 0.05, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"precision": {"skill": "melee", "name": "Precision", "desc": "Melee critical chance", "bonus": "crit_chance", "per_rank": 0.03, "max_rank": 5, "level": 12, "level_step": 6, "cost": 2},
	"executioner": {"skill": "melee", "name": "Executioner", "desc": "Critical hits deal much more", "bonus": "crit_damage", "per_rank": 0.5, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "precision", "requires_rank": 3},
	"steady_aim": {"skill": "marksman", "name": "Steady Aim", "desc": "Firearms hit harder", "bonus": "ranged_damage", "per_rank": 0.05, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"thrifty_shooter": {"skill": "marksman", "name": "Thrifty Shooter", "desc": "Chance not to use ammunition", "bonus": "ammo_save", "per_rank": 0.04, "max_rank": 5, "level": 10, "level_step": 6, "cost": 2},
	"headhunter": {"skill": "marksman", "name": "Headhunter", "desc": "Deadly firearms", "bonus": "ranged_damage", "per_rank": 0.3, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "steady_aim", "requires_rank": 3},
	"zombie_hunter": {"skill": "slayer", "name": "Zombie Hunter", "desc": "More damage to the infected", "bonus": "zombie_damage", "per_rank": 0.05, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"bounty": {"skill": "slayer", "name": "Bounty", "desc": "The infected drop more silver", "bonus": "zombie_silver", "per_rank": 0.15, "max_rank": 5, "level": 10, "level_step": 6, "cost": 2},
	"apex_predator": {"skill": "slayer", "name": "Apex Predator", "desc": "Terrifying damage to the infected", "bonus": "zombie_damage", "per_rank": 0.3, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "zombie_hunter", "requires_rank": 3},
	"thick_skin": {"skill": "toughness", "name": "Thick Skin", "desc": "Take less damage", "bonus": "damage_reduction", "per_rank": 0.02, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"vitality": {"skill": "toughness", "name": "Vitality", "desc": "More maximum health", "bonus": "max_health", "per_rank": 6.0, "max_rank": 5, "level": 8, "level_step": 6, "cost": 2},
	"unbreakable": {"skill": "toughness", "name": "Unbreakable", "desc": "Shrug off blows", "bonus": "damage_reduction", "per_rank": 0.06, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "thick_skin", "requires_rank": 3},
	"swift_feet": {"skill": "athletics", "name": "Swift Feet", "desc": "Move faster", "bonus": "move_speed", "per_rank": 0.02, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"strong_lungs": {"skill": "athletics", "name": "Strong Lungs", "desc": "Sprinting costs less stamina", "bonus": "stamina_drain", "per_rank": 0.06, "max_rank": 5, "level": 10, "level_step": 6, "cost": 2},
	"marathoner": {"skill": "athletics", "name": "Marathoner", "desc": "Stamina recovers much faster", "bonus": "stamina_regen", "per_rank": 0.4, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "strong_lungs", "requires_rank": 3},
	"iron_stomach": {"skill": "survivalist", "name": "Iron Stomach", "desc": "Hunger grows slower", "bonus": "hunger_rate", "per_rank": 0.06, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"camel": {"skill": "survivalist", "name": "Camel", "desc": "Thirst grows slower", "bonus": "thirst_rate", "per_rank": 0.06, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"nutrition": {"skill": "survivalist", "name": "Nutrition", "desc": "Food and drink restore more", "bonus": "food_power", "per_rank": 0.1, "max_rank": 4, "level": 12, "level_step": 8, "cost": 2},
	"field_medic": {"skill": "medic", "name": "Field Medic", "desc": "Healing heals more", "bonus": "heal_power", "per_rank": 0.08, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"triage": {"skill": "medic", "name": "Triage", "desc": "Masterful healing", "bonus": "heal_power", "per_rank": 0.4, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "field_medic", "requires_rank": 3},
	"thrifty_maker": {"skill": "crafting", "name": "Thrifty Maker", "desc": "Chance to save materials", "bonus": "craft_refund", "per_rank": 0.04, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"master_hand": {"skill": "crafting", "name": "Master Hand", "desc": "Waste almost nothing", "bonus": "craft_refund", "per_rank": 0.1, "max_rank": 1, "level": 40, "level_step": 0, "cost": 5, "requires": "thrifty_maker", "requires_rank": 3},
	"keen_eye": {"skill": "scavenging", "name": "Keen Eye", "desc": "More silver from loot", "bonus": "loot_silver", "per_rank": 0.1, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"lucky_find": {"skill": "scavenging", "name": "Lucky Find", "desc": "Chance for an extra item from loot", "bonus": "loot_extra", "per_rank": 0.04, "max_rank": 5, "level": 10, "level_step": 6, "cost": 2},
	"pathfinder": {"skill": "explorer", "name": "Pathfinder", "desc": "Carry more without slowing down", "bonus": "carry_capacity", "per_rank": 0.08, "max_rank": 5, "level": 5, "level_step": 5, "cost": 1},
	"wanderer": {"skill": "explorer", "name": "Wanderer", "desc": "All skills train faster", "bonus": "xp_gain", "per_rank": 0.03, "max_rank": 5, "level": 10, "level_step": 6, "cost": 2},
}

enum Buy { OK, UNKNOWN, MAX_RANK, LEVEL, REQUIRES, POINTS }

static var _thresholds: Array = [] # Cumulative XP needed to reach each level.

var xp: Dictionary = {} # skill -> int
var ranks: Dictionary = {} # perk -> int
var zones_seen: int = 0 # Bit mask of explored regions.


func _init() -> void:
	reset()


func reset() -> void:
	xp = {}
	for skill in SKILLS:
		xp[skill] = 0
	ranks = {}
	zones_seen = 0


# --- The XP curve -----------------------------------------------------------------------------------------------

## XP needed to advance from `level` to the next one.
static func xp_to_next(level: int) -> int:
	return int(XP_BASE * pow(float(maxi(level, 1)), XP_EXPONENT))


## Total XP at which a skill reaches `level` (level 1 needs none).
static func xp_for_level(level: int) -> int:
	if _thresholds.is_empty():
		var total := 0
		_thresholds.append(0) # Level 1.
		for l in range(1, MAX_LEVEL):
			total += xp_to_next(l)
			_thresholds.append(total)
	return _thresholds[clampi(level, 1, MAX_LEVEL) - 1]


static func level_for_xp(amount: int) -> int:
	if amount <= 0:
		return 1
	var level := 1
	while level < MAX_LEVEL and amount >= xp_for_level(level + 1):
		level += 1
	return level


func level(skill: String) -> int:
	return level_for_xp(int(xp.get(skill, 0)))


func total_level() -> int:
	var total := 0
	for skill in SKILLS:
		total += level(skill)
	return total


## 0..1 progress to the next level.
func progress(skill: String) -> float:
	var current := level(skill)
	if current >= MAX_LEVEL:
		return 1.0
	var span := xp_for_level(current + 1) - xp_for_level(current)
	return clampf(float(int(xp[skill]) - xp_for_level(current)) / float(span), 0.0, 1.0)


# --- Points and perks ---------------------------------------------------------------------------------------------

## One point for every level gained in any skill.
func points_earned() -> int:
	return total_level() - SKILLS.size()


static func perk_cost_of(perk_id: String, rank_count: int) -> int:
	return int(PERKS[perk_id]["cost"]) * rank_count


func points_spent() -> int:
	var spent := 0
	for perk_id in ranks:
		spent += perk_cost_of(perk_id, int(ranks[perk_id]))
	return spent


func points_available() -> int:
	return points_earned() - points_spent()


func rank(perk_id: String) -> int:
	return int(ranks.get(perk_id, 0))


## What the next rank of a perk needs, or {} when it is maxed. Used by the interface and by `buy_perk`.
func next_rank_requirement(perk_id: String) -> Dictionary:
	if not PERKS.has(perk_id):
		return {}
	var perk: Dictionary = PERKS[perk_id]
	var current := rank(perk_id)
	if current >= int(perk["max_rank"]):
		return {}
	return {"level": int(perk["level"]) + int(perk["level_step"]) * current, "cost": int(perk["cost"])}


func buy_perk(perk_id: String) -> int:
	if not PERKS.has(perk_id):
		return Buy.UNKNOWN
	var perk: Dictionary = PERKS[perk_id]
	var need := next_rank_requirement(perk_id)
	if need.is_empty():
		return Buy.MAX_RANK
	if level(String(perk["skill"])) < int(need["level"]):
		return Buy.LEVEL
	if perk.has("requires") and rank(String(perk["requires"])) < int(perk.get("requires_rank", 1)):
		return Buy.REQUIRES
	if points_available() < int(need["cost"]):
		return Buy.POINTS
	ranks[perk_id] = rank(perk_id) + 1
	return Buy.OK


# --- Bonuses -----------------------------------------------------------------------------------------------------------

## The total of a named bonus from passives and perks, never above its cap. 0 for unknown names.
func bonus(name: String) -> float:
	var total := 0.0
	for skill in SKILLS:
		var passive: Dictionary = SKILLS[skill]["passive"]
		if passive.has(name):
			total += float(passive[name]) * float(level(skill) - 1)
	for perk_id in ranks:
		var perk: Dictionary = PERKS[perk_id]
		if perk["bonus"] == name:
			total += float(perk["per_rank"]) * float(ranks[perk_id])
	return minf(total, float(BONUS_CAPS.get(name, 0.0)))


## All non-zero bonuses, for the interface.
func all_bonuses() -> Dictionary:
	var result: Dictionary = {}
	for name in BONUS_CAPS:
		var value := bonus(name)
		if value > 0.00001:
			result[name] = value
	return result


# --- Gaining XP --------------------------------------------------------------------------------------------------------

## Adds XP to a skill (the explorer's xp_gain bonus applies). Returns {"gained": int, "levels": [new levels]}.
func add_xp(skill: String, amount: float) -> Dictionary:
	if not SKILLS.has(skill) or not is_finite(amount) or amount <= 0.0:
		return {"gained": 0, "levels": []}
	var scaled := int(round(amount * (1.0 + bonus("xp_gain"))))
	scaled = clampi(scaled, 1, 100000)
	var before := level(skill)
	var old_xp := int(xp[skill])
	xp[skill] = mini(MAX_XP, old_xp + scaled)
	var levels: Array = []
	for l in range(before + 1, level(skill) + 1):
		levels.append(l)
	return {"gained": int(xp[skill]) - old_xp, "levels": levels}


## Which skill a gatherable node trains.
static func skill_for_node(kind: String) -> String:
	match kind:
		"tree": return "woodcutting"
		"rock", "ore": return "mining"
		"bush", "berry": return "foraging"
	return ""


# --- Persistence ---------------------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "xp": xp.duplicate(true), "ranks": ranks.duplicate(true), "zones": zones_seen}


static func _whole(value: Variant, upper: float) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= upper and number == floor(number)


## Atomic: returns false and changes nothing unless the data is fully consistent. Perks must be affordable with
## the points the XP earned, meet their level and prerequisite rules, and no unknown skill or perk may appear.
func load_dict(data: Variant) -> bool:
	if not (data is Dictionary) or int(data.get("v", 0)) != SAVE_VERSION:
		return false
	var raw_xp: Variant = data.get("xp")
	var raw_ranks: Variant = data.get("ranks", {})
	if not (raw_xp is Dictionary) or not (raw_ranks is Dictionary):
		return false
	var clean_xp: Dictionary = {}
	for skill in SKILLS:
		clean_xp[skill] = 0
	for skill in raw_xp:
		if not SKILLS.has(skill) or not _whole(raw_xp[skill], float(MAX_XP)):
			return false
		clean_xp[skill] = int(raw_xp[skill])
	var clean_ranks: Dictionary = {}
	for perk_id in raw_ranks:
		if not PERKS.has(perk_id) or not _whole(raw_ranks[perk_id], float(PERKS[perk_id]["max_rank"])):
			return false
		if int(raw_ranks[perk_id]) > 0:
			clean_ranks[perk_id] = int(raw_ranks[perk_id])
	var seen: Variant = data.get("zones", 0)
	if not _whole(seen, 255.0):
		return false
	# Check the rules on a scratch copy.
	var scratch = get_script().new()
	scratch.xp = clean_xp
	scratch.ranks = clean_ranks
	for perk_id in clean_ranks:
		var perk: Dictionary = PERKS[perk_id]
		var top_rank := int(clean_ranks[perk_id])
		var need_level := int(perk["level"]) + int(perk["level_step"]) * (top_rank - 1)
		if scratch.level(String(perk["skill"])) < need_level:
			return false
		if perk.has("requires") and int(clean_ranks.get(String(perk["requires"]), 0)) < int(perk.get("requires_rank", 1)):
			return false
	if scratch.points_available() < 0:
		return false
	xp = clean_xp
	ranks = clean_ranks
	zones_seen = int(seen)
	return true


## A one-line text for a bonus, for the interface and tests.
static func describe_bonus(name: String, value: float) -> String:
	match name:
		"max_health": return "+%d max health" % int(round(value))
		_: return "%+d%% %s" % [int(round(value * 100.0)), name.replace("_", " ").replace(".", " ")]
