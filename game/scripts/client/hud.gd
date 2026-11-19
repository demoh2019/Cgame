extends CanvasLayer
## All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")

var client
var _bars: Dictionary = {}
var _zone_label: Label
var _info_label: Label
var _radar
var _contract_label: Label
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
var _trade_state: Dictionary = {}
var _trade_target: OptionButton
var _trade_item: OptionButton
var _trade_quantity: SpinBox
var _trade_status: Label
var _trade_peer_signature: String = ""
var _trade_item_signature: String = ""
var _market_select: OptionButton
var _market_quantity: SpinBox
var _market_price: SpinBox
var _market_status: Label
var _market_listings: Array = []







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


	var radar := SurvivalRadar.new()
	radar.name = "SurvivalRadar"
	radar.client = client
	radar.world = client.world
	add_child(radar)
	radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	radar.offset_left = -222.0
	radar.offset_top = 16.0
	radar.offset_right = -16.0
	radar.offset_bottom = 222.0
	_radar = radar

	var top_left := VBoxContainer.new()
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top_left)
	for entry in [["health", Color(0.85, 0.2, 0.2)], ["hunger", Color(0.9, 0.65, 0.2)], ["thirst", Color(0.25, 0.55, 0.95)], ["infection", Color(0.54, 0.28, 0.65)], ["exposure", Color(0.38, 0.7, 0.88)]]:
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
	_contract_label = Label.new()
	_contract_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right.add_child(_contract_label)

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
	var dismantle_button := Button.new()
	dismantle_button.text = "Dismantle nearby barricade (partial salvage)"
	dismantle_button.pressed.connect(func() -> void:
		var id: int = client.nearest_barricade(client.display_position())
		if id == -1:
			say("No barricade within 3 metres.")
		else:
			client.dismantle(id))
	inventory_box.add_child(dismantle_button)
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

	var rest_button := Button.new()
	rest_button.text = "Rest at camp (2 wood, 1 water, 1 food)"
	rest_button.tooltip_text = "Recover health and stamina in the safe settlement; 90s cooldown"
	rest_button.pressed.connect(Callable(client, "rest"))
	inventory_box.add_child(rest_button)

	var vendor_title := Label.new()
	vendor_title.text = "NPC vendor (hub workbench only)"
	inventory_box.add_child(vendor_title)
	var vendor_buttons := GridContainer.new()
	vendor_buttons.columns = 2
	inventory_box.add_child(vendor_buttons)
	var buy_water := Button.new()
	buy_water.text = "Buy water (%d silver)" % int(Vendor.BUY_PRICES["water_bottle"])
	buy_water.pressed.connect(func() -> void: client.vendor("water_bottle", 1, true))
	vendor_buttons.add_child(buy_water)
	var buy_food := Button.new()
	buy_food.text = "Buy food (%d silver)" % int(Vendor.BUY_PRICES["canned_food"])
	buy_food.pressed.connect(func() -> void: client.vendor("canned_food", 1, true))
	vendor_buttons.add_child(buy_food)
	var sell_scrap := Button.new()
	sell_scrap.text = "Sell scrap (+%d silver)" % int(Vendor.SELL_PRICES["scrap"])
	sell_scrap.pressed.connect(func() -> void: client.vendor("scrap", 1, false))
	vendor_buttons.add_child(sell_scrap)
	var sell_wood := Button.new()
	sell_wood.text = "Sell wood (+%d silver)" % int(Vendor.SELL_PRICES["wood_1"])
	sell_wood.pressed.connect(func() -> void: client.vendor("wood_1", 1, false))
	vendor_buttons.add_child(sell_wood)
	var sell_refined := Button.new()
	sell_refined.text = "Sell carried refined material"
	sell_refined.pressed.connect(_sell_one_material)
	vendor_buttons.add_child(sell_refined)
	var contract_title := Label.new()
	contract_title.text = "Camp contracts (hub only)"
	inventory_box.add_child(contract_title)
	var contract_actions := HBoxContainer.new()
	inventory_box.add_child(contract_actions)
	var fish_button := Button.new()
	fish_button.text = "Cast fishing rod (near shoreline; 5 seconds)"
	fish_button.pressed.connect(func() -> void: client.fish())
	inventory_box.add_child(fish_button)
	var accept_contract := Button.new()
	accept_contract.text = "Accept next mission"
	accept_contract.pressed.connect(func() -> void: client.contract("accept"))
	contract_actions.add_child(accept_contract)
	var claim_contract := Button.new()
	claim_contract.text = "Turn in mission"
	claim_contract.pressed.connect(func() -> void: client.contract("claim"))
	contract_actions.add_child(claim_contract)

	var trade_title := Label.new()
	trade_title.text = "Player barter (safe hub, within 6 metres)"
	inventory_box.add_child(trade_title)
	_trade_status = Label.new()
	_trade_status.text = "Invite a nearby survivor, set an offer and both confirm."
	inventory_box.add_child(_trade_status)
	_trade_target = OptionButton.new()
	inventory_box.add_child(_trade_target)
	var trade_buttons := HBoxContainer.new()
	inventory_box.add_child(trade_buttons)
	var invite_trade := Button.new()
	invite_trade.text = "Invite"
	invite_trade.pressed.connect(func() -> void:
		var peer_id: int = _trade_target.get_selected_id()
		if peer_id >= 0:
			client.trade_invite(peer_id)
		else:
			say("Trade: no nearby survivor selected"))
	trade_buttons.add_child(invite_trade)
	_trade_item = OptionButton.new()
	trade_buttons.add_child(_trade_item)
	_trade_quantity = SpinBox.new()
	_trade_quantity.min_value = 0.0
	_trade_quantity.max_value = 9999.0
	_trade_quantity.step = 1.0
	_trade_quantity.value = 1.0
	trade_buttons.add_child(_trade_quantity)
	var offer_trade := Button.new()
	offer_trade.text = "Offer"
	offer_trade.pressed.connect(func() -> void:
		if _trade_state.is_empty() or _trade_item.selected < 0:
			say("Trade: invite someone and choose an item first")
		else:
			var id: String = str(_trade_item.get_item_metadata(_trade_item.selected))
			client.trade_offer(int(_trade_state["id"]), id, int(_trade_quantity.value)))
	trade_buttons.add_child(offer_trade)
	var accept_trade := Button.new()
	accept_trade.text = "Accept"
	accept_trade.pressed.connect(func() -> void:
		if not _trade_state.is_empty():
			client.trade_accept(int(_trade_state["id"]), int(_trade_state["revision"])))
	trade_buttons.add_child(accept_trade)
	var cancel_trade := Button.new()
	cancel_trade.text = "Cancel"
	cancel_trade.pressed.connect(func() -> void:
		if not _trade_state.is_empty():
			client.trade_cancel(int(_trade_state["id"])))
	trade_buttons.add_child(cancel_trade)

	var market_title := Label.new()
	market_title.text = "Survivor market - ONLINE listings (hub)"
	inventory_box.add_child(market_title)
	_market_status = Label.new()
	_market_status.text = "Refresh to browse listings. Stock is checked on purchase."
	inventory_box.add_child(_market_status)
	_market_select = OptionButton.new()
	_market_select.custom_minimum_size.x = 320.0
	inventory_box.add_child(_market_select)
	var market_row := HBoxContainer.new()
	inventory_box.add_child(market_row)
	_market_quantity = SpinBox.new()
	_market_quantity.min_value = 1.0
	_market_quantity.max_value = 40.0
	_market_quantity.value = 1.0
	market_row.add_child(_market_quantity)
	_market_price = SpinBox.new()
	_market_price.min_value = 1.0
	_market_price.max_value = 2000.0
	_market_price.value = 5.0
	market_row.add_child(_market_price)
	var refresh_market := Button.new()
	refresh_market.text = "Refresh"
	refresh_market.pressed.connect(func() -> void: client.market_list())
	market_row.add_child(refresh_market)
	var post_market := Button.new()
	post_market.text = "List item"
	post_market.pressed.connect(func() -> void:
		if _trade_item.selected < 0:
			say("Market: choose an inventory item in the barter selector")
		else:
			var id: String = str(_trade_item.get_item_metadata(_trade_item.selected))
			client.market_create(id, int(_market_quantity.value), int(_market_price.value)))
	market_row.add_child(post_market)
	var buy_market := Button.new()
	buy_market.text = "Buy"
	buy_market.pressed.connect(func() -> void:
		if _market_select.selected < 0:
			say("Market: select an active listing")
		else:
			var listing_id: int = int(_market_select.get_item_metadata(_market_select.selected))
			client.market_buy(listing_id, int(_market_quantity.value)))
	market_row.add_child(buy_market)
	var cancel_market := Button.new()
	cancel_market.text = "Cancel mine"
	cancel_market.pressed.connect(func() -> void:
		if _market_select.selected >= 0:
			var listing_id: int = int(_market_select.get_item_metadata(_market_select.selected))
			client.market_cancel(listing_id))
	market_row.add_child(cancel_market)

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



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M and _radar != null:
			_radar.visible = not _radar.visible


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	if _inventory_panel.visible:
		client.market_list()


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
		"fished":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Fishing: caught %d raw fish. Cook at the hub workbench." % int(event.get("amount", 0)))
		"zone":
			var zone: int = clampi(int(event["zone"]), 0, 3)
			say("Entering %s: %s" % [Defs.ZONE_NAMES[zone], ZoneRisk.description(zone)])
		"death":
			if event.get("peer", -1) == client.peer_id:
				say("You died: %s" % ("full loot" if bool(event.get("full_loot", true)) else "gear retained"))
			else:
				say("A survivor was killed.")
		"hit":
			if event.get("id", -1) == client.peer_id and event.get("kind", "") == "player":
				say("-%d health" % int(event["damage"]))
		"infection":
			if event.get("peer", -1) == client.peer_id:
				say("Infected wound: severity %d. Use antiseptic or antibiotics." % int(event.get("severity", 0)))
		"mastery":
			if event.get("peer", -1) == client.peer_id:
				say("+%d %s weapon mastery XP" % [int(event.get("xp", 0)),
					str(event.get("skill", "weapon"))])
		"evaded":
			if event.get("peer", -1) == client.peer_id:
				say("Evaded an infected attack!")
		"crate":
			say("You search the crate...")
		"trade":
			var phase: String = str(event.get("phase", ""))
			if phase == "completed" or phase == "cancelled":
				_trade_state = {}
				say("Trade %s: %s" % [phase, str(event.get("reason", ""))])
			else:
				_trade_state = event.duplicate(true)
				say("Trade %s (#%d, revision %d)" % [phase, int(event["id"]), int(event["revision"])])


func _sell_one_material() -> void:
	var item_id: String = Vendor.first_sellable(client.inventory)
	if item_id.is_empty():
		say("Vendor: no tradable materials")
		return
	client.vendor(item_id, 1, false)


func _on_result(kind: String, data: Dictionary) -> void:
	if kind == "drink":
		if bool(data.get("ok", false)):
			say("Lake: clean filtered drink" if bool(data.get("filtered", false)) else "Lake: unfiltered water increased infection")
		else:
			say("Lake: %s" % str(data.get("reason", "denied")))
		return
	if kind == "rest":
		if bool(data.get("ok", false)):
			say("Camp rest: recovered; 90 seconds until the next rest")
		else:
			say("Camp rest: " + str(data.get("reason", "rejected")))
		return
	if kind == "fish":
		say("Fishing: casting..." if bool(data.get("ok", false)) else "Fishing: %s" % str(data.get("reason", "denied")))
		return
	if kind == "market":
		if not bool(data.get("ok", false)):
			say("Market: " + str(data.get("reason", "rejected")))
		elif str(data.get("action", "")) == "list":
			_market_listings = data.get("orders", [])
			_refresh_market_options()
		else:
			say("Market: %s %s" % [str(data.get("action", "updated")), str(data.get("item", ""))])
			client.market_list()
		return
	if kind == "trade":
		if not bool(data.get("ok", false)):
			say("Trade rejected: " + str(data.get("reason", "unknown")))
		return
	if kind == "dismantle":
		if bool(data.get("ok", false)):
			say("Barricade dismantled; recovered %s" % str(data.get("salvage", {})))
		else:
			say("Dismantle denied: %s" % str(data.get("reason", "rejected")))
		return
	if kind == "contract":
		if bool(data.get("ok", false)):
			say("Camp mission: " + str(data.get("title", data.get("active", "updated"))))
		else:
			say("Camp mission: " + str(data.get("reason", "rejected")))
		return
	if kind == "vendor":
		if bool(data.get("ok", false)):
			say("%s %d x %s (%d silver)" % [
				"Bought" if data.get("buy", false) else "Sold",
				int(data.get("quantity", 0)), str(data.get("item", "")),
				int(data.get("silver_delta", 0))])
		else:
			var messages := {
				"no_station": "Vendor: return to hub workbench",
				"dead": "Vendor: unavailable while dead",
				"invalid_quantity": "Vendor: invalid quantity",
				"not_traded": "Vendor: item is not traded here",
				"missing_items": "Vendor: insufficient resources",
				"insufficient_silver": "Vendor: insufficient silver",
				"no_space": "Vendor: backpack slots or stacks are full",
			}
			say(str(messages.get(str(data.get("reason", "")), "Vendor: rejected")))
		return
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
	_bars["infection"].value = float(client.you.get("infection", 0.0))
	_bars["exposure"].value = float(client.you.get("exposure", 0.0))
	var zone: int = clampi(int(client.you.get("zone", 0)), 0, 3)
	_zone_label.text = "%s zone (T%d)\n%s" % [Defs.ZONE_NAMES[zone].capitalize(), zone + 1, ZoneRisk.description(zone)]
	_zone_label.add_theme_color_override("font_color", [Color(0.4, 0.9, 0.4), Color(0.95, 0.85, 0.3), Color(0.95, 0.45, 0.3), Color(0.8, 0.3, 0.9)][zone])
	_info_label.text = "%s | FPS %d  kills %d  deaths %d  Load %.1f kg  Speed %.0f%%  Stamina %d  Dodge %.1fs" % [
		"NIGHT" if WorldCycle.is_night(client.server_time) else "DAY", Engine.get_frames_per_second(), client.you.get("kills", 0), client.you.get("deaths", 0),
		float(client.you.get("carry_kg", 0.0)), 100.0 * float(client.you.get("cargo_factor", 1.0)),
		int(client.you.get("stamina", Defs.MAX_STAMINA)), float(client.you.get("dodge_cooldown", 0.0))
	]
	var weather: Dictionary = client.you.get("weather", {})
	if not weather.is_empty():
		_info_label.text += "\nWeather: %s %.0fC %s | Exposure %d/100 | Heat pack %ds" % [
			str(weather.get("condition", "clear")).capitalize(),
			float(weather.get("temperature_c", 0.0)),
			"SHELTERED" if bool(weather.get("sheltered", false)) else "EXPOSED",
			int(client.you.get("exposure", 0.0)), int(ceil(float(client.you.get("warmth_seconds", 0.0))))
		]
	var journal: Variant = client.you.get("contract", Contracts.empty_state())
	_contract_label.text = Contracts.description(journal if journal is Dictionary else Contracts.empty_state())
	_info_label.text += "  Rest %.0fs" % float(client.you.get("rest_cooldown", 0.0))
	var weapon: String = client.you.get("weapon", "")
	var levels: Dictionary = client.you.get("gathering_levels", {})
	var weapon_levels: Dictionary = client.you.get("combat_levels", {})
	_equipped.text = "Weapon: %s | Craft L%d (%d XP)\nWood L%d | Stone L%d | Ore L%d | Fiber L%d | Fishing L%d\nMastery: Melee L%d | Ranged L%d" % [
		(Defs.item(weapon).get("name", weapon) if weapon != "" else "fists"),
		int(client.you.get("crafting_level", 1)), int(client.you.get("crafting_xp", 0)),
		int(levels.get("wood", 1)), int(levels.get("stone", 1)),
		int(levels.get("ore", 1)), int(levels.get("fiber", 1)),
		int(levels.get("fishing", 1)),
		int(weapon_levels.get("melee", 1)), int(weapon_levels.get("ranged", 1))
	]
	_death.visible = not bool(client.you.get("alive", true))
	_death.text = "YOU DIED\n%s" % ("All carried items dropped." if bool(client.you.get("last_death_full_loot", false)) else "Carried equipment retained.")
	if _inventory_panel.visible:
		_refresh_inventory()
		_refresh_trade_controls()
	if _craft_panel.visible:
		_refresh_crafting()


func _refresh_market_options() -> void:
	var selected_id := -1
	if _market_select.selected >= 0:
		selected_id = int(_market_select.get_item_metadata(_market_select.selected))
	_market_select.clear()
	for order in _market_listings:
		var item_id: String = str(order["item"])
		var label: String = "%s ×%d | %d silver/item | %s%s" % [
			str(Defs.item(item_id).get("name", item_id)),
			int(order["quantity"]), int(order["price"]),
			str(order["seller_name"]), " (yours)" if bool(order["own"]) else "",
		]
		_market_select.add_item(label)
		var index: int = _market_select.item_count - 1
		_market_select.set_item_metadata(index, int(order["id"]))
		if int(order["id"]) == selected_id:
			_market_select.select(index)
	_market_status.text = "%d listings | quantity & price inputs below | inventory item from barter selector" % _market_listings.size()


func _refresh_trade_controls() -> void:
	var peers: Array = []
	for peer in client.players.values():
		peers.append([int(peer["id"]), str(peer.get("name", "Survivor"))])
	peers.sort_custom(func(a, b): return a[0] < b[0])
	var peer_signature := str(peers)
	if peer_signature != _trade_peer_signature:
		var selected_peer: int = _trade_target.get_selected_id()
		_trade_peer_signature = peer_signature
		_trade_target.clear()
		for peer in peers:
			_trade_target.add_item("%s (#%d)" % [peer[1], peer[0]], peer[0])
			if peer[0] == selected_peer:
				_trade_target.select(_trade_target.item_count - 1)
	var ids: Array[String] = []
	for slot in client.inventory.slots:
		if not slot.is_empty() and not ids.has(str(slot["id"])):
			ids.append(str(slot["id"]))
	ids.sort()
	var item_signature := str(ids)
	if item_signature != _trade_item_signature:
		var selected_item: String = ""
		if _trade_item.selected >= 0:
			selected_item = str(_trade_item.get_item_metadata(_trade_item.selected))
		_trade_item_signature = item_signature
		_trade_item.clear()
		for id in ids:
			_trade_item.add_item(str(Defs.item(id).get("name", id)))
			_trade_item.set_item_metadata(_trade_item.item_count - 1, id)
			if id == selected_item:
				_trade_item.select(_trade_item.item_count - 1)
	if _trade_state.is_empty():
		_trade_status.text = "No active exchange. Trades require two players in the safe hub."
	else:
		var a: int = int(_trade_state["a"])
		var ours: bool = a == client.peer_id
		var my_offer: Dictionary = _trade_state["offer_a"] if ours else _trade_state["offer_b"]
		var their_offer: Dictionary = _trade_state["offer_b"] if ours else _trade_state["offer_a"]
		var my_accepted: bool = bool(_trade_state["accepted_a"] if ours else _trade_state["accepted_b"])
		var their_accepted: bool = bool(_trade_state["accepted_b"] if ours else _trade_state["accepted_a"])
		_trade_status.text = "Trade #%d rev %d | You: %s (%s) | Them: %s (%s)" % [
			int(_trade_state["id"]), int(_trade_state["revision"]),
			str(my_offer), "accepted" if my_accepted else "pending",
			str(their_offer), "accepted" if their_accepted else "pending"
		]


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
		button.text = "%s\nx%d" % [Defs.item(item_id).get("name", item_id), slot["count"]]
		button.tooltip_text = "Withdraw one item (at hub workbench)"
		button.pressed.connect(func() -> void: client.move_stash(item_id, 1, false))
		_stash_grid.add_child(button)


func _refresh_crafting() -> void:
	var craftable: Array = Crafting.craftable(client.inventory)
	var signature := str(craftable) + str(client.inventory.count("wood_1")) + str(client.you.get("crafting_level", 1))
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
		var required_tier: int = maxi(1, Defs.tier_of(String(recipe["output"])))
		var skill_locked: bool = required_tier > int(client.you.get("crafting_level", 1))
		button.disabled = not craftable.has(id) or skill_locked
		if skill_locked:
			button.text += "  [Craft Lv%d]" % required_tier
		button.pressed.connect(func() -> void: client.craft(id, 1))
		_craft_list.add_child(button)
