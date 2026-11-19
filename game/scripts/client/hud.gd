extends CanvasLayer
## All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")

var client
var _bars: Dictionary = {}
var _zone_label: Label
var _info_label: Label
var _prompt: Label
var _log: Label
var _inventory_panel: PanelContainer
var _inventory_grid: GridContainer
var _stash_grid: GridContainer
var _craft_panel: PanelContainer
var _craft_list: VBoxContainer
var _death: Label
var _equipped: Label
var _log_lines: Array[String] = []
var _craft_signature: String = ""
var _inventory_signature: String = ""


func setup(p_client) -> void:
	client = p_client
	client.event_received.connect(_on_event)
	client.net.result_received.connect(_on_result)
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var top_left := VBoxContainer.new()
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top_left)
	for entry in [["health", Color(0.85, 0.2, 0.2)], ["hunger", Color(0.9, 0.65, 0.2)], ["thirst", Color(0.25, 0.55, 0.95)]]:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240, 18)
		bar.max_value = 100.0
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = entry[1]
		bar.add_theme_stylebox_override("fill", fill)
		var label := Label.new()
		label.text = String(entry[0]).capitalize()
		label.add_theme_font_size_override("font_size", 12)
		top_left.add_child(label)
		top_left.add_child(bar)
		_bars[entry[0]] = bar
	_equipped = Label.new()
	top_left.add_child(_equipped)

	var top_right := VBoxContainer.new()
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top_right)
	_zone_label = Label.new()
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zone_label.add_theme_font_size_override("font_size", 20)
	top_right.add_child(_zone_label)
	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right.add_child(_info_label)

	_log = Label.new()
	_log.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_log.size_flags_vertical = Control.SIZE_SHRINK_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_log)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-200, -140)
	_prompt.size = Vector2(400, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	_inventory_panel = PanelContainer.new()
	_inventory_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_inventory_panel.position = Vector2(-330, -200)
	_inventory_panel.visible = false
	add_child(_inventory_panel)
	var inventory_box := VBoxContainer.new()
	_inventory_panel.add_child(inventory_box)
	var inventory_title := Label.new()
	inventory_title.text = "Inventory: click = use/equip, right-click = bank one (at hub workbench)"
	inventory_box.add_child(inventory_title)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 4
	inventory_box.add_child(_inventory_grid)
	var stash_title := Label.new()
	stash_title.text = "Protected stash: click an item to withdraw one at the workbench"
	inventory_box.add_child(stash_title)
	var stash_scroll := ScrollContainer.new()
	stash_scroll.custom_minimum_size = Vector2(400, 110)
	inventory_box.add_child(stash_scroll)
	_stash_grid = GridContainer.new()
	_stash_grid.columns = 4
	stash_scroll.add_child(_stash_grid)

	_craft_panel = PanelContainer.new()
	_craft_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_craft_panel.position = Vector2(14, -220)
	_craft_panel.visible = false
	add_child(_craft_panel)
	var craft_box := VBoxContainer.new()
	_craft_panel.add_child(craft_box)
	var craft_title := Label.new()
	craft_title.text = "Crafting (workbench near the hub fountain: most recipes need it)"
	craft_box.add_child(craft_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 380)
	craft_box.add_child(scroll)
	_craft_list = VBoxContainer.new()
	scroll.add_child(_craft_list)

	_death = Label.new()
	_death.text = "YOU DIED\nEverything you carried was dropped where you fell."
	_death.add_theme_font_size_override("font_size", 28)
	_death.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.position = Vector2(-300, -60)
	_death.size = Vector2(600, 120)
	_death.visible = false
	add_child(_death)


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible


func toggle_crafting() -> void:
	_craft_panel.visible = not _craft_panel.visible


func is_menu_open() -> bool:
	return _inventory_panel.visible or _craft_panel.visible


func set_prompt(text: String) -> void:
	_prompt.text = text


func say(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > 7:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		"gathered":
			say("+%d %s" % [event["amount"], Defs.item(event["item"]).get("name", event["item"])])
		"zone":
			say("Entering the %s zone" % Defs.ZONE_NAMES[clampi(event["zone"], 0, 3)])
		"death":
			if event.get("peer", -1) == client.peer_id:
				say("You died.")
			else:
				say("A survivor was killed.")
		"hit":
			if event.get("id", -1) == client.peer_id and event.get("kind", "") == "player":
				say("-%d health" % int(event["damage"]))
		"crate":
			say("You search the crate...")


func _on_result(kind: String, data: Dictionary) -> void:
	if kind != "stash":
		return
	if bool(data.get("ok", false)):
		say("%s %d × %s" % ["Stored" if data.get("deposit", false) else "Withdrawn", data.get("count", 0), data.get("item", "")])
	else:
		var reason: String = data.get("reason", "rejected")
		var reasons := {
			"no_station": "Stash: travel to the hub workbench",
			"missing_items": "Stash: item not available",
			"no_space": "Stash: destination is full",
			"dead": "Stash: unavailable while dead",
			"invalid_stack": "Stash: invalid amount"
		}
		say(reasons.get(reason, "Stash: " + reason))


func _process(_delta: float) -> void:
	if client == null or not client.you.has("health"):
		return
	_bars["health"].value = client.you["health"]
	_bars["hunger"].value = client.you["hunger"]
	_bars["thirst"].value = client.you["thirst"]
	var zone: int = clampi(int(client.you.get("zone", 0)), 0, 3)
	_zone_label.text = "%s zone  (tier %d)" % [Defs.ZONE_NAMES[zone].capitalize(), zone + 1]
	_zone_label.add_theme_color_override("font_color", [Color(0.4, 0.9, 0.4), Color(0.95, 0.85, 0.3), Color(0.95, 0.45, 0.3), Color(0.8, 0.3, 0.9)][zone])
	_info_label.text = "FPS %d   kills %d   deaths %d" % [Engine.get_frames_per_second(), client.you.get("kills", 0), client.you.get("deaths", 0)]
	var weapon: String = client.you.get("weapon", "")
	_equipped.text = "Weapon: %s" % (Defs.item(weapon).get("name", weapon) if weapon != "" else "fists")
	_death.visible = not bool(client.you.get("alive", true))
	if _inventory_panel.visible:
		_refresh_inventory()
	if _craft_panel.visible:
		_refresh_crafting()


func _refresh_inventory() -> void:
	var signature := str(client.inventory.to_dict()) + "|" + str(client.stash.to_dict())
	if signature == _inventory_signature:
		return
	_inventory_signature = signature
	for child in _inventory_grid.get_children():
		child.queue_free()
	for slot in client.inventory.slots:
		var button := Button.new()
		button.custom_minimum_size = Vector2(76, 44)
		button.add_theme_font_size_override("font_size", 11)
		if slot.is_empty():
			button.disabled = true
			button.text = "-"
		else:
			var item_id: String = slot["id"]
			var equipped: bool = item_id == client.inventory.weapon or item_id == client.inventory.armor
			button.text = "%s\nx%d%s" % [Defs.item(item_id).get("name", item_id), slot["count"], "  [on]" if equipped else ""]
			button.pressed.connect(func() -> void: client.use_item(item_id))
			button.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					client.move_stash(item_id, 1, true))
		_inventory_grid.add_child(button)
	for child in _stash_grid.get_children():
		child.queue_free()
	for slot in client.stash.slots:
		if slot.is_empty():
			continue
		var item_id: String = slot["id"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(90, 44)
		button.add_theme_font_size_override("font_size", 11)
		button.text = "%s\\nx%d" % [Defs.item(item_id).get("name", item_id), slot["count"]]
		button.tooltip_text = "Withdraw one item (at hub workbench)"
		button.pressed.connect(func() -> void: client.move_stash(item_id, 1, false))
		_stash_grid.add_child(button)


func _refresh_crafting() -> void:
	var craftable: Array = Crafting.craftable(client.inventory)
	var signature := str(craftable) + str(client.inventory.count("wood_1"))
	if signature == _craft_signature:
		return
	_craft_signature = signature
	for child in _craft_list.get_children():
		child.queue_free()
	var ids: Array = Defs.recipes().keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := craftable.has(a)
		var cb := craftable.has(b)
		return (ca and not cb) or (ca == cb and a < b))
	for id in ids:
		var recipe: Dictionary = Defs.recipes()[id]
		var needs: Array[String] = []
		for input in recipe["inputs"]:
			needs.append("%dx %s" % [recipe["inputs"][input], Defs.item(input).get("name", input)])
		var button := Button.new()
		button.text = "%s  <-  %s%s" % [Defs.item(recipe["output"]).get("name", recipe["output"]), ", ".join(needs), "  [bench]" if recipe["station"] == "workbench" else ""]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not craftable.has(id)
		button.pressed.connect(func() -> void: client.craft(id, 1))
		_craft_list.add_child(button)
