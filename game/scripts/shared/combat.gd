extends RefCounted
## Damage rules and loot tables.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


## Damage after the target's armour. `armor_id` may be empty.
static func apply_armor(damage: float, armor_id: String) -> float:
	var reduction := 0.0
	if armor_id != "":
		reduction = float(Defs.item(armor_id).get("armor", 0.0))
	return damage * (1.0 - clampf(reduction, 0.0, 0.8))


## Equipment-specific secondary wound resistance. Used only when the
## server has confirmed a real infected hit against the wearer, and after
## verifying the armor is still physically in their inventory.
static func infected_wound_amount(amount: float, armor_id: String,
		owned: bool, wound: String) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	if not owned:
		return amount
	var resistance_key := ""
	match wound:
		"infection":
			resistance_key = "infection_resistance"
		"bleeding":
			resistance_key = "bleeding_resistance"
		_:
			return amount
	var reduction: float = float(Defs.item(armor_id).get(resistance_key, 0.0))
	return amount * (1.0 - clampf(reduction, 0.0, 0.8))


## What a weapon does per hit. Fists when unarmed.
static func weapon_damage(weapon_id: String) -> float:
	if weapon_id == "":
		return 6.0
	return float(Defs.item(weapon_id).get("damage", 6.0))


## PvE-only equipment trait. The authoritative server calls this ONLY after
## resolving a hit against a living infected, never for player-versus-player.
static func against_infected(damage: float, weapon_id: String, owned: bool) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	if not owned:
		return damage
	var trait: float = float(Defs.item(weapon_id).get("infected_bonus", 0.0))
	return damage * (1.0 + clampf(trait, 0.0, 0.5))


static func weapon_cooldown(weapon_id: String) -> float:
	if weapon_id == "":
		return 0.6
	return float(Defs.item(weapon_id).get("cooldown", 0.8))


## Equipment determines the active ability. No class selection or client damage.
## Ranged skills consume real server-owned ammunition in GameServer.cmd_skill.
static func active_skill(weapon_id: String) -> Dictionary:
	var info: Dictionary = Defs.item(weapon_id)
	if info.is_empty():
		return {}
	if weapon_id == "purifier_maul_3" and str(info.get("weapon", "")) == "melee":
		return {"id": "purifying_slam", "energy_cost": 35.0, "cooldown": 8.0,
			"attack_lock": 1.1, "range": Defs.MELEE_RANGE + 0.8,
			"damage": weapon_damage(weapon_id) * 1.5,
			"ranged": false}
	if weapon_id.begins_with("club_") and str(info.get("weapon", "")) == "melee":
		return {"id": "heavy_strike", "energy_cost": 30.0, "cooldown": 6.0,
			"attack_lock": 0.95, "range": Defs.MELEE_RANGE + 0.6,
			"damage": weapon_damage(weapon_id) * 1.6,
			"ranged": false}
	if weapon_id == "pistol" and str(info.get("weapon", "")) == "ranged":
		return {"id": "focused_shot", "energy_cost": 40.0, "cooldown": 8.0,
			"attack_lock": 0.55, "range": Defs.PISTOL_RANGE + 4.0,
			"damage": weapon_damage(weapon_id) * 1.75,
			"ranged": true, "ammo": str(info.get("ammo", ""))}
	return {}


## Loot from a ruin crate or a dead zombie: {item_id: count}. Deterministic for a given rng.
static func crate_loot(zone: int, rng: RandomNumberGenerator) -> Dictionary:
	var loot: Dictionary = {}
	var tier := WorldGen.tier_for_zone(zone)
	var rolls := rng.randi_range(2, 4)
	for i in rolls:
		var roll := rng.randf()
		if roll < 0.24:
			loot["canned_food"] = int(loot.get("canned_food", 0)) + 1
		elif roll < 0.44:
			loot["water_bottle"] = int(loot.get("water_bottle", 0)) + 1
		elif roll < 0.60:
			loot["bandage"] = int(loot.get("bandage", 0)) + rng.randi_range(1, 2)
		elif roll < 0.76:
			loot["scrap"] = int(loot.get("scrap", 0)) + rng.randi_range(2, 6)
		elif roll < 0.86:
			loot["cloth_%d" % tier] = int(loot.get("cloth_%d" % tier, 0)) + rng.randi_range(1, 3)
		elif roll < 0.95:
			loot["ammo_9mm"] = int(loot.get("ammo_9mm", 0)) + rng.randi_range(6, 18)
		else:
			loot["pistol"] = 1
	if rng.randf() < (0.14 if zone >= 2 else 0.025):
		loot["antibiotics"] = 1
	var silver := rng.randi_range(2, 10) * tier
	loot["silver"] = silver
	return loot


static func zombie_loot(zombie_type: String, zone: int, rng: RandomNumberGenerator) -> Dictionary:
	var loot: Dictionary = {}
	if rng.randf() < 0.55:
		loot["cloth_%d" % WorldGen.tier_for_zone(zone)] = rng.randi_range(1, 2)
	if rng.randf() < 0.20:
		loot["canned_food"] = 1
	if rng.randf() < 0.30:
		loot["scrap"] = rng.randi_range(1, 3)
	if zombie_type == "brute" and rng.randf() < 0.35:
		loot["bandage"] = 1
	loot["silver"] = rng.randi_range(1, 4) * WorldGen.tier_for_zone(zone)
	return loot
