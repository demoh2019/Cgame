extends Node2D
## Original top-down apocalypse sandbox vertical slice, made entirely from
## built-in Godot 2D drawing primitives so it requires no external assets.
## The gameplay is local/single-player: red-zone PvP and real player market
## are defined design rules, NOT falsely simulated as a connected MMO.

const Rules = preload("res://rules.gd")
const Survivor = preload("res://survivor.gd")

const SAVE_PATH = "user://afterfall_frontier_v1.json"
const START = Vector2(240.0, 525.0)
const TRADER = Vector2(250.0, 330.0)
const HOME = Vector2(205.0, 645.0)
const MOVE_SPEED = 205.0
const SPRINT_MULTIPLIER = 1.5
const INTERACTION_RANGE = 80.0

const ZONE_COLORS = [
	Color(0.12, 0.23, 0.22),
	Color(0.22, 0.20, 0.15),
	Color(0.23, 0.12, 0.14)
]
const RESOURCE_COLORS = {
	"wood": Color(0.29, 0.77, 0.35),
	"stone": Color(0.70, 0.72, 0.78),
	"fiber": Color(0.60, 0.84, 0.45),
	"herb": Color(0.24, 1.0, 0.62),
	"water": Color(0.26, 0.69, 1.0),
	"food": Color(1.0, 0.77, 0.30),
	"scrap": Color(0.95, 0.52, 0.30),
	"ore": Color(0.72, 0.54, 1.0),
	"alloy": Color(1.0, 0.38, 0.88)
}

var survivor = Survivor.new()
var player_position := START
var resource_nodes: Array[Dictionary] = []
var infected: Array[Dictionary] = []
var lost_bags: Array[Dictionary] = []
var camera: Camera2D
var hud_title: Label
var hud_stats: Label
var hud_inventory: Label
var hud_progress: Label
var hud_help: Label
var hud_notice: Label
var selected_recipe := 0
var attack_cooldown := 0.0
var notice_seconds := 0.0
var rng := RandomNumberGenerator.new()
var recipe_ids := ["axe", "bandage", "pickaxe", "spear", "armor"]


func _ready() -> void:
	name = "AfterfallFrontier"
	rng.seed = 20261119
	_spawn_resources()
	_spawn_infected()
	_setup_camera()
	_setup_hud()
	_notice("Explore, gather with E and craft an axe with C. No external art required.")
	_refresh_hud()


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position = player_position
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(Rules.WORLD_SIZE.x)
	camera.limit_bottom = int(Rules.WORLD_SIZE.y)
	add_child(camera)
	camera.make_current()


func _add_label(parent: Node, name_id: String, content: String, size: int) -> Label:
	var label := Label.new()
	label.name = name_id
	label.text = content
	label.add_theme_color_override("font_color", Color(0.93, 0.96, 0.93))
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.name = "StatusPanel"
	panel.position = Vector2(14.0, 12.0)
	panel.custom_minimum_size = Vector2(565.0, 160.0)
	canvas.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	hud_title = _add_label(stack, "ZoneTitle", "AFTERFALL FRONTIER", 20)
	hud_stats = _add_label(stack, "SurvivalStats", "", 15)
	hud_inventory = _add_label(stack, "Inventory", "", 14)
	hud_progress = _add_label(stack, "Progression", "", 14)

	var controls := PanelContainer.new()
	controls.name = "ControlPanel"
	controls.position = Vector2(14.0, 180.0)
	controls.custom_minimum_size = Vector2(565.0, 115.0)
	canvas.add_child(controls)
	hud_help = _add_label(controls, "Controls", "", 14)
	hud_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var message_panel := PanelContainer.new()
	message_panel.position = Vector2(14.0, 300.0)
	message_panel.custom_minimum_size = Vector2(565.0, 48.0)
	canvas.add_child(message_panel)
	hud_notice = _add_label(message_panel, "EventMessage", "", 15)
	hud_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _spawn_resources() -> void:
	var sets := [
		["wood", "stone", "fiber", "herb", "food", "water"],
		["wood", "stone", "fiber", "herb", "scrap", "ore"],
		["scrap", "ore", "alloy", "herb", "food", "stone"],
	]
	for zone in range(Rules.ZONES.size()):
		var info: Dictionary = Rules.zone_info(zone)
		var choices: Array = sets[zone]
		for i in range(50 if zone == 0 else 65):
			var type_id: String = str(choices[i % choices.size()])
			resource_nodes.append({
				"pos": Vector2(rng.randf_range(float(info["start"]) + 35.0,
						float(info["end"]) - 35.0), rng.randf_range(70.0, 935.0)),
				"item": type_id,
				"remaining": 3 if zone == 0 else 4,
				"respawn": 0.0
			})


func _spawn_infected() -> void:
	for i in range(17):
		var dangerous := i >= 9
		var x := rng.randf_range(1200.0, 1720.0) if dangerous else rng.randf_range(580.0, 1120.0)
		var home_position := Vector2(x, rng.randf_range(100.0, 900.0))
		infected.append({
			"pos": home_position, "home": home_position,
			"health": 52.0 if dangerous else 36.0,
			"cooldown": 0.0, "respawn": 0.0,
			"high_risk": dangerous
		})


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	notice_seconds = maxf(0.0, notice_seconds - delta)
	survivor.tick(delta)
	if survivor.health <= 0.0:
		_handle_death()

	var movement := Vector2(
		(1.0 if Input.is_key_pressed(KEY_D) else 0.0) -
				(1.0 if Input.is_key_pressed(KEY_A) else 0.0),
		(1.0 if Input.is_key_pressed(KEY_S) else 0.0) -
				(1.0 if Input.is_key_pressed(KEY_W) else 0.0)
	)
	movement += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	movement = movement.limit_length(1.0)
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and survivor.stamina > 1.0
	var speed := MOVE_SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
	if sprinting and movement.length_squared() > 0.0:
		survivor.stamina = maxf(0.0, survivor.stamina - delta * 21.0)
	player_position += movement * speed * delta
	player_position = player_position.clamp(Vector2(25.0, 25.0),
			Rules.WORLD_SIZE - Vector2(25.0, 25.0))
	survivor.zone = Rules.zone_index(player_position.x)
	camera.position = player_position
	_update_resource_respawns(delta)
	_update_bag_expiry(delta)
	_update_infected(delta)
	_refresh_hud()
	queue_redraw()


func _update_resource_respawns(delta: float) -> void:
	for i in range(resource_nodes.size()):
		var node: Dictionary = resource_nodes[i]
		if int(node["remaining"]) <= 0:
			node["respawn"] = maxf(0.0, float(node["respawn"]) - delta)
			if float(node["respawn"]) <= 0.0:
				node["remaining"] = 3
			resource_nodes[i] = node


func _update_bag_expiry(delta: float) -> void:
	for i in range(lost_bags.size() - 1, -1, -1):
		lost_bags[i]["ttl"] = float(lost_bags[i]["ttl"]) - delta
		if float(lost_bags[i]["ttl"]) <= 0.0:
			lost_bags.remove_at(i)


func _is_night() -> bool:
	var fraction: float = fposmod(survivor.elapsed_days, 1.0)
	return fraction >= 0.75 or fraction < 0.20


func _update_infected(delta: float) -> void:
	for i in range(infected.size()):
		var z: Dictionary = infected[i]
		z["cooldown"] = maxf(0.0, float(z["cooldown"]) - delta)
		if float(z["health"]) <= 0.0:
			z["respawn"] = maxf(0.0, float(z["respawn"]) - delta)
			if float(z["respawn"]) == 0.0:
				z["health"] = 52.0 if bool(z["high_risk"]) else 36.0
				z["pos"] = z["home"]
			infected[i] = z
			continue
		var pos: Vector2 = z["pos"]
		var distance: float = pos.distance_to(player_position)
		if survivor.zone > 0 and distance < (280.0 if _is_night() else 220.0):
			var direction := (player_position - pos).normalized()
			z["pos"] = pos + direction * (
					(105.0 if bool(z["high_risk"]) else 80.0) *
					(1.15 if _is_night() else 1.0) * delta)
			if distance < 33.0 and float(z["cooldown"]) <= 0.0:
				z["cooldown"] = 1.35
				var base_damage := 16.0 if bool(z["high_risk"]) else 10.0
				var dead: bool = survivor.damage(base_damage * (1.2 if _is_night() else 1.0))
				_notice("Infected hit! Armor reduces damage." if not dead else "You were overwhelmed.")
				if dead:
					_handle_death()
		infected[i] = z


func _handle_death() -> void:
	var at_death := player_position
	var lost: Dictionary = survivor.respawn()
	if not lost.is_empty():
		lost_bags.append({"pos": at_death, "items": lost, "ttl": 240.0})
	player_position = START
	_notice(survivor.last_message)


func _nearest_resource() -> int:
	var best := -1
	var distance := INTERACTION_RANGE
	for i in range(resource_nodes.size()):
		var node: Dictionary = resource_nodes[i]
		if int(node["remaining"]) <= 0:
			continue
		var d: float = (node["pos"] as Vector2).distance_to(player_position)
		if d < distance:
			distance = d
			best = i
	return best


func _gather_or_recover() -> void:
	for i in range(lost_bags.size() - 1, -1, -1):
		if (lost_bags[i]["pos"] as Vector2).distance_to(player_position) <= INTERACTION_RANGE:
			var contents: Dictionary = lost_bags[i]["items"]
			var recovered := 0
			for item in contents.keys():
				var amount: int = int(contents[item])
				if survivor.give(str(item), amount):
					contents.erase(item)
					recovered += amount
			if contents.is_empty():
				lost_bags.remove_at(i)
			else:
				lost_bags[i]["items"] = contents
			_notice("Recovered %d items from your dropped backpack" % recovered)
			return
	var index := _nearest_resource()
	if index < 0:
		_notice("Move closer to a resource node or your dropped backpack")
		return
	var resource: Dictionary = resource_nodes[index]
	var result: String = survivor.gather(str(resource["item"]))
	if result.begins_with("+"):
		resource["remaining"] = int(resource["remaining"]) - 1
		if int(resource["remaining"]) == 0:
			resource["respawn"] = 24.0
		resource_nodes[index] = resource
	_notice(result)


func _attack() -> void:
	if attack_cooldown > 0.0 or survivor.stamina < 10.0:
		return
	attack_cooldown = 0.48
	survivor.stamina -= 10.0
	var closest := -1
	var distance := 88.0
	for i in range(infected.size()):
		var z: Dictionary = infected[i]
		if float(z["health"]) <= 0.0:
			continue
		var d: float = (z["pos"] as Vector2).distance_to(player_position)
		if d < distance:
			distance = d
			closest = i
	if closest == -1:
		_notice("Attack missed. Move within melee range.")
		return
	var z: Dictionary = infected[closest]
	z["health"] = float(z["health"]) - survivor.attack_damage()
	if float(z["health"]) <= 0.0:
		z["respawn"] = 18.0
		survivor.defeated_enemy()
		var reward: String = "alloy" if bool(z["high_risk"]) and rng.randf() < 0.30 else "scrap"
		if survivor.give(reward, 1):
			_notice("Infected defeated! +1 %s | Combat XP +12" % reward)
		else:
			_notice("Infected defeated! Backpack too heavy for loot.")
	else:
		_notice("Hit infected for %d damage" % int(survivor.attack_damage()))
	infected[closest] = z


func _near_trader() -> bool:
	return player_position.distance_to(TRADER) < 100.0


func _near_home() -> bool:
	return player_position.distance_to(HOME) < 110.0


func _near_workbench() -> bool:
	return _near_trader() or (survivor.shelter_level > 0 and _near_home())


func _store_stash() -> void:
	if not _near_home():
		_notice("Visit your shelter to store items")
		return
	for item in ["alloy", "ore", "scrap", "wood", "stone"]:
		if survivor.count(item) > 0:
			_notice("Stored 1 %s" % item if survivor.store(item, 1) else "Build shelter first (B)")
			return
	_notice("No gathered resources to store")


func _withdraw_stash() -> void:
	if not _near_home():
		_notice("Visit your shelter to retrieve items")
		return
	for item in ["alloy", "ore", "scrap", "wood", "stone"]:
		if int(survivor.stash.get(item, 0)) > 0:
			_notice("Retrieved 1 %s" % item if survivor.withdraw(item, 1) else "Bag full")
			return
	_notice("Stash is empty")


func _notice(content: String) -> void:
	if hud_notice != null:
		hud_notice.text = content
	notice_seconds = 5.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_E:
			_gather_or_recover()
		KEY_F:
			_attack()
		KEY_TAB:
			selected_recipe = (selected_recipe + 1) % recipe_ids.size()
			_notice("Selected craft: %s" % recipe_ids[selected_recipe])
		KEY_C:
			_notice(survivor.craft(recipe_ids[selected_recipe], _near_workbench()))
		KEY_B:
			_notice(survivor.build_shelter(_near_home()))
		KEY_T:
			var sold := false
			for item in ["alloy", "ore", "scrap", "fiber", "wood", "stone"]:
				if survivor.count(item) > 0:
					_notice(survivor.sell(item, 1, _near_trader()))
					sold = true
					break
			if not sold:
				_notice("No sellable resources in your bag")
		KEY_Y:
			_notice(survivor.buy("water", 1, _near_trader()))
		KEY_K:
			_store_stash()
		KEY_L:
			_withdraw_stash()
		KEY_R:
			_notice(survivor.consume("bandage"))
		KEY_H:
			_notice(survivor.consume("food"))
		KEY_J:
			_notice(survivor.consume("water"))
		KEY_F5:
			_save_profile()
		KEY_F9:
			_load_profile()


func _save_profile() -> void:
	var content := survivor.snapshot()
	content["player_x"] = player_position.x
	content["player_y"] = player_position.y
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_notice("Save failed (user:// unavailable)")
		return
	file.store_string(JSON.stringify(content))
	file.close()
	_notice("Survivor, professions, shelter and inventory saved")


func _load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_notice("No saved survivor yet (F5)")
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_notice("Cannot read save")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not survivor.import_snapshot(parsed):
		_notice("Invalid or incompatible save, current game preserved")
		return
	player_position = Vector2(
			clampf(float(parsed.get("player_x", START.x)), 25.0, Rules.WORLD_SIZE.x - 25.0),
			clampf(float(parsed.get("player_y", START.y)), 25.0, Rules.WORLD_SIZE.y - 25.0))
	survivor.zone = Rules.zone_index(player_position.x)
	_notice("Survivor loaded")


func _refresh_hud() -> void:
	if hud_title == null:
		return
	var zone_info: Dictionary = Rules.zone_info(survivor.zone)
	var danger: String = "FULL LOOT" if bool(zone_info["full_loot"]) else (
			"PVP planned / partial loss" if bool(zone_info["pvp"]) else "SAFE / no loss")
	hud_title.text = "AFTERFALL FRONTIER | %s" % str(zone_info["name"])
	hud_stats.text = "HP %d  Food %d  Water %d  Energy %d | Coins %d | Day %d %s | %s" % [
		int(survivor.health), int(survivor.hunger), int(survivor.thirst),
		int(survivor.stamina), survivor.coins, 1 + int(survivor.elapsed_days),
		"NIGHT" if _is_night() else "DAY", danger
	]
	var item_bits := PackedStringArray()
	for item_id in survivor.inventory.keys():
		item_bits.append("%s:%d" % [item_id, survivor.count(str(item_id))])
	item_bits.sort()
	hud_inventory.text = "Bag (%d/%d): %s" % [
		survivor.total_weight(), Rules.MAX_CARRY_WEIGHT, " ".join(item_bits)
	]
	hud_progress.text = "Gather Lv%d | Craft Lv%d | Combat Lv%d | Shelter Lv%d | Infected %d | Recipe [%s]" % [
		Rules.profession_level(int(survivor.skills["gathering"])),
		Rules.profession_level(int(survivor.skills["crafting"])),
		Rules.profession_level(int(survivor.skills["combat"])),
		survivor.shelter_level, survivor.infected_kills, recipe_ids[selected_recipe]
	]
	hud_help.text = "WASD/arrows: move | SHIFT: sprint | E: gather/recover | F: attack\n" + \
			"TAB: next recipe | C: craft | B: shelter | K/L: stash\n" + \
			"T: sell | Y: buy water at trader | H/J/R: eat/drink/heal\n" + \
			"F5: save | F9: load | VENTURE EAST FOR RARE RESOURCES"
	if notice_seconds <= 0.0:
		hud_notice.text = "Build at home • Craft near the workbench • Higher danger pays more"


func _draw() -> void:
	for z in range(Rules.ZONES.size()):
		var info: Dictionary = Rules.zone_info(z)
		draw_rect(Rect2(Vector2(float(info["start"]), 0.0),
				Vector2(float(info["end"]) - float(info["start"]), Rules.WORLD_SIZE.y)),
				ZONE_COLORS[z], true)
	for x in range(0, 1801, 80):
		draw_line(Vector2(x, 0), Vector2(x, Rules.WORLD_SIZE.y),
				Color(1, 1, 1, 0.045), 1.0)
	for y in range(0, 1001, 80):
		draw_line(Vector2(0, y), Vector2(Rules.WORLD_SIZE.x, y),
				Color(1, 1, 1, 0.045), 1.0)
	draw_line(Vector2(520, 0), Vector2(520, 1000), Color(0.96, 0.74, 0.23), 5)
	draw_line(Vector2(1160, 0), Vector2(1160, 1000), Color(0.99, 0.23, 0.25), 5)
	for x in [90, 650, 1260]:
		draw_string(ThemeDB.fallback_font, Vector2(x, 65),
				"HAVEN" if x == 90 else ("FRONTIER" if x == 650 else "DEADLANDS"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.55))
	# Home shelter and Haven trader/workbench are explicit interactables.
	draw_rect(Rect2(HOME - Vector2(74, 60), Vector2(148, 120)),
			Color(0.24, 0.53, 0.53), true)
	draw_rect(Rect2(TRADER - Vector2(55, 40), Vector2(110, 80)),
			Color(0.78, 0.58, 0.19), true)
	draw_string(ThemeDB.fallback_font, HOME + Vector2(-35, 6),
			"SHELTER %d" % survivor.shelter_level,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(ThemeDB.fallback_font, TRADER + Vector2(-40, 4),
			"MARKET", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)

	for r in resource_nodes:
		if int(r["remaining"]) <= 0:
			continue
		var pos: Vector2 = r["pos"]
		var item: String = str(r["item"])
		draw_circle(pos, 11, RESOURCE_COLORS.get(item, Color.WHITE))
		draw_arc(pos, 13, 0, TAU, 12, Color(0.04, 0.04, 0.04, 0.7), 2)
		if pos.distance_to(player_position) < 95:
			draw_string(ThemeDB.fallback_font, pos + Vector2(-22, -17), item,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	for bag in lost_bags:
		var pos: Vector2 = bag["pos"]
		draw_rect(Rect2(pos - Vector2(13, 10), Vector2(26, 20)), Color(1, 0.82, 0.25), true)
	for zombie in infected:
		if float(zombie["health"]) <= 0.0:
			continue
		var pos: Vector2 = zombie["pos"]
		draw_circle(pos, 17, Color(0.92, 0.30, 0.32) if bool(zombie["high_risk"]) else Color(0.69, 0.78, 0.26))
		draw_circle(pos + Vector2(-5, -3), 2.5, Color(0.15, 0.16, 0.13))
		draw_circle(pos + Vector2(5, -3), 2.5, Color(0.15, 0.16, 0.13))
		draw_rect(Rect2(pos + Vector2(-17, -25), Vector2(34.0 * minf(1.0,
				float(zombie["health"]) / (52.0 if bool(zombie["high_risk"]) else 36.0)), 3)),
				Color(1, 0.3, 0.2), true)
	# Night reduces visibility on the map without obscuring CanvasLayer UI.
	# NPCs use the same phase for perception and attack difficulty.
	if _is_night():
		draw_rect(Rect2(Vector2.ZERO, Rules.WORLD_SIZE),
				Color(0.02, 0.06, 0.13, 0.47), true)
	draw_circle(player_position, 16, Color(0.20, 0.77, 1.0))
	draw_circle(player_position + Vector2(-4, -3), 3, Color.WHITE)
	draw_circle(player_position + Vector2(4, -3), 3, Color.WHITE)
	draw_arc(player_position, INTERACTION_RANGE, 0, TAU, 64,
			Color(0.37, 0.89, 1.0, 0.13), 1)
