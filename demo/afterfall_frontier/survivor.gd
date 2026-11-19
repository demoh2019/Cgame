extends RefCounted
## Pure survival + classless progression domain model, independent of rendering.
## The offline prototype has a local trader, NOT a multiplayer market.

const Rules = preload("res://rules.gd")

var inventory: Dictionary = {"wood": 4, "stone": 2, "fiber": 2, "water": 2, "food": 2}
var stash: Dictionary = {}
var skills: Dictionary = {"gathering": 0, "crafting": 0, "combat": 0}
var health := 100.0
var hunger := 90.0
var thirst := 90.0
var stamina := 100.0
var coins := 12
var shelter_level := 0
var zone := 0
var elapsed_days := 0.35
var deaths := 0
var infected_kills := 0
var last_message := ""


func count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func total_weight() -> int:
	var weight := 0
	for key in inventory:
		weight += Rules.item_weight(str(key)) * int(inventory[key])
	return weight


func give(item_id: String, quantity: int) -> bool:
	if not Rules.ITEMS.has(item_id) or quantity <= 0:
		return false
	if count(item_id) + quantity > Rules.STACK_LIMIT:
		return false
	if total_weight() + Rules.item_weight(item_id) * quantity > Rules.MAX_CARRY_WEIGHT:
		return false
	inventory[item_id] = count(item_id) + quantity
	return true


func remove(item_id: String, quantity: int) -> bool:
	if quantity <= 0 or count(item_id) < quantity:
		return false
	var remaining := count(item_id) - quantity
	if remaining == 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = remaining
	return true


func gather(item_id: String) -> String:
	if not Rules.can_gather(item_id, inventory):
		last_message = "Requires pickaxe" if item_id in ["ore", "alloy"] else "Cannot collect"
		return last_message
	var quantity: int = Rules.gathering_yield(zone, int(skills["gathering"]))
	if item_id in ["wood", "fiber"] and count("axe") > 0:
		quantity += 1
	if not give(item_id, quantity):
		last_message = "Bag full (90 weight max / 99 per stack)"
		return last_message
	skills["gathering"] = int(skills["gathering"]) + 3 * quantity
	last_message = "+%d %s | Gathering Lv%d" % [
		quantity, str(Rules.ITEMS[item_id]["name"]),
		Rules.profession_level(int(skills["gathering"]))
	]
	return last_message


func craft(recipe_id: String, near_workbench: bool) -> String:
	if not Rules.RECIPES.has(recipe_id):
		last_message = "Unknown recipe"
		return last_message
	var recipe: Dictionary = Rules.RECIPES[recipe_id]
	if bool(recipe["station"]) and not near_workbench:
		last_message = "Requires settlement workbench / shelter"
		return last_message
	var costs: Dictionary = recipe["cost"]
	for ingredient in costs:
		if count(str(ingredient)) < int(costs[ingredient]):
			last_message = "Missing %s (%d needed)" % [ingredient, int(costs[ingredient])]
			return last_message
	# The output can be carried after consuming its ingredients.
	var new_weight := total_weight() + Rules.item_weight(recipe_id)
	for ingredient in costs:
		new_weight -= Rules.item_weight(str(ingredient)) * int(costs[ingredient])
	if count(recipe_id) >= Rules.STACK_LIMIT or new_weight > Rules.MAX_CARRY_WEIGHT:
		last_message = "No room for crafted equipment"
		return last_message
	for ingredient in costs:
		remove(str(ingredient), int(costs[ingredient]))
	give(recipe_id, 1)
	skills["crafting"] = int(skills["crafting"]) + int(recipe["xp"])
	last_message = "Crafted %s | Crafting Lv%d" % [
		str(Rules.ITEMS[recipe_id]["name"]),
		Rules.profession_level(int(skills["crafting"]))
	]
	return last_message


func build_shelter(in_haven: bool) -> String:
	if not in_haven:
		last_message = "Build in the settlement to protect your stash"
		return last_message
	if shelter_level >= 3:
		last_message = "Shelter fully upgraded"
		return last_message
	var factor := shelter_level + 1
	if count("wood") < Rules.BASE_WOOD * factor or count("stone") < Rules.BASE_STONE * factor:
		last_message = "Shelter Lv%d needs %d wood + %d stone" % [
			shelter_level + 1, Rules.BASE_WOOD * factor, Rules.BASE_STONE * factor
		]
		return last_message
	remove("wood", Rules.BASE_WOOD * factor)
	remove("stone", Rules.BASE_STONE * factor)
	shelter_level += 1
	skills["crafting"] = int(skills["crafting"]) + 15 * factor
	last_message = "Shelter upgraded to level %d" % shelter_level
	return last_message


func store(item_id: String, quantity: int) -> bool:
	if shelter_level == 0 or quantity <= 0 or count(item_id) < quantity:
		return false
	if int(stash.get(item_id, 0)) + quantity > Rules.STACK_LIMIT:
		return false
	if not remove(item_id, quantity):
		return false
	stash[item_id] = int(stash.get(item_id, 0)) + quantity
	return true


func withdraw(item_id: String, quantity: int) -> bool:
	if shelter_level == 0 or quantity <= 0 or int(stash.get(item_id, 0)) < quantity:
		return false
	if not give(item_id, quantity):
		return false
	stash[item_id] = int(stash[item_id]) - quantity
	if int(stash[item_id]) == 0:
		stash.erase(item_id)
	return true


func sell(item_id: String, quantity: int, at_settlement: bool) -> String:
	if not at_settlement:
		last_message = "Trade only at the Haven market"
	elif item_id in ["axe", "pickaxe", "spear", "armor"] or Rules.item_value(item_id) <= 0:
		last_message = "Market buys gathered resources and consumables"
	elif quantity <= 0 or count(item_id) < quantity:
		last_message = "Not enough items to sell"
	elif remove(item_id, quantity):
		var gross := quantity * Rules.item_value(item_id)
		var payout := maxi(1, gross - int(ceil(gross * 0.1)))
		coins += payout
		last_message = "Sold %d %s for %d coins (10%% tax)" % [quantity, item_id, payout]
	return last_message


func buy(item_id: String, quantity: int, at_settlement: bool) -> String:
	if not at_settlement:
		last_message = "Trade only at the Haven market"
	elif not item_id in ["water", "food", "fiber", "herb"]:
		last_message = "This vendor only sells essential supplies"
	elif quantity <= 0:
		last_message = "Invalid quantity"
	else:
		var price := Rules.item_value(item_id) * 2 * quantity
		if coins < price:
			last_message = "Need %d coins" % price
		elif not give(item_id, quantity):
			last_message = "Bag full"
		else:
			coins -= price
			last_message = "Bought %d %s for %d coins" % [quantity, item_id, price]
	return last_message


func consume(item_id: String) -> String:
	if item_id == "food" and remove("food", 1):
		hunger = minf(100.0, hunger + 36.0)
		last_message = "Ate rations (+36 hunger)"
	elif item_id == "water" and remove("water", 1):
		thirst = minf(100.0, thirst + 45.0)
		last_message = "Drank clean water (+45 thirst)"
	elif item_id == "bandage" and remove("bandage", 1):
		health = minf(100.0, health + 40.0)
		last_message = "Applied bandage (+40 health)"
	else:
		last_message = "No %s in inventory" % item_id
	return last_message


func damage(amount: float) -> bool:
	if amount <= 0.0 or not is_finite(amount):
		return false
	health = maxf(0.0, health - amount * (0.65 if count("armor") > 0 else 1.0))
	return health <= 0.0


func attack_damage() -> float:
	return 26.0 if count("spear") > 0 else (18.0 if count("axe") > 0 else 9.0)


func defeated_enemy() -> void:
	infected_kills += 1
	skills["combat"] = int(skills["combat"]) + 12


func respawn() -> Dictionary:
	var dropped := {}
	if zone == 1:
		# Contested zone: lose roughly half the carried stacks.
		for item_id in inventory.keys():
			var amount: int = int(ceil(float(inventory[item_id]) * 0.5))
			if amount > 0:
				dropped[item_id] = amount
	elif zone == 2:
		# High-risk zone: all carried items, including equipped gear.
		dropped = inventory.duplicate(true)
	for item_id in dropped:
		remove(str(item_id), int(dropped[item_id]))
	health = 100.0
	hunger = 60.0
	thirst = 60.0
	stamina = 100.0
	deaths += 1
	zone = 0
	last_message = "Respawned at Haven | Lost %d carried stacks | Stash is safe" % dropped.size()
	return dropped


func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# Day length is 20 real minutes in the prototype.
	elapsed_days += delta / 1200.0
	hunger = maxf(0.0, hunger - delta * 0.035)
	thirst = maxf(0.0, thirst - delta * 0.055)
	stamina = minf(100.0, stamina + delta * 13.0)
	if hunger <= 0.0 or thirst <= 0.0:
		health = maxf(0.0, health - 3.0 * delta)


func snapshot() -> Dictionary:
	return {
		"version": 1, "inventory": inventory.duplicate(true),
		"stash": stash.duplicate(true), "skills": skills.duplicate(true),
		"health": health, "hunger": hunger, "thirst": thirst, "stamina": stamina,
		"coins": coins, "shelter_level": shelter_level, "zone": zone,
		"elapsed_days": elapsed_days, "deaths": deaths,
		"infected_kills": infected_kills
	}


func import_snapshot(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		return false
	var bag: Dictionary = Rules.sanitize_bag(data.get("inventory", {}))
	var saved_stash: Dictionary = Rules.sanitize_bag(data.get("stash", {}))
	var weight := 0
	for item_id in bag:
		weight += Rules.item_weight(str(item_id)) * int(bag[item_id])
	if weight > Rules.MAX_CARRY_WEIGHT:
		return false
	var new_skills := {}
	var raw_skills: Variant = data.get("skills", {})
	if typeof(raw_skills) != TYPE_DICTIONARY:
		return false
	for profession in ["gathering", "crafting", "combat"]:
		new_skills[profession] = clampi(int(raw_skills.get(profession, 0)), 0, 1000000)
	inventory = bag
	stash = saved_stash
	skills = new_skills
	health = clampf(float(data.get("health", 100.0)), 0.0, 100.0)
	hunger = clampf(float(data.get("hunger", 90.0)), 0.0, 100.0)
	thirst = clampf(float(data.get("thirst", 90.0)), 0.0, 100.0)
	stamina = clampf(float(data.get("stamina", 100.0)), 0.0, 100.0)
	coins = clampi(int(data.get("coins", 12)), 0, 1000000)
	shelter_level = clampi(int(data.get("shelter_level", 0)), 0, 3)
	zone = clampi(int(data.get("zone", 0)), 0, 2)
	elapsed_days = clampf(float(data.get("elapsed_days", 0.35)), 0.0, 100000.0)
	deaths = clampi(int(data.get("deaths", 0)), 0, 1000000)
	infected_kills = clampi(int(data.get("infected_kills", 0)), 0, 1000000)
	return true
