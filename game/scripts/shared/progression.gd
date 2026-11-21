extends RefCounted
## Server-owned, classless gathering and crafting progression.
## Persistent skills survive character death; access checks are authoritative.

const Defs = preload("res://scripts/shared/defs.gd")
const Scavenging = preload("res://scripts/shared/scavenging.gd")
const XP_PER_LEVEL := 100
const MAX_XP := 100000000
const GATHER_XP_PER_ITEM := 8
const CRAFT_XP_PER_BATCH := 25
const GATHER_SKILLS := ["wood", "stone", "ore", "fiber", "fishing"]
# Equipment-based weapon mastery; awarded by the authoritative server on confirmed kills.
const COMBAT_SKILLS := ["melee", "ranged"]
const COMBAT_XP_PER_LEVEL := 80
const COMBAT_MAX_LEVEL := 5
const COMBAT_DAMAGE_PER_LEVEL := 0.03

var gathering_xp: Dictionary = {"wood": 0, "stone": 0, "ore": 0, "fiber": 0, "fishing": 0}
var crafting_xp: int = 0
var combat_xp: Dictionary = {"melee": 0, "ranged": 0}
var scavenging_xp: int = 0
# Albion Destiny Board-style weapon line mastery: fame per weapon family ("spear", "club"...).
var weapon_fame: Dictionary = {}
# Albion-style focus points: a daily crafting budget (see return_rate.gd). New characters start full.
var focus: float = 10000.0
const MASTERY_MAX_LEVEL := 100
const MASTERY_FAME_SCALE := 20.0 # level = sqrt(fame / 20): L10 = 2k fame, L100 = 200k fame.
const MASTERY_IP_PER_LEVEL := 2 # Albion: specialization raises the item power of that line.
const MASTERY_ULTIMATE_PER_LEVEL := 0.002 # Weapon ultimate (E) scales with line mastery.


static func resource_skill(kind: String) -> String:
	match kind:
		"tree": return "wood"
		"rock": return "stone"
		"ore": return "ore"
		"bush": return "fiber"
		"fishing": return "fishing"
		_: return "" # Berries are freely scavenged; unknown nodes have no skill.


static func level_for_xp(xp: int) -> int:
	return mini(Defs.MAX_TIER, 1 + maxi(xp, 0) / XP_PER_LEVEL)


func gathering_level(kind: String) -> int:
	if not gathering_xp.has(kind):
		return 0
	return level_for_xp(int(gathering_xp[kind]))


func crafting_level() -> int:
	return level_for_xp(crafting_xp)


func can_gather(kind: String, tier: int) -> bool:
	var skill := resource_skill(kind)
	return tier >= 1 and tier <= Defs.MAX_TIER and (skill == "" or gathering_level(skill) >= tier)


func can_craft_tier(tier: int) -> bool:
	return tier <= 1 or crafting_level() >= tier


func award_gather(kind: String, tier: int, quantity: int) -> int:
	var skill := resource_skill(kind)
	if skill == "" or tier < 1 or tier > Defs.MAX_TIER or quantity <= 0:
		return 0
	var old_xp := int(gathering_xp[skill])
	gathering_xp[skill] = mini(MAX_XP, old_xp + mini(quantity, 100000) * GATHER_XP_PER_ITEM * tier)
	return int(gathering_xp[skill]) - old_xp


func award_craft(tier: int, batches: int) -> int:
	if tier < 0 or tier > Defs.MAX_TIER or batches <= 0:
		return 0
	var old_xp := crafting_xp
	crafting_xp = mini(MAX_XP, old_xp + mini(batches, 50) * CRAFT_XP_PER_BATCH * maxi(tier, 1))
	return crafting_xp - old_xp


static func combat_skill_for_weapon(weapon_id: String) -> String:
	var kind: String = str(Defs.item(weapon_id).get("weapon", ""))
	return kind if kind in COMBAT_SKILLS else ""


func combat_level(skill: String) -> int:
	if not combat_xp.has(skill):
		return 0
	return mini(COMBAT_MAX_LEVEL,
		1 + maxi(0, int(combat_xp[skill])) / COMBAT_XP_PER_LEVEL)


func combat_levels() -> Dictionary:
	return {"melee": combat_level("melee"), "ranged": combat_level("ranged")}


func combat_damage_multiplier(weapon_id: String) -> float:
	var skill := combat_skill_for_weapon(weapon_id)
	if skill == "":
		return 1.0
	return 1.0 + float(combat_level(skill) - 1) * COMBAT_DAMAGE_PER_LEVEL


func award_combat(weapon_id: String, earned_xp: int) -> int:
	var skill := combat_skill_for_weapon(weapon_id)
	if skill == "" or earned_xp <= 0:
		return 0
	# The same fight also builds mastery of this specific weapon line.
	var family: String = weapon_family(weapon_id)
	if family != "":
		weapon_fame[family] = mini(MAX_XP, int(weapon_fame.get(family, 0)) + mini(earned_xp, 1000))
	var old_xp: int = int(combat_xp[skill])
	combat_xp[skill] = mini(MAX_XP, old_xp + mini(earned_xp, 1000))
	return int(combat_xp[skill]) - old_xp


func scavenging_level() -> int:
	return Scavenging.level_for_xp(scavenging_xp)


func award_scavenge(zone: int) -> int:
	var amount: int = Scavenging.xp_for_zone(zone)
	if amount <= 0:
		return 0
	var old_xp: int = scavenging_xp
	scavenging_xp = mini(MAX_XP, scavenging_xp + amount)
	return scavenging_xp - old_xp


func levels() -> Dictionary:
	var result: Dictionary = {}
	for skill in GATHER_SKILLS:
		result[skill] = gathering_level(skill)
	return result


func to_dict() -> Dictionary:
	return {"gathering": gathering_xp.duplicate(true),
		"crafting": crafting_xp, "combat": combat_xp.duplicate(true),
		"scavenging": scavenging_xp, "weapon_fame": weapon_fame.duplicate(), "focus": focus}


static func _valid_xp(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= float(MAX_XP) and number == floor(number)


## Atomic validation: invalid or client-forged data cannot replace live skill XP.
func load_dict(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var source: Variant = data.get("gathering", null)
	if not (source is Dictionary) or source.size() not in [GATHER_SKILLS.size(), GATHER_SKILLS.size() - 1]:
		return false
	if source.size() == GATHER_SKILLS.size() and not source.has("fishing"):
		return false # Extra foreign key must not masquerade as legacy fishing.
	if not _valid_xp(data.get("crafting", null)):
		return false
	var clean: Dictionary = {}
	for skill in GATHER_SKILLS:
		# Save files made before fishing had only four gather professions.
		# All other missing/forged fields remain invalid.
		if skill == "fishing" and not source.has(skill):
			clean[skill] = 0
			continue
		if not source.has(skill) or not _valid_xp(source[skill]):
			return false
		clean[skill] = int(source[skill])
	# Old characters have no combat subtree; missing data starts at novice level.
	var combat_raw: Variant = data.get("combat", {"melee": 0, "ranged": 0})
	if not (combat_raw is Dictionary) or combat_raw.size() != COMBAT_SKILLS.size():
		return false
	var clean_combat: Dictionary = {}
	for skill in COMBAT_SKILLS:
		if not combat_raw.has(skill) or not _valid_xp(combat_raw[skill]):
			return false
		clean_combat[skill] = int(combat_raw[skill])
	# Legacy records predate scavenging; malformed newer records fail atomically.
	var scavenging_raw: Variant = data.get("scavenging", 0)
	if not _valid_xp(scavenging_raw):
		return false
	# Atomic commit: corrupt mastery XP must not mutate any existing profession.
	gathering_xp = clean
	crafting_xp = int(data["crafting"])
	combat_xp = clean_combat
	scavenging_xp = int(scavenging_raw)
	load_weapon_fame(data.get("weapon_fame", {}))
	var saved_focus: Variant = data.get("focus", 10000.0)
	if (saved_focus is float or saved_focus is int) and is_finite(float(saved_focus)):
		focus = clampf(float(saved_focus), 0.0, 10000.0)
	return true


## Weapon line of an item: "spear_3@2+4" -> "spear"; "pistol" -> "pistol". "" for non-weapons.
static func weapon_family(weapon_id: String) -> String:
	if weapon_id == "" or str(Defs.item(weapon_id).get("kind", "")) != "weapon":
		return ""
	var plain: String = Defs.unenchanted_id(weapon_id)
	var cut: int = plain.rfind("_")
	if cut > 0 and plain.substr(cut + 1).is_valid_int():
		return plain.substr(0, cut)
	return plain


static func mastery_level_for_fame(fame: int) -> int:
	return clampi(int(floor(sqrt(maxf(0.0, float(fame)) / MASTERY_FAME_SCALE))), 0, MASTERY_MAX_LEVEL)


func weapon_mastery_level(weapon_id: String) -> int:
	var family: String = weapon_family(weapon_id)
	return 0 if family == "" else mastery_level_for_fame(int(weapon_fame.get(family, 0)))


## Restores saved mastery; malformed entries are skipped (older saves have none).
func load_weapon_fame(raw: Variant) -> void:
	weapon_fame = {}
	if not (raw is Dictionary):
		return
	for family in raw:
		if family is String and family.length() <= 40 and _valid_xp(raw[family]):
			weapon_fame[family] = int(raw[family])


## Extra item power from mastering this weapon's line (+2 IP per level, +200 at L100).
func mastery_item_power(weapon_id: String) -> int:
	return weapon_mastery_level(weapon_id) * MASTERY_IP_PER_LEVEL


## Multiplier for the weapon ultimate's damage from line mastery (up to +20%).
func mastery_ultimate_multiplier(weapon_id: String) -> float:
	return 1.0 + float(weapon_mastery_level(weapon_id)) * MASTERY_ULTIMATE_PER_LEVEL
