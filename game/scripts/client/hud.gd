extends CanvasLayer
## All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")
const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")
const PartyFrames = preload("res://scripts/client/party_frames.gd")
const HudSkin = preload("res://scripts/client/hud_skin.gd")

var client
var _bars: Dictionary = {}
var _zone_label: Label
var _info_label: Label
var _vendor_water_button: Button
var _vendor_food_button: Button
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
var _party_frames: Label
var _log_lines: Array[String] = []
var _log_times: Array[float] = []
var _skin
var _details: Array = [] # The old text widgets, kept alive for F3.
var _craft_signature: String = ""
var _inventory_signature: String = ""
var _trade_state: Dictionary = {}
var _party_status: Label
var _duel_status: Label
var _arena_queue_status: Label
var _party_target: OptionButton
var _party_peer_signature: String = ""
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
	# The drawn vitals card (hud_skin.gd) covers this area; the plain bars below stay as hidden data holders.
	var card_gap := Control.new()
	card_gap.custom_minimum_size = Vector2(1, 178)
	card_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_child(card_gap)
	for entry in [["health", Color(0.85, 0.2, 0.2)], ["hunger", Color(0.9, 0.65, 0.2)], ["thirst", Color(0.25, 0.55, 0.95)], ["infection", Color(0.54, 0.28, 0.65)], ["bleeding", Color(0.73, 0.21, 0.27)], ["fracture", Color(0.75, 0.48, 0.2)], ["exposure", Color(0.38, 0.7, 0.88)]]:
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
		_details.append(label)
		_details.append(bar)
	_equipped = Label.new()
	top_left.add_child(_equipped)
	_details.append(_equipped)
	_party_frames = Label.new()
	_party_frames.name = "PartyFrames"
	_party_frames.add_theme_font_size_override("font_size", 14)
	_party_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_child(_party_frames)

	var top_right := VBoxContainer.new()
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top_right)
	# The minimap sits in the top-right corner: start the text column below it.
	var minimap_gap := Control.new()
	minimap_gap.custom_minimum_size = Vector2(1, 236)
	minimap_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_child(minimap_gap)
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
	_details.append_array([_zone_label, _info_label, _contract_label])

	_log = Label.new()
	_log.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_log.size_flags_vertical = Control.SIZE_SHRINK_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.04, 0.05, 0.08, 0.62)
	log_style.set_corner_radius_all(10)
	log_style.set_content_margin_all(9)
	_log.add_theme_stylebox_override("normal", log_style)
	_log.add_theme_font_size_override("font_size", 14)
	_log.visible = false
	margin.add_child(_log)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-200, -140)
	_prompt.size = Vector2(400, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prompt_style := StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.05, 0.06, 0.09, 0.78)
	prompt_style.border_color = Color(0.95, 0.78, 0.35, 0.7)
	prompt_style.set_border_width_all(1)
	prompt_style.set_corner_radius_all(14)
	prompt_style.content_margin_left = 16
	prompt_style.content_margin_right = 16
	prompt_style.content_margin_top = 4
	prompt_style.content_margin_bottom = 4
	_prompt.add_theme_stylebox_override("normal", prompt_style)
	_prompt.position = Vector2(-260, -176)
	_prompt.size = Vector2(520, 30)
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
	var campfire_button := Button.new()
	campfire_button.text = "Light field campfire (3 wood T1, 1 stone T1)"
	campfire_button.tooltip_text = "Shared warmth for 5 minutes, outside the safe settlement"
	campfire_button.pressed.connect(func() -> void:
		var pos: Vector3 = client.display_position()
		var direction := Vector2(sin(client.yaw), cos(client.yaw))
		client.light_campfire(Vector2(pos.x, pos.z) + direction * 2.8))
	inventory_box.add_child(campfire_button)
	var decoy_button := Button.new()
	decoy_button.name = "ThrowNoiseDecoy"
	decoy_button.text = "Throw clattering decoy (,): 8s distraction"
	decoy_button.tooltip_text = "Needs a crafted decoy: 2 wood T1 + 1 scrap"
	decoy_button.pressed.connect(func() -> void:
		var heading := Vector2(sin(client.yaw), cos(client.yaw))
		client.throw_decoy(heading))
	inventory_box.add_child(decoy_button)
	var snare_button := Button.new()
	snare_button.name = "PlaceInfectedSnare"
	snare_button.text = "Place infected tripwire (\\): roots one infected"
	snare_button.tooltip_text = "Requires one crafted snare; outside safe zones, up to 3 deployed per survivor."
	snare_button.pressed.connect(func() -> void:
		var at: Vector3 = client.display_position()
		var face := Vector2(sin(client.yaw), cos(client.yaw))
		client.place_infected_snare(Vector2(at.x, at.z) + face * 2.8))
	inventory_box.add_child(snare_button)
	var refuel_button := Button.new()
	refuel_button.name = "RefuelCampfire"
	refuel_button.text = "Refuel nearest campfire (+2 min, 2 wood T1; 9)"
	refuel_button.pressed.connect(func() -> void:
		var fire_id: int = client.nearest_campfire(client.display_position())
		if fire_id == -1:
			say("No burning campfire nearby.")
		else:
			client.refuel_campfire(fire_id))
	inventory_box.add_child(refuel_button)
	var extinguish_button := Button.new()
	extinguish_button.name = "ExtinguishCampfire"
	extinguish_button.text = "Extinguish my nearby campfire (no refund; -)"
	extinguish_button.pressed.connect(func() -> void:
		var fire_id: int = client.nearest_campfire(client.display_position())
		if fire_id == -1:
			say("No campfire nearby.")
		else:
			client.extinguish_campfire(fire_id))
	inventory_box.add_child(extinguish_button)
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
	rest_button.text = "Rest: safe hub or a lit field campfire"
	rest_button.tooltip_text = "Hub: 2 wood + canned food + water. Fire: cooked fish/canned ration + water, no nearby threats; 90s cooldown."
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
	_vendor_water_button = buy_water
	var buy_food := Button.new()
	buy_food.text = "Buy food (%d silver)" % int(Vendor.BUY_PRICES["canned_food"])
	buy_food.pressed.connect(func() -> void: client.vendor("canned_food", 1, true))
	vendor_buttons.add_child(buy_food)
	_vendor_food_button = buy_food
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
	var sell_fish := Button.new()
	sell_fish.text = "Sell best raw fish"
	sell_fish.pressed.connect(func() -> void:
		var fish_id: String = Vendor.first_fish(client.inventory)
		if fish_id.is_empty():
			say("Vendor: no raw fish in backpack")
		else:
			client.vendor(fish_id, 1, false))
	vendor_buttons.add_child(sell_fish)

	var contract_title := Label.new()
	contract_title.text = "Camp contracts (hub only)"
	inventory_box.add_child(contract_title)
	var contract_actions := HBoxContainer.new()
	inventory_box.add_child(contract_actions)
	var fish_button := Button.new()
	fish_button.text = "Cast fishing rod (near shoreline; 5 seconds)"
	fish_button.pressed.connect(func() -> void: client.fish())
	inventory_box.add_child(fish_button)
	var bait_button := Button.new()
	bait_button.name = "BaitedCast"
	bait_button.text = "Baited cast (+1 fish on completion; 1 bait)"
	bait_button.tooltip_text = "Craft from berries and fiber; no charge if the bonus cannot fit."
	bait_button.pressed.connect(func() -> void: client.fish(true))
	inventory_box.add_child(bait_button)
	var storm_button := Button.new()
	storm_button.name = "StormCast"
	storm_button.text = "Storm cast (red/black coast; 8s, +2 fish)"
	storm_button.tooltip_text = "During real storms in full-loot regions; canceled if weather changes. No bait used."
	storm_button.pressed.connect(func() -> void: client.fish(false, true))
	inventory_box.add_child(storm_button)
	var cook_button := Button.new()
	cook_button.text = "0: Quick-cook best carried fish (fire or hub)"
	cook_button.pressed.connect(quick_cook)
	inventory_box.add_child(cook_button)
	var accept_contract := Button.new()
	accept_contract.text = "Accept next mission"
	accept_contract.pressed.connect(func() -> void: client.contract("accept"))
	contract_actions.add_child(accept_contract)
	var claim_contract := Button.new()
	claim_contract.text = "Turn in mission"
	claim_contract.pressed.connect(func() -> void: client.contract("claim"))
	contract_actions.add_child(claim_contract)
	var daily_claim := Button.new()
	daily_claim.text = "Turn in UTC daily bounty"
	daily_claim.tooltip_text = "One repeatable camp bounty each UTC day. Collect only at the camp workbench."
	daily_claim.pressed.connect(func() -> void: client.contract("daily_claim"))
	contract_actions.add_child(daily_claim)

	var cache_heading := Label.new()
	cache_heading.text = "Frontier cache (capture a red/black outpost)"
	inventory_box.add_child(cache_heading)
	var claim_cache_button := Button.new()
	claim_cache_button.text = "Collect nearest captured outpost supplies"
	claim_cache_button.pressed.connect(_claim_nearest_outpost_cache)
	inventory_box.add_child(claim_cache_button)

	var party_title := Label.new()
	party_title.text = "Survivor party (nearby invites, up to 5 players)"
	inventory_box.add_child(party_title)
	_party_status = Label.new()
	_party_status.text = "No party. Invite a nearby survivor to fight together."
	inventory_box.add_child(_party_status)
	_party_target = OptionButton.new()
	inventory_box.add_child(_party_target)
	var party_buttons := HBoxContainer.new()
	inventory_box.add_child(party_buttons)
	var invite_member := Button.new()
	invite_member.text = "Invite"
	invite_member.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target >= 0:
			client.party_invite(target)
		else:
			say("Party: choose a visible survivor first"))
	party_buttons.add_child(invite_member)
	var accept_member := Button.new()
	accept_member.text = "Join"
	accept_member.pressed.connect(func() -> void: client.party_accept())
	party_buttons.add_child(accept_member)
	var decline_member := Button.new()
	decline_member.text = "Decline"
	decline_member.pressed.connect(func() -> void: client.party_decline())
	party_buttons.add_child(decline_member)
	var leave_party := Button.new()
	leave_party.text = "Leave"
	leave_party.pressed.connect(func() -> void: client.party_leave())
	party_buttons.add_child(leave_party)
	var duel_heading := Label.new()
	duel_heading.text = "Training duel (green hub only, no gear loss)"
	inventory_box.add_child(duel_heading)
	_duel_status = Label.new()
	_duel_status.text = "No duel pending."
	inventory_box.add_child(_duel_status)
	var duel_buttons := HBoxContainer.new()
	inventory_box.add_child(duel_buttons)
	var duel_invite := Button.new()
	duel_invite.text = "Challenge selected"
	duel_invite.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target >= 0:
			client.duel_invite(target)
		else:
			say("Select a visible survivor above"))
	duel_buttons.add_child(duel_invite)
	var ranked_button := Button.new()
	ranked_button.text = "Ranked challenge"
	ranked_button.tooltip_text = "Authenticated accounts only; Elo after knockout/forfeit. 20-minute same-opponent cooldown."
	ranked_button.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target >= 0:
			client.duel_invite(target, true)
		else:
			say("Ranked: choose a nearby survivor first"))
	duel_buttons.add_child(ranked_button)
	var queue_buttons := HBoxContainer.new()
	inventory_box.add_child(queue_buttons)
	var queue_join := Button.new()
	queue_join.text = "Find rated opponent"
	queue_join.tooltip_text = "Opt into automatic matching with nearby authenticated hub players."
	queue_join.pressed.connect(func() -> void: client.arena_queue_join())
	queue_buttons.add_child(queue_join)
	var queue_leave := Button.new()
	queue_leave.text = "Leave arena queue"
	queue_leave.pressed.connect(func() -> void: client.arena_queue_leave())
	queue_buttons.add_child(queue_leave)
	_arena_queue_status = Label.new()
	_arena_queue_status.text = "Ranked queue: not searching"
	inventory_box.add_child(_arena_queue_status)
	var duel_accept := Button.new()
	duel_accept.text = "Accept"
	duel_accept.pressed.connect(func() -> void: client.duel_accept())
	duel_buttons.add_child(duel_accept)
	var duel_cancel := Button.new()
	duel_cancel.text = "Decline / end"
	duel_cancel.pressed.connect(func() -> void: client.duel_cancel())
	duel_buttons.add_child(duel_cancel)
	var rally_button := Button.new()
	rally_button.text = "Set rally"
	rally_button.tooltip_text = "Leader only: signal your current server position for 45 seconds"
	rally_button.pressed.connect(func() -> void: client.party_rally())
	party_buttons.add_child(rally_button)
	var standard_button := Button.new()
	standard_button.text = "Raise standard"
	standard_button.tooltip_text = "Party leader: use one crafted expedition standard outside town, with an ally nearby (+stamina/energy for 90s)."
	standard_button.pressed.connect(func() -> void: client.party_standard())
	party_buttons.add_child(standard_button)
	var guardian_button := Button.new()
	guardian_button.text = "Guardian taunt (F1)"
	guardian_button.tooltip_text = "Melee weapon, party, 25 combat energy, 20s cooldown; defend nearby allies"
	guardian_button.pressed.connect(func() -> void: client.guardian_taunt())
	inventory_box.add_child(guardian_button)
	var fortify_button := Button.new()
	fortify_button.name = "FortifyOutpost"
	fortify_button.text = "Fortify controlled outpost (4m, wood + stone)"
	fortify_button.tooltip_text = "Stand next to a party-controlled outpost in a PvP zone. Each upgrade increases enemy capture time."
	fortify_button.pressed.connect(func() -> void:
		var here: Vector3 = client.display_position()
		var nearest: Dictionary = {}
		var closest_distance := INF
		for site in client.outposts:
			var distance: float = Vector2(here.x, here.z).distance_to(
				Vector2(float(site["x"]), float(site["z"])))
			if distance < closest_distance:
				closest_distance = distance
				nearest = site
		if nearest.is_empty() or closest_distance > 4.0:
			say("Fortification: move within 4m of an outpost")
		else:
			client.outpost_fortify(int(nearest["id"])))
	inventory_box.add_child(fortify_button)
	var breach_button := Button.new()
	breach_button.name = "BreachOutpost"
	breach_button.text = "Breach enemy outpost (2 planks T2 + 2 bars T2)"
	breach_button.tooltip_text = "Two living attackers in one party must be near the enemy flag. Reduces one fortification tier; 45s cooldown."
	breach_button.pressed.connect(func() -> void:
		var here: Vector3 = client.display_position()
		var nearest: Dictionary = {}
		var distance := INF
		for site in client.outposts:
			var delta: float = Vector2(here.x, here.z).distance_to(
				Vector2(float(site["x"]), float(site["z"])))
			if delta < distance:
				distance = delta
				nearest = site
		if nearest.is_empty() or distance > 4.0:
			say("Breach: move within 4m of an enemy outpost")
		else:
			client.outpost_breach(int(nearest["id"])))
	inventory_box.add_child(breach_button)
	var war_button := Button.new()
	war_button.name = "DeclareSiege"
	war_button.text = "Declare siege (2 cloth T2 + 25 silver)"
	war_button.tooltip_text = "Party leader only: two nearby party members, 20s preparation, 180s assault."
	war_button.pressed.connect(func() -> void:
		var here: Vector3 = client.display_position()
		var nearest: Dictionary = {}
		var distance := INF
		for site in client.outposts:
			var gap: float = Vector2(here.x, here.z).distance_to(
				Vector2(float(site["x"]), float(site["z"])))
			if gap < distance:
				distance = gap
				nearest = site
		if nearest.is_empty() or distance > 24.0:
			say("Siege: leader must be within 24m of a rival outpost")
		else:
			client.siege_declare(int(nearest["id"])))
	inventory_box.add_child(war_button)



	var kick_member := Button.new()
	kick_member.text = "Kick"
	kick_member.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target >= 0:
			client.party_kick(target)
		else:
			say("Party: select the member to remove"))
	party_buttons.add_child(kick_member)
	# Equipment-free support role, paid for with real carried medical items.
	var aid_row := HBoxContainer.new()
	inventory_box.add_child(aid_row)
	var aid_items := OptionButton.new()
	for item_id in ["bandage", "field_antiseptic", "antibiotics", "purified_serum"]:
		if Defs.is_item(item_id):
			var index: int = aid_items.item_count
			aid_items.add_item(str(Defs.item(item_id).get("name", item_id)))
			aid_items.set_item_metadata(index, item_id)
	aid_row.add_child(aid_items)
	var aid_button := Button.new()
	aid_button.text = "Aid"
	aid_button.tooltip_text = "Treat the selected nearby party member with one medical item; 5s cooldown."
	aid_button.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target < 0 or aid_items.selected < 0:
			say("Aid: select a nearby party member and a medical item.")
		else:
			client.party_aid(target, str(aid_items.get_selected_metadata())))
	aid_row.add_child(aid_button)
	# A cook supplies one real dish per present, eligible group member.
	var feast_row := HBoxContainer.new()
	inventory_box.add_child(feast_row)
	var feast_item := OptionButton.new()
	for tier in range(1, Defs.MAX_TIER + 1):
		var meal_id: String = "cooked_fish" if tier == 1 else "cooked_fish_%d" % tier
		feast_item.add_item(str(Defs.item(meal_id).get("name", meal_id)))
		feast_item.set_item_metadata(feast_item.item_count - 1, meal_id)
	feast_row.add_child(feast_item)
	var feast_button := Button.new()
	feast_button.text = "Share cooked meal"
	feast_button.tooltip_text = "At a lit campfire, share one cooked fish per nearby party member (20s cooldown)."
	feast_button.pressed.connect(func() -> void:
		if feast_item.selected < 0:
			say("Select the prepared fish tier to share.")
		else:
			client.party_feast(str(feast_item.get_selected_metadata())))
	feast_row.add_child(feast_button)

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
	var death_style := StyleBoxFlat.new()
	death_style.bg_color = Color(0.1, 0.0, 0.0, 0.72)
	death_style.border_color = Color(0.95, 0.25, 0.2, 0.8)
	death_style.set_border_width_all(2)
	death_style.set_corner_radius_all(16)
	death_style.set_content_margin_all(18)
	_death.add_theme_stylebox_override("normal", death_style)
	_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_death)

	# The drawn interface on top of everything else: vitals card, clock, quests, action bar.
	_skin = HudSkin.new()
	_skin.name = "HudSkin"
	add_child(_skin)
	move_child(_skin, 0)
	_skin.setup(client)
	_skin.client_info_label = _info_label
	set_details_visible(false)



## F3: the full text readout (every number and timer) instead of the drawn interface.
func set_details_visible(shown: bool) -> void:
	for node in _details:
		node.visible = shown
	if _skin != null:
		_skin.details_visible = shown


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3 and _skin != null:
			set_details_visible(not _skin.details_visible)
		if event.physical_keycode == KEY_M and _radar != null:
			_radar.visible = not _radar.visible


## Invoked from the online '0' key and inventory button.
func quick_cook() -> void:
	var recipe_id: String = QuickCooking.best_recipe(
		client.inventory, int(client.you.get("crafting_level", 1)))
	if recipe_id.is_empty():
		say("Cooking: need fish, matching wood and sufficient crafting mastery")
	else:
		client.craft(recipe_id, 1)


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
	_log_times.append(Time.get_ticks_msec() / 1000.0)
	while _log_lines.size() > 7:
		_log_lines.pop_front()
		_log_times.pop_front()
	_log.text = "\n".join(_log_lines)
	_log.visible = true


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		"party_feast":
			if int(event.get("peer", -1)) == client.peer_id and int(event.get("by", -1)) != client.peer_id:
				say("A teammate shared a T%d cooked meal. Recovery boosted for %ds." % [
					int(event.get("tier", 1)), int(event.get("seconds", 0))])
		"arena_queue":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Arena matchmaking: " + str(event.get("status", "unknown")))
		"duel":
			match str(event.get("phase", "")):
				"invited":
					say("%s challenge from %s. Open inventory to accept." % [
						"RANKED" if bool(event.get("ranked", false)) else "Training duel",
						str(event.get("name", "Survivor"))])
				"started":
					say("%s duel started vs %s. No loot loss." % [
						"Ranked" if bool(event.get("ranked", false)) else "Training",
						str(event.get("opponent", "Survivor"))])
				"finished":
					var winner: int = int(event.get("winner", -1))
					say("Duel %s (%s)." % ["won" if winner == client.peer_id else ("lost" if winner > 0 else "ended"),
						str(event.get("reason", "finished"))])
					if bool(event.get("ranked", false)):
						say("Arena rating: %d (%+d)" % [int(event.get("rating", 1200)),
							int(event.get("rating_change", 0))])
		"self_defense":
			if int(event.get("peer", -1)) == client.peer_id:
				say("ATTACKED! You may retaliate for 30 seconds without infamy.")
		"justice":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Lawful PvP victory (%s). No criminal infamy added." % str(event.get("reason", "defense")))
		"party_aid":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Teammate treated you: +%d HP, -%d infection, -%d bleeding, -%d fracture." % [
					roundi(float(event.get("heal", 0.0))),
					roundi(float(event.get("cure", 0.0))),
					roundi(float(event.get("bleeding_stopped", 0.0))),
					roundi(float(event.get("fracture_treated", 0.0)))])
		"gathered":
			say("+%d %s" % [event["amount"], Defs.item(event["item"]).get("name", event["item"])])
		"campfire_doused":
			say("Storm exhausted a nearby campfire. Find shelter or refuel sooner.")
		"campfire_refueled":
			if int(event.get("peer", -1)) == client.peer_id:
				say("You added wood to the shared campfire.")
		"storm_cast_lost":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Storm fishing interrupted: storm ended or you left the risky coast.")
		"fished":
			if int(event.get("peer", -1)) == client.peer_id:
				var catch_id: String = str(event.get("item", "raw_fish"))
				var display: String = str(Defs.item(catch_id).get("name", catch_id))
				say("Fishing: caught %d %s%s. Cook at the camp." % [
					int(event.get("amount", 0)), display,
					" (storm bonus +%d)" % int(event.get("storm_bonus", 0)) if
						int(event.get("storm_bonus", 0)) > 0 else ""])
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
		"bleeding":
			if event.get("peer", -1) == client.peer_id:
				say("Bleeding wound: %d/100. Use a bandage or antiseptic." % int(event.get("severity", 0)))
		"fracture":
			if event.get("peer", -1) == client.peer_id:
				say("Broken limb: sprint disabled, walking slowed. Craft a Field Splint.")
		"renown":
			if int(event.get("peer", -1)) == client.peer_id:
				say("+%d renown from %s | %s (%d total)" % [
					int(event.get("earned", 0)), str(event.get("source", "survival")),
					str(event.get("rank", "Newcomer")), int(event.get("total", 0))])
		"mastery":
			if event.get("peer", -1) == client.peer_id:
				say("+%d %s weapon mastery XP" % [int(event.get("xp", 0)),
					str(event.get("skill", "weapon"))])
		"evaded":
			if event.get("peer", -1) == client.peer_id:
				say("Evaded an infected attack!")
		"siege_started":
			say("Night siege! %d infected are attacking a T%d barricade." % [int(event.get("count", 0)), int(event.get("tier", 1))])
		"guardian_taunt":
			say("Frontline guardian draws %d infected away from teammates!" % int(event.get("count", 0)))
		"spit_warning":
			say("ACID SPIT! Leave the green circle before it lands.")
		"spit_impact":
			say("Corrosive spit landed — the acid remains dangerous for 5 seconds!")
		"supply_drop":
			say("SUPPLY DROP T%d at X:%d Z:%d! %d guards. Full-loot PvP." % [
				int(event.get("tier", 3)), roundi(float(event.get("x", 0.0))),
				roundi(float(event.get("z", 0.0))), int(event.get("guards", 0))])
		"raid_started":
			say("RAID BOSS nearby! A mutant warlord entered the dangerous zone.")
		"raid_enraged":
			say("RAID PHASE TWO! The warlord is enraged. Dodge more frequent, stronger slams!")
		"raid_warning":
			say("RAID SLAM in %.1f seconds! Evade the marked %dm circle." % [
				float(event.get("seconds", 2.0)), int(event.get("radius", 5))])
		"raid_slam":
			say("Raid boss slam struck. Dodge or retreat from the next circle.")
		"raid_defeated":
			say("RAID VICTORY! The warlord dropped one shared loot bag.")
		"raid_expired":
			say("Raid boss retreated. The encounter is over.")
		"pvp_honor":
			say("PvP: +%d honor | %d total (%s)" % [int(event.get("earned", 0)),
				int(event.get("honor", 0)), str(event.get("rank", "Wanderer"))])
		"raid_reinforcements":
			say("RAID PHASE %d! %d additional infected appeared." % [
				int(event.get("phase", 1)), int(event.get("count", 0))])
		"scavenging":
			if event.get("peer", -1) == client.peer_id:
				say("+%d scavenging XP (rank %d)" % [
					int(event.get("xp", 0)), int(event.get("level", 1))])
		"crate":
			say("You search the crate...")
		"lockpick":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Lockpick consumed: sealed T%d compartment salvaged!" % int(event.get("tier", 3)))
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


func _claim_nearest_outpost_cache() -> void:
	if client.you.is_empty():
		return
	var position := Vector2(float(client.you.get("x", 0.0)),
		float(client.you.get("z", 0.0)))
	var nearest_id: int = -1
	var distance: float = 4.01
	for site in client.outposts:
		var at := Vector2(float(site["x"]), float(site["z"]))
		var separation: float = position.distance_to(at)
		if separation < distance:
			nearest_id = int(site["id"])
			distance = separation
	if nearest_id < 0:
		say("Outpost cache: move within 4 metres of a captured flag.")
	else:
		client.outpost_supplies(nearest_id)


func _on_result(kind: String, data: Dictionary) -> void:
	if kind == "party_standard":
		if bool(data.get("ok", false)):
			say("Rally standard raised: nearby allies recover stamina and combat energy for 90 seconds.")
		else:
			say("Rally standard: " + str(data.get("reason", "denied")))
		return
	if kind == "arena_queue":
		say("Arena queue: " + (str(data.get("status", "queued")) if bool(data.get("ok", false)) else str(data.get("reason", "denied"))))
		return
	if kind == "party_feast":
		if bool(data.get("ok", false)):
			say("Camp feast: shared T%d cooked fish with %d survivors." % [
				int(data.get("tier", 1)), int(data.get("served", 0))])
		else:
			say("Camp feast denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "infected_snare":
		say("Tripwire placed: will root the first non-boss infected that steps on it." if bool(data.get("ok", false)) else
			"Tripwire: " + str(data.get("reason", "rejected")))
		return
	if kind == "throw_decoy":
		say("Decoy deployed: nearby idle infected investigate the sound." if bool(data.get("ok", false)) else
				"Decoy denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "guardian_taunt":
		if bool(data.get("ok", false)):
			say("Guardian: drew %d infected; defensive brace for 3 seconds (-30%% infected damage)." % int(data.get("count", 0)))
		else:
			say("Guardian: " + str(data.get("reason", "rejected")))
		return
	if kind == "outpost_supplies":
		if bool(data.get("ok", false)):
			say("Outpost supplies collected! %d cache shares left. Inventory updated." % int(data.get("remaining", 0)))
		else:
			say("Outpost cache: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_aid":
		if bool(data.get("ok", false)):
			say("Field aid: +%d HP, -%d infection, -%d bleeding." % [
				roundi(float(data.get("heal", 0.0))),
				roundi(float(data.get("cure", 0.0))),
				roundi(float(data.get("bleeding_stopped", 0.0)))])
		else:
			say("Field aid denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "loot" and str(data.get("reason", "")) == "guards_alive":
		say("Cache sealed: eliminate %d infected guards." % int(data.get("remaining", 0)))
		return
	if kind == "loot" and str(data.get("reason", "")) == "raid_reserved":
		say("Raid loot is reserved for its contributors (%ds remaining)." % [
			int(ceil(float(data.get("remaining", 0.0))))])
		return
	if kind == "siege_declare":
		if bool(data.get("ok", false)):
			say("Siege declared! Prepare for %ds, attack within %ds." % [
				int(data.get("preparation", 0)), int(data.get("attack_window", 0))])
		else:
			say("Siege declaration: " + str(data.get("reason", "rejected")))
		return
	if kind == "outpost_breach":
		if bool(data.get("ok", false)):
			say("Siege breach successful: enemy fortification now T%d." % int(data.get("level", 0)))
		else:
			say("Siege breach: " + str(data.get("reason", "rejected")))
		return
	if kind == "outpost_fortify":
		if bool(data.get("ok", false)):
			say("Outpost fortified to T%d; spent %s" % [
				int(data.get("level", 0)), str(data.get("spent", {}))])
		else:
			say("Outpost fortification: " + str(data.get("reason", "rejected")))
		return
	if kind == "rally":
		if bool(data.get("ok", false)):
			say("Party rally active for 45 seconds. Only teammates see the marker.")
		else:
			say("Party rally: " + str(data.get("reason", "rejected")))
		return
	if kind == "party":
		if bool(data.get("ok", false)):
			say("Party updated. Member lists appear in the next server snapshot.")
		else:
			say("Party: " + str(data.get("reason", "rejected")))
		return
	if kind == "extinguish":
		if bool(data.get("ok", false)):
			say("Your campfire was extinguished. No fuel refunded.")
		else:
			say("Extinguish denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "refuel":
		if bool(data.get("ok", false)):
			say("Campfire fueled: %d seconds of warmth remain." % int(ceil(float(data.get("remaining", 0.0)))))
		else:
			say("Refuel denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "campfire":
		if bool(data.get("ok", false)):
			say("Campfire lit: shared warmth for 5 minutes.")
		else:
			say("Campfire: " + str(data.get("reason", "rejected")))
		return
	if kind == "drink":
		if bool(data.get("ok", false)):
			say("Lake: clean filtered drink" if bool(data.get("filtered", false)) else "Lake: unfiltered water increased infection")
		else:
			say("Lake: %s" % str(data.get("reason", "denied")))
		return
	if kind == "rest":
		if bool(data.get("ok", false)):
			say("Field respite: recovered by a safe campfire (90s cooldown)" if bool(data.get("field", false)) else "Hub rest: recovered (90s cooldown)")
		else:
			say("Camp rest: " + str(data.get("reason", "rejected")))
		return
	if kind == "fish":
		if bool(data.get("ok", false)):
			var fish_id: String = str(data.get("item", "raw_fish"))
			say("Fishing: %scasting for %s (%d s)..." % [
				"storm " if bool(data.get("storm_cast", false)) else (
					"baited " if bool(data.get("baited", false)) else ""),
				str(Defs.item(fish_id).get("name", fish_id)), int(data.get("seconds", 5))])
		else:
			say("Fishing: %s" % str(data.get("reason", "denied")))
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


## Shows the actual authoritative unit price formula; PvP infamy increases
## the price AFTER earned renown discount, and the result may change live.
func _refresh_vendor_price_labels() -> void:
	if _vendor_water_button == null or _vendor_food_button == null:
		return
	var points: int = int(client.you.get("renown", 0))
	var crime: float = float(client.you.get("pvp_infamy", 0.0))
	var water: int = PvpInfamy.vendor_unit_price(
		Reputation.buy_price(int(Vendor.BUY_PRICES["water_bottle"]), 1, points),
		crime, true)
	var food: int = PvpInfamy.vendor_unit_price(
		Reputation.buy_price(int(Vendor.BUY_PRICES["canned_food"]), 1, points),
		crime, true)
	_vendor_water_button.text = "Buy water (%d silver)" % water
	_vendor_food_button.text = "Buy food (%d silver)" % food


func _process(_delta: float) -> void:
	# Messages fade from the log after a while.
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _log_lines.is_empty() and now - _log_times[0] > 14.0:
		_log_lines.pop_front()
		_log_times.pop_front()
		_log.text = "\n".join(_log_lines)
		_log.visible = not _log_lines.is_empty()
	if client == null or not client.you.has("health"):
		return
	_refresh_vendor_price_labels()
	_bars["health"].value = client.you["health"]
	_bars["hunger"].value = client.you["hunger"]
	_bars["thirst"].value = client.you["thirst"]
	_bars["infection"].value = float(client.you.get("infection", 0.0))
	_bars["bleeding"].value = float(client.you.get("bleeding", 0.0))
	_bars["fracture"].value = float(client.you.get("fracture", 0.0))
	_bars["exposure"].value = float(client.you.get("exposure", 0.0))
	var zone: int = clampi(int(client.you.get("zone", 0)), 0, 3)
	_zone_label.text = "%s zone (T%d)\n%s" % [Defs.ZONE_NAMES[zone].capitalize(), zone + 1, ZoneRisk.description(zone)]
	var response_time: float = float(client.you.get("self_defense_seconds", 0.0))
	if response_time > 0.0:
		_info_label.text += "\nSELF-DEFENSE: %ds remaining" % ceili(response_time)
	var infamy: float = float(client.you.get("pvp_infamy", 0.0))
	if infamy > 0.0:
		_zone_label.text += "\n%s %d/100 | Vendor penalty" % [
			"OUTLAW" if PvpInfamy.is_outlaw(infamy) else "Infamy", ceili(infamy)]
	_zone_label.add_theme_color_override("font_color", [Color(0.4, 0.9, 0.4), Color(0.95, 0.85, 0.3), Color(0.95, 0.45, 0.3), Color(0.8, 0.3, 0.9)][zone])
	_info_label.text = "%s | FPS %d  kills %d  deaths %d  Load %.1f kg  Speed %.0f%%  Stamina %d  Dodge %.1fs  Guardian %.1fs  Brace %.1fs" % [
		"NIGHT" if WorldCycle.is_night(client.server_time) else "DAY", Engine.get_frames_per_second(), client.you.get("kills", 0), client.you.get("deaths", 0),
		float(client.you.get("carry_kg", 0.0)), 100.0 * float(client.you.get("cargo_factor", 1.0)),
		int(client.you.get("stamina", Defs.MAX_STAMINA)), float(client.you.get("dodge_cooldown", 0.0)),
		float(client.you.get("guardian_cooldown", 0.0)),
		float(client.you.get("guardian_brace", 0.0))
	]
	var guild: Dictionary = client.you.get("guild", {})
	if str(guild.get("id", "")) != "":
		var nearby_mates := 0
		for other in client.players.values():
			var tag: Dictionary = other.get("guild", {})
			if str(tag.get("id", "")) == str(guild["id"]):
				nearby_mates += 1
		_info_label.text += "\nGuild: %s | allies nearby: %d" % [
			str(guild.get("name", "")), nearby_mates
		]
		_info_label.text += " | Historic clan siege wins: %d" % int(client.you.get("guild_siege_wins", 0))
	if bool(client.you.get("warden_ward", false)):
		_info_label.text += "\nWARDEN'S WARD: -15% infected wounds (nearby relic ally)"
	_info_label.text += "\nStorm insulation %d%% (equipped armor)" % int(
		round(100.0 * float(client.you.get("weather_insulation", 0.0))))
	var visual: float = float(client.you.get("visual_signature", 1.0))
	if visual < 0.999:
		_info_label.text += "\nGHILLIE CAMOUFLAGE: infected visual range -%d%%" % [
			int(round(100.0 * (1.0 - visual)))]
	_info_label.text += "\nCAMP RENOWN %s: %d / %d | NPC buy discount %d%%" % [
		str(client.you.get("renown_rank", "Newcomer")),
		int(client.you.get("renown", 0)), int(client.you.get("renown_next", 40)),
		int(client.you.get("vendor_discount", 0))]
	var mask_seconds: float = float(client.you.get("scent_mask_seconds", 0.0))
	if mask_seconds > 0.0:
		_info_label.text += "\nSCENT MASK: %.0fs remaining (vision and hearing unchanged)" % mask_seconds
	var blood_range: float = float(client.you.get("blood_scent_radius", 0.0))
	if blood_range > 0.0:
		_info_label.text += "\nBLOOD SCENT: infected can sense the wound from %d m" % ceili(blood_range)
	var stim_remaining: float = float(client.you.get("stim_cooldown", 0.0))
	if stim_remaining > 0.0:
		_info_label.text += "\nFIELD STIM: recharge %.0fs" % stim_remaining
	var weather: Dictionary = client.you.get("weather", {})
	if not weather.is_empty():
		_info_label.text += "\nWeather: %s %.0fC %s | Exposure %d/100 | Heat pack %ds" % [
			str(weather.get("condition", "clear")).capitalize(),
			float(weather.get("temperature_c", 0.0)),
			"CAMPFIRE WARMTH" if bool(client.you.get("campfire_warm", false)) else ("SHELTERED" if bool(weather.get("sheltered", false)) else "EXPOSED"),
			int(client.you.get("exposure", 0.0)), int(ceil(float(client.you.get("warmth_seconds", 0.0))))
		]
	var journal: Variant = client.you.get("contract", Contracts.empty_state())
	_contract_label.text = Contracts.description(journal if journal is Dictionary else Contracts.empty_state())
	_contract_label.text += "\n" + str(client.you.get("daily_description", "Daily bounty pending server"))
	_info_label.text += "  Rest %.0fs" % float(client.you.get("rest_cooldown", 0.0))
	var combat_tag: float = float(client.you.get("combat_tag_seconds", 0.0))
	if combat_tag > 0.0:
		_info_label.text += "\nPvP COMBAT %.0fs — leaving a full-loot zone now drops gear!" % ceil(combat_tag)
	_info_label.text += "\nPvP victories %d | Honor %d | %s" % [
		int(client.you.get("pvp_kills", 0)), int(client.you.get("pvp_honor", 0)),
		str(client.you.get("pvp_rank", "Wanderer"))
	]
	_info_label.text += " | Arena %d %s (%dW / %dL)" % [
		int(client.you.get("arena_rating", 1200)), str(client.you.get("arena_tier", "Silver")),
		int(client.you.get("arena_wins", 0)), int(client.you.get("arena_losses", 0))]
	# A lightweight compass for siege outposts; all coordinates, owners and
	# progress originate in the authoritative snapshot, not client commands.
	var closest: Dictionary = {}
	var best_distance := INF
	var here := Vector2(float(client.you.get("x", 0.0)), float(client.you.get("z", 0.0)))
	for post in client.outposts:
		var distance: float = here.distance_to(Vector2(float(post["x"]), float(post["z"])))
		if distance < best_distance:
			best_distance = distance
			closest = post
	if not closest.is_empty():
		var group_id: int = int(client.you.get("party", {}).get("id", 0))
		var owner: int = int(closest["owner"])
		var status: String = "Neutral" if owner == 0 else ("YOURS" if owner == group_id and group_id != 0 else "Party %d" % owner)
		var owning_clan: Dictionary = closest.get("guild", {})
		if not owning_clan.is_empty():
			var my_clan: Dictionary = client.you.get("guild", {})
			if str(my_clan.get("id", "")) != "" and str(my_clan.get("id", "")) == str(owning_clan["id"]):
				status = "CLAN ALLY" if group_id != owner else "CLAN DEFENDERS"
			status += " | Clan: %s" % str(owning_clan["name"])
		if bool(closest["contested"]):
			status += " | CONTESTED"
		elif int(closest["challenger"]) != 0:
			status += " | Capture %d%%" % int(100.0 * float(closest["progress"]) / maxf(1.0, float(closest.get("capture_target", 30.0))))
		status += " | Fort T%d" % int(closest.get("fortification", 0))
		if str(closest.get("siege_phase", "")) != "":
			var pending: bool = str(closest["siege_phase"]) == "preparing"
			var seconds: int = int(ceil(float(closest["siege_starts_in"] if pending else closest["siege_ends_in"])))
			status += " | WAR %s %ds (party %d)" % [
				"prep" if pending else "active", seconds, int(closest["siege_attacker"])
			]
		if float(closest.get("breach_cooldown", 0.0)) > 0.0:
			status += " | Breach CD %ds" % int(ceil(float(closest["breach_cooldown"])))
		status += " | Supplies %d/5" % int(closest.get("supplies_left", 0))
		_info_label.text += "\nSiege outpost #%d at (%d, %d): %.0f m | %s" % [
			int(closest["id"]), int(closest["x"]), int(closest["z"]), best_distance, status
		]

	if int(client.you.get("siege_wins", 0)) > 0:
		_info_label.text += " | Siege victories: %d" % int(client.you["siege_wins"])
	var rally: Dictionary = client.you.get("party", {}).get("rally", {})
	if not rally.is_empty():
		_info_label.text += "\nPARTY RALLY x%d z%d | %ds left" % [
			int(rally["x"]), int(rally["z"]), int(ceil(float(rally["remaining"])))]
	var fishing_status: String = FishingDisplay.progress(client.you.get("action", {}))
	if not fishing_status.is_empty():
		_info_label.text += "\n" + fishing_status
	var weapon: String = client.you.get("weapon", "")
	var levels: Dictionary = client.you.get("gathering_levels", {})
	var weapon_levels: Dictionary = client.you.get("combat_levels", {})
	var active: Dictionary = Combat.active_skill(weapon)
	var skill_name: String = "None"
	if not active.is_empty():
		match str(active["id"]):
			"focused_shot":
				skill_name = "Focused Shot (G)"
			"power_draw":
				skill_name = "Power Draw (G)"
			"piercing_thrust":
				skill_name = "Piercing Thrust (G)"
			"purifying_slam":
				skill_name = "Purifying Slam (G)"
			"heavy_strike":
				skill_name = "Heavy Strike (G)"
	_equipped.text = "Weapon: %s | Craft L%d (%d XP)\nWood L%d | Stone L%d | Ore L%d | Fiber L%d | Fishing L%d | Scavenging L%d (%d XP)\nMastery: Melee L%d | Ranged L%d\nSkill: %s  Energy %d/%d  Cooldown %.1fs" % [
		(Defs.item(weapon).get("name", weapon) if weapon != "" else "fists"),
		int(client.you.get("crafting_level", 1)), int(client.you.get("crafting_xp", 0)),
		int(levels.get("wood", 1)), int(levels.get("stone", 1)),
		int(levels.get("ore", 1)), int(levels.get("fiber", 1)),
		int(levels.get("fishing", 1)),
		int(client.you.get("scavenging_level", 1)), int(client.you.get("scavenging_xp", 0)),
		int(weapon_levels.get("melee", 1)), int(weapon_levels.get("ranged", 1)),
		skill_name, int(client.you.get("combat_energy", 0)), int(Defs.COMBAT_ENERGY_MAX),
		float(client.you.get("skill_cooldown", 0.0))
	]
	var ranged_ammo: String = str(Defs.item(weapon).get("ammo", ""))
	if not ranged_ammo.is_empty():
		_equipped.text += "\nAmmo: %s ×%d" % [
			str(Defs.item(ranged_ammo).get("name", ranged_ammo)),
			client.inventory.count(ranged_ammo)]
	var meal_left: float = float(client.you.get("meal_seconds", 0.0))
	var meal_tier: int = int(client.you.get("meal_tier", 0))
	if meal_left > 0.0 and meal_tier > 0:
		_equipped.text += "\nPrepared meal T%d: %.0fs | +%.1f stamina/s, +%.2f energy/s" % [
			meal_tier, meal_left, HeartyMeal.stamina_per_second(meal_tier),
			HeartyMeal.energy_per_second(meal_tier)]
	_party_frames.text = PartyFrames.describe(client.you.get("party", {}), client.peer_id)
	_party_frames.visible = not _party_frames.text.is_empty()
	_death.visible = not bool(client.you.get("alive", true))
	_death.text = "YOU DIED\n%s" % ("All carried items dropped." if bool(client.you.get("last_death_full_loot", false)) else "Carried equipment retained.")
	if _inventory_panel.visible:
		_refresh_inventory()
		_refresh_trade_controls()
		_refresh_party_controls()
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


func _refresh_party_controls() -> void:
	var queue: Dictionary = client.you.get("arena_queue", {})
	if bool(queue.get("queued", false)):
		_arena_queue_status.text = "Finding rated match: %ds · ±%d Elo" % [
			ceili(float(queue.get("seconds", 0.0))), int(queue.get("search_gap", 125))]
	else:
		_arena_queue_status.text = "Ranked queue: not searching"
	var training: Dictionary = client.you.get("duel", {})
	if bool(training.get("active", false)):
		_duel_status.text = "%s with #%d — %ds" % [
			"Ranked" if bool(training.get("ranked", false)) else "Sparring",
			int(training.get("opponent", -1)), ceili(float(training.get("seconds", 0.0)))]
	elif int(training.get("invite_from", -1)) > 0:
		_duel_status.text = "%s challenge from #%d — %ds to accept" % [
			"Ranked" if bool(training.get("ranked", false)) else "Training",
			int(training.get("invite_from", -1)), ceili(float(training.get("seconds", 0.0)))]
	else:
		_duel_status.text = "No duel pending. Select a nearby survivor above."
	var state: Dictionary = client.you.get("party", {})
	var group_id: int = int(state.get("id", 0))
	var roster: Array = state.get("roster", [])
	var remaining_aid: float = float(client.you.get("party_aid_cooldown", 0.0))
	var remaining_feast: float = float(client.you.get("party_feast_cooldown", 0.0))
	if group_id == 0:
		_party_status.text = "No party. Invite someone nearby to start one."
	else:
		var names: PackedStringArray = []
		for member in roster:
			var prefix: String = "[Leader] " if int(member["id"]) == int(state.get("leader", 0)) else ""
			names.append("%s%s (%d HP)" % [prefix, str(member["name"]), int(member["health"])])
		_party_status.text = "Party %d (%d/5): %s" % [group_id, roster.size(), ", ".join(names)]
	if remaining_aid > 0.0:
		_party_status.text += "\nMedical aid ready in %.1f s" % remaining_aid
	if remaining_feast > 0.0:
		_party_status.text += "\nCamp feast ready in %.1f s" % remaining_feast
	if int(state.get("invite_from", 0)) > 0:
		_party_status.text += "\nInvitation from " + str(state.get("invite_name", "Survivor"))
	var standard: Dictionary = state.get("standard", {})
	if not standard.is_empty():
		_party_status.text += "\nRally standard: x%d z%d | %ds | +1.4 stamina/s, +0.8 energy/s" % [
			int(standard["x"]), int(standard["z"]),
			int(ceil(float(standard["remaining"])))]
		var standard_cooldown: float = float(standard.get("cooldown", 0.0))
		if standard_cooldown > 0.0:
			_party_status.text += " | next in %ds" % int(ceil(standard_cooldown))
	var rally: Dictionary = state.get("rally", {})
	if not rally.is_empty():
		_party_status.text += "\nRally: x%d z%d (%d seconds)" % [
			int(rally["x"]), int(rally["z"]), int(ceil(float(rally["remaining"])))]
	var nearby: Array = []
	for peer in client.players.values():
		nearby.append([int(peer["id"]), str(peer.get("name", "Survivor"))])
	nearby.sort_custom(func(a, b): return a[0] < b[0])
	var signature := str(nearby)
	if signature != _party_peer_signature:
		var selected: int = _party_target.get_selected_id()
		_party_peer_signature = signature
		_party_target.clear()
		for peer in nearby:
			_party_target.add_item("%s (#%d)" % [peer[1], peer[0]], peer[0])
			if peer[0] == selected:
				_party_target.select(_party_target.item_count - 1)


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
		var station_note := "  [bench]" if recipe["station"] == "workbench" else ("  [fire or bench]" if recipe["station"] == "campfire" else "")
		button.text = "%s  <-  %s%s" % [Defs.item(recipe["output"]).get("name", recipe["output"]), ", ".join(needs), station_note]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var required_tier: int = maxi(1, Defs.tier_of(String(recipe["output"])))
		var skill_locked: bool = required_tier > int(client.you.get("crafting_level", 1))
		button.disabled = not craftable.has(id) or skill_locked
		if skill_locked:
			button.text += "  [Craft Lv%d]" % required_tier
		button.pressed.connect(func() -> void: client.craft(id, 1))
		_craft_list.add_child(button)
