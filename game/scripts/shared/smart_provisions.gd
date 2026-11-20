extends RefCounted
## Pure, deterministic server-side selection for safe survival provisions.
## This module never consumes items: the authoritative cmd_use does that.
const Defs = preload("res://scripts/shared/defs.gd")

const MIN_NEED := 15.0
const SECONDARY_BENEFIT := 0.85
const VALUE_PENALTY := 0.12
const TIER_PENALTY := 2.5
const PRESERVE_DUAL_MEAL := 12.0


static func pick(inventory, survivor, intent: String) -> String:
	if intent != "food" and intent != "drink":
		return ""
	if inventory == null or survivor == null or not survivor.alive:
		return ""
	if not is_finite(survivor.hunger) or not is_finite(survivor.thirst):
		return ""
	if survivor.hunger < 0.0 or survivor.hunger > 100.0 or \
			survivor.thirst < 0.0 or survivor.thirst > 100.0:
		return ""
	var hungry: float = 100.0 - survivor.hunger
	var thirsty: float = 100.0 - survivor.thirst
	var primary_need: float = hungry if intent == "food" else thirsty
	var secondary_need: float = thirsty if intent == "food" else hungry
	if primary_need < MIN_NEED:
		return ""
	var best_id := ""
	var best_score := INF
	var all_items: Dictionary = Defs.items()
	var candidates: Array = all_items.keys()
	candidates.sort() # Tie-break is stable across platforms and server restarts.
	for raw_id in candidates:
		var id: String = str(raw_id)
		if inventory.count(id) < 1:
			continue
		var data: Dictionary = all_items[id]
		var kind: String = str(data.get("kind", ""))
		# Raw fish is intentionally edible only through its explicit risky hotkey.
		# Unboiled water and lake pouches cannot be suggested as drinks.
		if bool(data.get("unsafe_food", false)):
			continue
		if kind != "food" and kind != "drink":
			continue
		if intent == "food" and kind != "food":
			continue
		var food: float = float(data.get("food", 0.0))
		var drink: float = float(data.get("drink", 0.0))
		var cost: float = float(data.get("value", 0.0))
		if not is_finite(food) or not is_finite(drink) or not is_finite(cost):
			continue
		var primary: float = food if intent == "food" else drink
		var secondary: float = drink if intent == "food" else food
		if primary <= 0.0:
			continue
		var score: float = absf(primary - primary_need) + \
			maxf(0.0, cost) * VALUE_PENALTY + \
			maxf(0.0, float(data.get("tier", 0))) * TIER_PENALTY
		if secondary > 0.0:
			if secondary_need >= MIN_NEED:
				# A real cooked meal can solve two shortages in one action.
				score -= minf(secondary, secondary_need) * SECONDARY_BENEFIT
			else:
				# Preserve scarce mixed meals when the other vital is already full.
				score += PRESERVE_DUAL_MEAL
		if score < best_score:
			best_score = score
			best_id = id
	return best_id
