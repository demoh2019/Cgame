extends RefCounted
## Albion-style enchanting: infected drop runes, elites souls, raid bosses relics.
## At a workbench they raise a piece of gear one level (.0 -> .1 -> .2 -> .3),
## swapping the item for its stronger variant (Defs.enchanted_id). Durability and
## the equipped slot carry over. All authority stays on the server.

const Defs = preload("res://scripts/shared/defs.gd")


## Enchantment materials dropped by a kill. Riskier zones drop more.
static func material_drop(zone: int, elite: bool, raid_boss: bool, rng: RandomNumberGenerator) -> Dictionary:
	var drop: Dictionary = {}
	var z: int = clampi(zone, 0, 3)
	if rng.randf() < 0.06 + 0.06 * float(z):
		drop["rune"] = 1 + (1 if z >= 2 and rng.randf() < 0.5 else 0)
	if elite:
		drop["rune"] = int(drop.get("rune", 0)) + 2
		drop["soul"] = 1 if z < 2 else 2
	if raid_boss:
		drop["soul"] = int(drop.get("soul", 0)) + 3
		drop["relic"] = 1 + z
	return drop


## Enchants one carried `item_id` in `inventory`. Returns {"ok", "item"} or {"ok": false, "reason", ...}.
static func enchant(inventory, item_id: String) -> Dictionary:
	if inventory.count(item_id) < 1:
		return {"ok": false, "reason": "missing_item"}
	var cost: Dictionary = Defs.enchant_cost(item_id)
	if cost.is_empty():
		return {"ok": false, "reason": "cannot_enchant"}
	if not inventory.has_all(cost):
		return {"ok": false, "reason": "need_materials", "cost": cost}
	var next_id: String = Defs.enchanted_id(Defs.base_id(item_id), Defs.enchant_of(item_id) + 1)
	if not Defs.is_item(next_id):
		return {"ok": false, "reason": "cannot_enchant"}
	var was_equipped: bool = inventory.is_equipped(item_id)
	var durability: float = inventory.durability(item_id) if inventory.has_method("durability") else 100.0
	for id in cost:
		inventory.remove(str(id), int(cost[id]))
	inventory.remove(item_id, 1)
	if inventory.add(next_id, 1) > 0:
		# No room for the result (cannot happen after removing the base, but stay safe): roll back.
		inventory.add(item_id, 1)
		for id in cost:
			inventory.add(str(id), int(cost[id]))
		return {"ok": false, "reason": "no_space"}
	inventory.unequip_missing()
	if was_equipped:
		inventory.equip(next_id)
	if durability < 100.0 and inventory.has_method("damage_item"):
		inventory.damage_item(next_id, 100.0 - durability)
	return {"ok": true, "item": next_id, "cost": cost, "item_power": Defs.item_power(next_id)}
