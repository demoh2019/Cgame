extends RefCounted
## Server-owned, classless gathering and crafting progression.
## Persistent skills survive character death; access checks are authoritative.

const Defs = preload("res://scripts/shared/defs.gd")
const XP_PER_LEVEL := 100
const MAX_XP := 100000000
const GATHER_XP_PER_ITEM := 8
const CRAFT_XP_PER_BATCH := 25
const GATHER_SKILLS := ["wood", "stone", "ore", "fiber"]

var gathering_xp: Dictionary = {"wood": 0, "stone": 0, "ore": 0, "fiber": 0}
var crafting_xp: int = 0


static func resource_skill(kind: String) -> String:
	match kind:
		"tree": return "wood"
		"rock": return "stone"
		"ore": return "ore"
		"bush": return "fiber"
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


func levels() -> Dictionary:
	var result: Dictionary = {}
	for skill in GATHER_SKILLS:
		result[skill] = gathering_level(skill)
	return result


func to_dict() -> Dictionary:
	return {"gathering": gathering_xp.duplicate(true), "crafting": crafting_xp}


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
	if not (source is Dictionary) or source.size() != GATHER_SKILLS.size():
		return false
	if not _valid_xp(data.get("crafting", null)):
		return false
	var clean: Dictionary = {}
	for skill in GATHER_SKILLS:
		if not source.has(skill) or not _valid_xp(source[skill]):
			return false
		clean[skill] = int(source[skill])
	gathering_xp = clean
	crafting_xp = int(data["crafting"])
	return true
