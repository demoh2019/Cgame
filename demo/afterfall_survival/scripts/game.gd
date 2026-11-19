extends Node2D
## Original top-down survival RPG vertical slice.
## Uses stock Godot 4.x APIs. No copied game assets, network claims or engine patches.

const Rules = preload("res://scripts/rules.gd")
const Survivor = preload("res://scripts/survivor.gd")
const Infected = preload("res://scripts/infected.gd")

const SPAWN := Vector2(970, 730)
const RESOURCE_COLORS: Dictionary = {
	"wood": Color(0.54, 0.78, 0.39),
	"stone": Color(0.55, 0.65, 0.66),
	"scrap": Color(0.95, 0.62, 0.35),
	"cloth": Color(0.80, 0.68, 0.88),
	"berries": Color(0.84, 0.23, 0.40),
	"water": Color(0.32, 0.73, 0.98),
}
const RESOURCE_KINDS: Array[String] = ["wood", "stone", "scrap", "cloth", "berries", "water"]
const RECIPE_NAMES: Array[String] = ["spear", "axe", "bandage", "campfire"]

var map_size: Vector2 = Vector2(2000, 1500)
var player = null
var enemies: Array = []
var resource_nodes: Array[Dictionary] = []
var safe_camps: Array[Vector2] = [SPAWN]
var inventory: Dictionary = {
	"wood": 0, "stone": 0, "scrap": 0, "cloth": 0,
	"berries": 2, "water": 2, "spear": 0, "axe": 0, "bandage": 0,
}
var hp: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var world_age: float = 0.0
var attack_wait: float = 0.0
var spawn_wait: float = 0.0
var ui_wait: float = 0.0
var combat_xp: int = 0
var gathering_xp: int = 0
var collected_wood: int = 0
var collected_scrap: int = 0
var kills: int = 0
var selected_recipe: int = 0
var message: String = "Find supplies, build a camp and survive the infected."
var message_wait: float = 8.0
var hud: Label
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 246813579
	_generate_resources()
	player = Survivor.new()
	player.game = self
	player.position = SPAWN
	add_child(player)
	for i in range(14):
		_spawn_infected()
	_make_hud()
	queue_redraw()


func _generate_resources() -> void:
	# Accessible resources close to spawn keep the first minute playable.
	for i in range(RESOURCE_KINDS.size()):
		resource_nodes.append({
			"kind": RESOURCE_KINDS[i],
			"position": SPAWN + Vector2(56.0, 0.0).rotated(float(i) * TAU / 6.0),
			"remaining": 4
		})
	for i in range(170):
		var point := Vector2(rng.randf_range(40, map_size.x - 40), rng.randf_range(40, map_size.y - 40))
		if point.distance_to(SPAWN) < 100.0:
			continue
		resource_nodes.append({
			"kind": RESOURCE_KINDS[i % RESOURCE_KINDS.size()],
			"position": point,
			"remaining": rng.randi_range(1, 4)
		})


func _spawn_infected() -> void:
	for attempt in range(32):
		var point := Vector2(rng.randf_range(25, map_size.x - 25), rng.randf_range(25, map_size.y - 25))
		if point.distance_to(player.position) < 270.0 or is_safe_at(point):
			continue
		var infected = Infected.new()
		infected.game = self
		infected.target = player
		infected.position = point
		add_child(infected)
		enemies.append(infected)
		return


func _make_hud() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var box := PanelContainer.new()
	box.position = Vector2(15, 15)
	box.custom_minimum_size = Vector2(500, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(margin)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 16)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hud)
	_update_hud()


func _process(delta: float) -> void:
	world_age += delta
	hunger = maxf(0.0, hunger - delta * 0.19)
	thirst = maxf(0.0, thirst - delta * 0.27)
	attack_wait = maxf(0.0, attack_wait - delta)
	if hunger <= 0.0 or thirst <= 0.0:
		apply_player_damage(3.5 * delta)
	spawn_wait += delta
	if spawn_wait >= (12.0 if is_night() else 21.0):
		spawn_wait = 0.0
		enemies = enemies.filter(func(enemy): return is_instance_valid(enemy) and not enemy.is_queued_for_deletion())
		if enemies.size() < 23:
			_spawn_infected()
	message_wait = maxf(0.0, message_wait - delta)
	ui_wait += delta
	if ui_wait >= 0.17:
		ui_wait = 0.0
		_update_hud()
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_attack()
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_E:
			try_gather()
		KEY_C:
			try_craft()
		KEY_TAB:
			selected_recipe = (selected_recipe + 1) % RECIPE_NAMES.size()
			_set_message("Selected recipe: " + RECIPE_NAMES[selected_recipe])
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			try_attack()
		KEY_1:
			try_equip("club")
		KEY_2:
			try_equip("spear")
		KEY_3:
			try_equip("axe")
		KEY_F:
			use_bandage()
		KEY_H:
			consume("berries")
		KEY_J:
			consume("water")


func try_gather() -> bool:
	var closest_index: int = -1
	var closest: float = 85.0
	for i in range(resource_nodes.size()):
		var distance: float = player.position.distance_to(resource_nodes[i]["position"])
		if distance < closest:
			closest_index = i
			closest = distance
	if closest_index == -1:
		_set_message("Move closer to a resource marker, then press E.")
		return false
	var node: Dictionary = resource_nodes[closest_index]
	var kind: String = node["kind"]
	var yield_amount: int = 2 if get_gathering_level() >= 3 else 1
	inventory[kind] = int(inventory.get(kind, 0)) + yield_amount
	gathering_xp += 2
	if kind == "wood":
		collected_wood += yield_amount
	if kind == "scrap":
		collected_scrap += yield_amount
	node["remaining"] = int(node["remaining"]) - 1
	if int(node["remaining"]) <= 0:
		resource_nodes.remove_at(closest_index)
	else:
		resource_nodes[closest_index] = node
	_set_message("Gathered " + kind + " x" + str(yield_amount))
	queue_redraw()
	return true


func try_craft() -> bool:
	var recipe: String = RECIPE_NAMES[selected_recipe]
	if not Rules.craft(inventory, recipe):
		_set_message("Missing materials for " + recipe + ": " + str(Rules.RECIPES[recipe]))
		return false
	if recipe == "campfire":
		inventory["campfire"] = int(inventory["campfire"]) - 1
		safe_camps.append(player.position)
		_set_message("New safe camp established. Enemies cannot attack inside it.")
	elif Rules.WEAPONS.has(recipe):
		player.equip(recipe)
		_set_message("Crafted and equipped: " + recipe)
	else:
		_set_message("Crafted: " + recipe)
	queue_redraw()
	return true


func try_equip(weapon: String) -> bool:
	if weapon != "club" and int(inventory.get(weapon, 0)) <= 0:
		_set_message("Craft a " + weapon + " first.")
		return false
	player.equip(weapon)
	_set_message("Equipped: " + weapon)
	return true


func try_attack() -> bool:
	if attack_wait > 0.0:
		return false
	var weapon: String = player.active_weapon
	var stats: Dictionary = Rules.WEAPONS[weapon]
	var attack_range: float = float(stats["range"])
	var target = null
	var shortest: float = attack_range
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var distance: float = enemy.position.distance_to(player.position)
		if distance < shortest:
			target = enemy
			shortest = distance
	attack_wait = float(stats["cooldown"])
	if target == null:
		_set_message("No infected within " + str(int(attack_range)) + "m of your weapon.")
		return false
	combat_xp += 2
	target.take_hit(Rules.weapon_power(weapon, get_combat_level()))
	_set_message("Hit infected with " + weapon + "!")
	return true


func infected_defeated(_position: Vector2) -> void:
	kills += 1
	combat_xp += 6
	if rng.randf() < 0.45:
		inventory["scrap"] = int(inventory.get("scrap", 0)) + 1
	_set_message("Infected defeated. +Combat XP")


func apply_player_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_respawn()


func _respawn() -> void:
	# First playable risk rule: lose half of unsecured materials on death.
	var lost: Dictionary = Rules.lose_unsecured_supplies(inventory)
	player.position = SPAWN
	hp = 80.0
	hunger = 65.0
	thirst = 65.0
	_set_message("Rescued at the refuge. Lost unsecured supplies: " + str(lost))


func use_bandage() -> bool:
	if int(inventory.get("bandage", 0)) < 1:
		_set_message("No bandages; craft them with C.")
		return false
	if hp >= 100.0:
		return false
	inventory["bandage"] = int(inventory["bandage"]) - 1
	hp = minf(100.0, hp + 36.0)
	_set_message("Used a bandage.")
	return true


func consume(kind: String) -> bool:
	if kind != "berries" and kind != "water":
		return false
	if int(inventory.get(kind, 0)) < 1:
		_set_message("No " + kind + " left. Search the world.")
		return false
	inventory[kind] = int(inventory[kind]) - 1
	if kind == "berries":
		hunger = minf(100.0, hunger + 35.0)
	else:
		thirst = minf(100.0, thirst + 45.0)
	_set_message("Consumed " + kind)
	return true


func get_movement_multiplier() -> float:
	return Rules.survival_speed_multiplier(hunger, thirst)


func is_night() -> bool:
	return fposmod(world_age, 240.0) >= 155.0


func is_safe_at(point: Vector2) -> bool:
	for camp in safe_camps:
		if camp.distance_to(point) < 130.0:
			return true
	return false


func get_combat_level() -> int:
	return 1 + combat_xp / 22


func get_gathering_level() -> int:
	return 1 + gathering_xp / 20


func get_quest_text() -> String:
	if collected_wood < 4:
		return "QUEST: gather wood (" + str(collected_wood) + "/4)"
	if collected_scrap < 2:
		return "QUEST: salvage scrap (" + str(collected_scrap) + "/2)"
	if int(inventory["spear"]) <= 0:
		return "QUEST: craft a spear (TAB select, C craft)"
	if safe_camps.size() < 2:
		return "QUEST: establish a second campfire"
	if kills < 3:
		return "QUEST: defeat infected (" + str(kills) + "/3)"
	return "QUEST COMPLETE: start exploring the wasteland!"


func _set_message(text: String) -> void:
	message = text
	message_wait = 4.0
	_update_hud()


func _update_hud() -> void:
	if hud == null or player == null:
		return
	var supplies: Array[String] = []
	for kind in Rules.DROPPABLE:
		supplies.append(kind + ":" + str(inventory.get(kind, 0)))
	var current_recipe: String = RECIPE_NAMES[selected_recipe]
	hud.text = "AFTERFALL FRONTIER  |  " + ("NIGHT - HIGH RISK" if is_night() else "DAY") + "\n"
	hud.text += "HP: %d   Hunger: %d   Thirst: %d\n" % [int(hp), int(hunger), int(thirst)]
	hud.text += "Weapon: %s   Combat Lv.%d   Gathering Lv.%d   Kills: %d\n" % [
		player.active_weapon, get_combat_level(), get_gathering_level(), kills]
	hud.text += "Supplies: " + "   ".join(supplies) + "\n"
	hud.text += "Craft: %s (%s)   Bandages: %d\n" % [
		current_recipe, str(Rules.RECIPES[current_recipe]), int(inventory.get("bandage", 0))]
	hud.text += get_quest_text() + "\n"
	hud.text += "WASD move | E gather | TAB recipe | C craft | SPACE/click attack\n"
	hud.text += "1 club | 2 spear | 3 axe | F bandage | H eat | J drink\n"
	if message_wait > 0.0:
		hud.text += "> " + message


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.12, 0.18, 0.17))
	# Scorched roads and warehouse remnants make a navigable, asset-free map.
	draw_rect(Rect2(0, 670, map_size.x, 100), Color(0.19, 0.21, 0.20))
	draw_rect(Rect2(1350, 0, 85, map_size.y), Color(0.18, 0.20, 0.19))
	for i in range(6):
		var ruin := Rect2(220 + i * 270, 150 + (i % 3) * 380, 100, 75)
		draw_rect(ruin, Color(0.25, 0.29, 0.27), true)
		draw_rect(ruin, Color(0.39, 0.43, 0.39), false, 3.0)
	draw_circle(Vector2(1640, 1190), 145.0, Color(0.11, 0.30, 0.37))
	for camp in safe_camps:
		draw_circle(camp, 130.0, Color(0.20, 0.47, 0.38, 0.19))
		draw_arc(camp, 130.0, 0.0, TAU, 72, Color(0.36, 0.78, 0.60, 0.6), 2.0)
		draw_circle(camp, 12.0, Color(0.93, 0.72, 0.32))
	for resource in resource_nodes:
		var point: Vector2 = resource["position"]
		var color: Color = RESOURCE_COLORS[resource["kind"]]
		draw_circle(point + Vector2(1, 2), 11.0, Color(0, 0, 0, 0.22))
		draw_circle(point, 9.0, color)
		draw_arc(point, 12.0, 0.0, TAU, 16, color.darkened(0.25), 1.3)
	if is_night():
		draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.02, 0.04, 0.11, 0.26))
