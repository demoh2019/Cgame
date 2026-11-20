extends RefCounted
## Server-owned, atomic recycling of unequipped gear into crafting materials.
## Every yield is calculated from the current item database, never client input.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


static func materials_for(item_id: String) -> Dictionary:
	var item: Dictionary = Defs.item(item_id)
	if str(item.get("kind", "")) not in ["weapon", "armor", "tool"]:
		return {}
	# Data-driven recipe lookup works for new tiered equipment without
	# having to maintain an exploitable second price table.
	var recovered: Dictionary = {}
	for recipe in Defs.recipes().values():
		if str(recipe.get("output", "")) != item_id:
			continue
		var count: int = maxi(1, int(recipe.get("count", 1)))
		# Only a single-unit recipe can safely be reversed one item at a time.
		if count != 1:
			break
		for ingredient in recipe["inputs"]:
			var amount: int = int(floor(float(recipe["inputs"][ingredient]) / 2.0))
			if amount > 0 and Defs.is_item(str(ingredient)):
				recovered[str(ingredient)] = amount
		break
	# Scavenged weapons without crafting recipes yield a little scrap.
	# Crafted gear with only single-quantity inputs also yields no free
	# conversion into higher-tier ingredients.
	if recovered.is_empty():
		recovered["scrap"] = maxi(1, mini(Defs.MAX_TIER, Defs.tier_of(item_id)))
	return recovered


static func transact(inventory: Inventory, item_id: String) -> Dictionary:
	var item: Dictionary = Defs.item(item_id)
	if str(item.get("kind", "")) not in ["weapon", "armor", "tool"]:
		return {"ok": false, "reason": "not_gear"}
	if inventory.count(item_id) < 1:
		return {"ok": false, "reason": "not_carried"}
	# Protect currently equipped items. The player must switch equipment.
	if item_id == inventory.weapon or item_id == inventory.armor:
		return {"ok": false, "reason": "equipped"}
	var materials: Dictionary = materials_for(item_id)
	if materials.is_empty():
		return {"ok": false, "reason": "no_materials"}
	var trial := Inventory.new(inventory.slots.size())
	trial.load_dict(inventory.to_dict())
	if not trial.remove(item_id, 1):
		return {"ok": false, "reason": "not_carried"}
	trial.unequip_missing()
	for material in materials:
		if trial.add(str(material), int(materials[material])) != 0:
			return {"ok": false, "reason": "no_space"}
	# Nothing is changed until the entire refund fits, including slots freed
	# by the dismantled item. Repeat requests cannot mint resources.
	inventory.load_dict(trial.to_dict())
	return {"ok": true, "item": item_id, "materials": materials}
