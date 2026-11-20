extends CanvasLayer
## All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

const Defs = preload("res://scripts/shared/defs.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const RaidCone = preload("res://scripts/shared/raid_cone.gd")
const Party = preload("res://scripts/shared/party.gd")
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")
const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const CraftingCatalog = preload("res://scripts/shared/crafting_catalog.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
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
var _caravan_status: Label
var _prompt: Label
var _log: Label
var _inventory_panel: PanelContainer
var _inventory_grid: GridContainer
var _stash_grid: GridContainer
var _craft_panel: PanelContainer
var _craft_list: VBoxContainer
var _craft_search: LineEdit
var _craft_ready_only: CheckBox
var _craft_result_count: Label
var _salvage_item: OptionButton
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
var _raid_loot_mode_button: Button
var _raid_vote_bag_id: int = -1
var _raid_vote_label: Label
var _raid_vote_need: Button
var _raid_vote_greed: Button
var _raid_vote_pass: Button
var _raid_skip_button: Button
var _raid_item_select: OptionButton
var _raid_claim_button: Button
var _raid_items_signature: String = ""
var _raid_skip_bag_id: int = -1
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
	for entry in [["health", Color(0.85, 0.2, 0.2)], ["hunger", Color(0.9, 0.65, 0.2)], ["thirst", Color(0.25, 0.55, 0.95)], ["infection", Color(0.54, 0.28, 0.65)], ["bleeding", Color(0.73, 0.21, 0.27)], ["fracture", Color(0.75, 0.48, 0.2)], ["exposure", Color(0.38, 0.7, 0.88)], ["wetness", Color(0.29, 0.52, 0.84)]]:
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
	# Keep the log left of the action bar: a fixed width and wrapped lines.
	_log.custom_minimum_size = Vector2(390, 0)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.max_lines_visible = 7
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
	var salvage_row := HBoxContainer.new()
	inventory_box.add_child(salvage_row)
	_salvage_item = OptionButton.new()
	_salvage_item.custom_minimum_size.x = 200.0
	_salvage_item.add_item("Select spare gear")
	_salvage_item.set_item_metadata(0, "")
	salvage_row.add_child(_salvage_item)
	var salvage_button := Button.new()
	salvage_button.text = "Recycle gear"
	salvage_button.tooltip_text = "Workbench only. Converts one unequipped weapon, armor or tool into materials."
	salvage_button.pressed.connect(func() -> void:
		var index: int = _salvage_item.selected
		if index < 0:
			say("Recycling: choose an unequipped item first.")
			return
		var item_id: String = str(_salvage_item.get_item_metadata(index))
		if item_id == "":
			say("Recycling: choose an unequipped item first.")
		else:
			client.salvage_gear(item_id))
	salvage_row.add_child(salvage_button)
	var campfire_button := Button.new()
	campfire_button.text = "Light field campfire (3 wood T1, 1 stone T1)"
	campfire_button.tooltip_text = "Shared warmth for 5 minutes, outside the safe settlement"
	campfire_button.pressed.connect(func() -> void:
		var pos: Vector3 = client.display_position()
		var direction := Vector2(sin(client.yaw), cos(client.yaw))
		client.light_campfire(Vector2(pos.x, pos.z) + direction * 2.8))
	inventory_box.add_child(campfire_button)
	var pitch_button := Button.new()
	pitch_button.name = "PitchTarp"
	pitch_button.text = "Pitch field tarp (2 cloth T1, 2 fiber T1, 1 plank T1)"
	pitch_button.tooltip_text = "4 minutes of shared weather cover (-75% exposure), no PvP immunity."
	pitch_button.pressed.connect(func() -> void:
		var position: Vector3 = client.display_position()
		var heading := Vector2(sin(client.yaw), cos(client.yaw))
		client.pitch_shelter(Vector2(position.x, position.z) + heading * 2.8))
	inventory_box.add_child(pitch_button)
	var pack_button := Button.new()
	pack_button.name = "PackTarp"
	pack_button.text = "Pack nearest tarp (owner only; no refund)"
	pack_button.pressed.connect(func() -> void:
		var shelter_id: int = client.nearest_shelter(client.display_position())
		if shelter_id < 0:
			say("No field tarp within reach.")
		else:
			client.pack_shelter(shelter_id))
	inventory_box.add_child(pack_button)
	var decoy_button := Button.new()
	decoy_button.name = "ThrowNoiseDecoy"
	decoy_button.text = "Throw clattering decoy (,): 8s distraction"
	decoy_button.tooltip_text = "Needs a crafted decoy: 2 wood T1 + 1 scrap"
	decoy_button.pressed.connect(func() -> void:
		var heading := Vector2(sin(client.yaw), cos(client.yaw))
		client.throw_decoy(heading))
	inventory_box.add_child(decoy_button)
	var flash_button := Button.new()
	flash_button.name = "ThrowFlashCharge"
	flash_button.text = "Throw flash charge (PvE interrupt)"
	flash_button.tooltip_text = "8m throw, up to 4 infected at impact. Bosses immune. Loud; 12-second cooldown."
	flash_button.pressed.connect(func() -> void:
		client.throw_flash(Vector2(sin(client.yaw), cos(client.yaw))))
	inventory_box.add_child(flash_button)
	var smoke_button := Button.new()
	smoke_button.name = "UseSmokeCharge"
	smoke_button.text = "Smoke charge (F9): nine-second sight cover"
	smoke_button.tooltip_text = "Consumes 1 crafted charge. Quiet survivors are less visible; no PvP or damage protection."
	smoke_button.pressed.connect(func() -> void: client.use_item("smoke_charge"))
	inventory_box.add_child(smoke_button)
	var snare_button := Button.new()
	snare_button.name = "PlaceInfectedSnare"
	snare_button.text = "Place infected tripwire (\\): roots one infected"
	snare_button.tooltip_text = "Requires one crafted snare; outside safe zones, up to 3 deployed per survivor."
	snare_button.pressed.connect(func() -> void:
		var at: Vector3 = client.display_position()
		var face := Vector2(sin(client.yaw), cos(client.yaw))
		client.place_infected_snare(Vector2(at.x, at.z) + face * 2.8))
	inventory_box.add_child(snare_button)
	var fish_trap_button := Button.new()
	fish_trap_button.name = "PlaceShoreFishTrap"
	fish_trap_button.text = "Deploy shoreline fish trap (F10)"
	fish_trap_button.tooltip_text = "One crafted trap + a real rod near water. Collect 2 fish after 120s."
	fish_trap_button.pressed.connect(func() -> void: client.place_fish_trap())
	inventory_box.add_child(fish_trap_button)
	var collect_fish_button := Button.new()
	collect_fish_button.name = "CollectShoreFishTrap"
	collect_fish_button.text = "Collect nearest fish trap (F12)"
	collect_fish_button.pressed.connect(func() -> void:
		var id: int = client.nearest_fish_trap(client.display_position())
		if id == -1:
			say("No fish trap within reach of the shore.")
		else:
			client.collect_fish_trap(id))
	inventory_box.add_child(collect_fish_button)
	var alkali_button := Button.new()
	alkali_button.name = "UseFieldAlkaliKit"
	alkali_button.text = "Neutralize nearby acid pools (1 kit, up to 3)"
	alkali_button.tooltip_text = "Clears lingering spitter acid within 5.5 m, not the initial splash."
	alkali_button.pressed.connect(func() -> void: client.use_item("field_alkali_kit"))
	inventory_box.add_child(alkali_button)
	var canteen_button := Button.new()
	canteen_button.name = "RefillFieldCanteen"
	canteen_button.text = "Refill canteen at shore (1 filter -> 1 clean water)"
	canteen_button.tooltip_text = "Requires a crafted canteen, one carbon filter and the shared lake cooldown."
	canteen_button.pressed.connect(func() -> void: client.refill_canteen())
	inventory_box.add_child(canteen_button)
	var storm_button := Button.new()
	storm_button.name = "EquipStormInsulator"
	storm_button.text = "Equip storm insulation (180s)"
	storm_button.tooltip_text = "Workbench craft: 1 bar T2, 2 cloth T2, 2 scrap. Consumed kit reduces lightning damage 60%, not PvP/infected."
	storm_button.pressed.connect(func() -> void: client.use_item("storm_insulator"))
	inventory_box.add_child(storm_button)
	var survey_button := Button.new()
	survey_button.name = "RuinSurveyChart"
	survey_button.text = "Survey dangerous ruins (F3; 1 crafted chart)"
	survey_button.tooltip_text = "Mark nearest unopened red/black ruin within 190 m for 75s."
	survey_button.pressed.connect(func() -> void: client.survey_ruins())
	inventory_box.add_child(survey_button)
	var scanner_button := Button.new()
	scanner_button.name = "UseFieldThreatScanner"
	scanner_button.text = "Scan elite / raid threats (145m; 1 crafted scanner)"
	scanner_button.tooltip_text = "Workbench craft (3 scrap, T2 bar, filter). One successful scan privately marks a living raid boss or elite for 50s."
	scanner_button.pressed.connect(func() -> void: client.use_item("field_threat_scanner"))
	inventory_box.add_child(scanner_button)
	var chain_button := Button.new()
	chain_button.name = "UseBikeChainWrap"
	chain_button.text = "Quiet bike chain (180s; workbench craft)"
	chain_button.tooltip_text = "Dismount and use 1 wrap: bike noise 27m -> 9m, gunshots unaffected."
	chain_button.pressed.connect(func() -> void: client.use_item("bike_chain_wrap"))
	inventory_box.add_child(chain_button)
	var tires_button := Button.new()
	tires_button.name = "FitTrailTireGrips"
	tires_button.text = "Fit off-road tire grips (240s; workbench craft)"
	tires_button.tooltip_text = "Fit 1 crafted kit to owned bike while dismounted; improves grip in mud, sand, forests, mountains."
	tires_button.pressed.connect(func() -> void: client.use_item("trail_tire_grips"))
	inventory_box.add_child(tires_button)
	var service_button := Button.new()
	service_button.name = "ServiceBikeDrive"
	service_button.text = "Service bicycle drive (800 m; PgUp)"
	service_button.tooltip_text = "Use a crafted drive service kit while dismounted; quiet riding for 800m, less off-road."
	service_button.pressed.connect(func() -> void: client.use_item("bike_service_kit"))
	inventory_box.add_child(service_button)
	var frame_button := Button.new()
	frame_button.name = "RepairBikeFrame"
	frame_button.text = "Patch bicycle frame (+45%; PgDn)"
	frame_button.tooltip_text = "Craft a frame patch at a workbench. Dismount to repair a damaged or broken bicycle."
	frame_button.pressed.connect(func() -> void: client.use_item("bike_frame_patch"))
	inventory_box.add_child(frame_button)
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
	var bulk_button := Button.new()
	bulk_button.name = "DepositAllMaterials"
	bulk_button.text = "BANK ALL: resources + crafting materials"
	bulk_button.tooltip_text = "At the hub workbench. Moves only raw/refined resources into your protected stash. Food, water, medicine, silver, gear and tools remain carried. Partial deposits are allowed if the bank is nearly full."
	bulk_button.pressed.connect(func() -> void: client.deposit_materials())
	inventory_box.add_child(bulk_button)

	var flare_button := Button.new()
	flare_button.name = "UseSignalFlare"
	flare_button.text = "Light signal flare: 120s (F2 offline)"
	flare_button.tooltip_text = "Crafted fuel: night-only glow also alerts nearby infected."
	flare_button.pressed.connect(func() -> void: client.use_item("signal_flare"))
	inventory_box.add_child(flare_button)
	var edge_oil_button := Button.new()
	edge_oil_button.name = "AntisepticEdgeOil"
	edge_oil_button.text = "Coat melee weapon: +20% infected damage for 120s (Shift+6)"
	edge_oil_button.tooltip_text = "Craft at workbench from 1 spore culture + antiseptic + scrap. No PvP or raid boss buff."
	edge_oil_button.pressed.connect(func() -> void: client.use_item("antiseptic_edge_oil"))
	inventory_box.add_child(edge_oil_button)
	var recall_button := Button.new()
	recall_button.name = "UseReturnCharm"
	recall_button.text = "Return charm: 8s channel (green/yellow only)"
	recall_button.tooltip_text = "Craft at workbench. Movement, combat or nearby infected cancels without spending."
	recall_button.pressed.connect(func() -> void: client.use_item("return_charm"))
	inventory_box.add_child(recall_button)
	var rest_button := Button.new()
	rest_button.text = "Rest: safe hub or a lit field campfire"
	rest_button.tooltip_text = "Hub: 2 wood + canned food + water. Fire: cooked fish/canned ration + water, no nearby threats; 90s cooldown."
	rest_button.pressed.connect(Callable(client, "rest"))
	inventory_box.add_child(rest_button)

	var vendor_title := Label.new()
	vendor_title.text = "NPC vendor (hub or village workbench)"
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

	var caravan_heading := Label.new()
	caravan_heading.text = "Caravan routes (village-to-village trading)"
	inventory_box.add_child(caravan_heading)
	_caravan_status = Label.new()
	_caravan_status.text = "No active route. Find an NPC trader in a wilderness village or fort."
	_caravan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_caravan_status)
	var caravan_buttons := HBoxContainer.new()
	inventory_box.add_child(caravan_buttons)
	var accept_caravan := Button.new()
	accept_caravan.text = "Take route"
	accept_caravan.pressed.connect(func() -> void: client.caravan("accept"))
	caravan_buttons.add_child(accept_caravan)
	var deliver_caravan := Button.new()
	deliver_caravan.text = "Deliver cargo"
	deliver_caravan.pressed.connect(func() -> void: client.caravan("deliver"))
	caravan_buttons.add_child(deliver_caravan)
	var abandon_caravan := Button.new()
	abandon_caravan.text = "Cancel route"
	abandon_caravan.pressed.connect(func() -> void: client.caravan("abandon"))
	caravan_buttons.add_child(abandon_caravan)

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
	var rain_button := Button.new()
	rain_button.name = "CollectStormWater"
	rain_button.text = "Collect rainwater (1 crafted tarp -> 2 bottles)"
	rain_button.tooltip_text = "Outdoors in a storm; swamps also consume 1 charcoal filter. 90s cooldown."
	rain_button.pressed.connect(func() -> void: client.collect_rain())
	inventory_box.add_child(rain_button)
	var spores_button := Button.new()
	spores_button.name = "CollectSporeCultures"
	spores_button.text = "Sample swamp spores (1 kit -> 2 cultures)"
	spores_button.tooltip_text = "Dangerous swamp only. Causes infection; 150s cooldown. Distill antidote at a workbench."
	spores_button.pressed.connect(func() -> void: client.sample_spores())
	inventory_box.add_child(spores_button)
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
	var delivery := Button.new()
	delivery.name = "OutpostProvisions"
	delivery.text = "Deliver supplies to outpost (+45s hold)"
	delivery.tooltip_text = "Costs 2 canned food, 2 water bottles, 4 wood. Max 4 deliveries per capture, unavailable when contested."
	delivery.pressed.connect(_deliver_nearest_outpost_provisions)
	inventory_box.add_child(delivery)

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
	var ready_buttons := HBoxContainer.new()
	inventory_box.add_child(ready_buttons)
	var start_ready := Button.new()
	start_ready.text = "Start ready check"
	start_ready.tooltip_text = "Party leader: ask all members whether they are prepared for a raid."
	start_ready.pressed.connect(func() -> void: client.party_ready_start())
	ready_buttons.add_child(start_ready)
	var vote_ready := Button.new()
	vote_ready.text = "I'm ready"
	vote_ready.pressed.connect(func() -> void: client.party_ready_answer(true))
	ready_buttons.add_child(vote_ready)
	var vote_not_ready := Button.new()
	vote_not_ready.text = "Not ready"
	vote_not_ready.pressed.connect(func() -> void: client.party_ready_answer(false))
	ready_buttons.add_child(vote_not_ready)
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
	_raid_loot_mode_button = Button.new()
	_raid_loot_mode_button.text = "Raid loot: Free"
	_raid_loot_mode_button.tooltip_text = "Leader: cycle future raid loot Free, Round robin, and Need/Greed (cores). Existing bags never change."
	_raid_loot_mode_button.pressed.connect(func() -> void:
		var current: String = str(client.you.get("party", {}).get("loot_mode", "free"))
		var next: String = "round_robin" if current == "free" else (
			"need_greed" if current == "round_robin" else "free")
		client.party_loot_mode(next))
	inventory_box.add_child(_raid_loot_mode_button)
	_raid_vote_label = Label.new()
	_raid_vote_label.text = "No active Need/Greed raid trophy ballot nearby."
	_raid_vote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_raid_vote_label)
	var vote_row := HBoxContainer.new()
	inventory_box.add_child(vote_row)
	_raid_vote_need = Button.new()
	_raid_vote_need.text = "Need"
	_raid_vote_need.tooltip_text = "Priority roll for raid infected cores; one vote per eligible contributor."
	_raid_vote_greed = Button.new()
	_raid_vote_greed.text = "Greed"
	_raid_vote_greed.tooltip_text = "Roll only if no contributor votes Need."
	_raid_vote_pass = Button.new()
	_raid_vote_pass.text = "Pass trophy"
	_raid_vote_pass.tooltip_text = "Decline the infected core roll. Vote cannot be changed."
	for option in [_raid_vote_need, _raid_vote_greed, _raid_vote_pass]:
		option.disabled = true
		vote_row.add_child(option)
	_raid_vote_need.pressed.connect(func() -> void:
		if _raid_vote_bag_id > 0:
			client.raid_vote(_raid_vote_bag_id, "need"))
	_raid_vote_greed.pressed.connect(func() -> void:
		if _raid_vote_bag_id > 0:
			client.raid_vote(_raid_vote_bag_id, "greed"))
	_raid_vote_pass.pressed.connect(func() -> void:
		if _raid_vote_bag_id > 0:
			client.raid_vote(_raid_vote_bag_id, "pass"))
	_raid_skip_button = Button.new()
	_raid_skip_button.text = "Pass raid turn"
	_raid_skip_button.tooltip_text = "If it is your round-robin turn and you are beside the raid bag, give the next contributor a turn without taking loot."
	_raid_skip_button.disabled = true
	_raid_skip_button.pressed.connect(func() -> void:
		if _raid_skip_bag_id > 0:
			client.raid_skip_turn(_raid_skip_bag_id))
	inventory_box.add_child(_raid_skip_button)
	var raid_choice_row := HBoxContainer.new()
	inventory_box.add_child(raid_choice_row)
	_raid_item_select = OptionButton.new()
	_raid_item_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_raid_item_select.disabled = true
	_raid_item_select.tooltip_text = "Choose one type of available boss loot on your round-robin turn."
	raid_choice_row.add_child(_raid_item_select)
	_raid_claim_button = Button.new()
	_raid_claim_button.text = "Claim selected"
	_raid_claim_button.disabled = true
	_raid_claim_button.pressed.connect(func() -> void:
		if _raid_skip_bag_id > 0 and _raid_item_select.selected >= 0:
			client.raid_claim_selected(_raid_skip_bag_id, str(_raid_item_select.get_selected_metadata())))
	raid_choice_row.add_child(_raid_claim_button)
	var focus_button := Button.new()
	focus_button.text = "Focus infected"
	focus_button.tooltip_text = "Leader: mark the nearest living infected within 24m for 18s. Allies near that exact enemy deal +8% PvE damage; 28s cooldown."
	focus_button.pressed.connect(func() -> void: client.party_focus())
	inventory_box.add_child(focus_button)
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
	var parry_button := Button.new()
	parry_button.name = "MeleeParry"
	parry_button.text = "Parry incoming infected (F8)"
	parry_button.tooltip_text = "Hold real melee weapon; 20 stamina, 0.45s timing window, 4s cooldown. Front infected melee only."
	parry_button.pressed.connect(func() -> void: client.parry())
	inventory_box.add_child(parry_button)
	var finisher_button := Button.new()
	finisher_button.name = "StaggerFinisher"
	finisher_button.text = "Finish staggered infected (Shift+G)"
	finisher_button.tooltip_text = "Real melee weapon, 24 combat energy, stunned enemy in front, 6s cooldown."
	finisher_button.pressed.connect(func() -> void: client.stagger_finisher())
	inventory_box.add_child(finisher_button)
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
	aid_button.tooltip_text = "Use one medical item to treat a nearby party member; 5s cooldown. Restored HP generates infected threat if your ally is in combat."
	aid_button.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target < 0 or aid_items.selected < 0:
			say("Aid: select a nearby party member and a medical item.")
		else:
			client.party_aid(target, str(aid_items.get_selected_metadata())))
	aid_row.add_child(aid_button)
	var triage_button := Button.new()
	triage_button.text = "Triage nearby allies"
	triage_button.tooltip_text = "Spend one crafted pack to treat up to 3 nearby allies (5.5m, 18s cooldown). Infected fighting them may turn toward the medic."
	triage_button.pressed.connect(func() -> void: client.party_triage())
	inventory_box.add_child(triage_button)
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
	_market_status.text = "Refresh to browse listings. %d%% seller tax on successful sales." % MarketBoard.SALE_TAX_PERCENT
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
	craft_title.text = "Crafting (workbench in the hub or a village, or a held PvP outpost field bench)"
	craft_box.add_child(craft_title)
	var craft_controls := HBoxContainer.new()
	craft_box.add_child(craft_controls)
	_craft_search = LineEdit.new()
	_craft_search.placeholder_text = "Find item or ingredients..."
	_craft_search.custom_minimum_size = Vector2(230, 0)
	_craft_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_search.text_changed.connect(func(_value: String) -> void:
		_craft_signature = ""
		_refresh_crafting())
	craft_controls.add_child(_craft_search)
	_craft_ready_only = CheckBox.new()
	_craft_ready_only.text = "Materials + level"
	_craft_ready_only.tooltip_text = "Only recipes with enough ingredients, inventory room and crafting level. A workbench or campfire may still be needed."
	_craft_ready_only.toggled.connect(func(_value: bool) -> void:
		_craft_signature = ""
		_refresh_crafting())
	craft_controls.add_child(_craft_ready_only)
	_craft_result_count = Label.new()
	craft_box.add_child(_craft_result_count)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(615, 380)
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
	_arrange_inventory_window()



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
		_inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		client.market_list()


## The inventory window holds the backpack, the stash and dozens of actions added over time. Lay it out as two columns:
## the backpack and stash on the left, every action in a scrolling list on the right, centred and always on screen.
func _arrange_inventory_window() -> void:
	var box: VBoxContainer = _inventory_panel.get_child(0)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(390, 0)
	var header := Label.new()
	header.text = "BACKPACK"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))
	left.add_child(header)
	var hint := Label.new()
	hint.text = "Click: use or equip.  Right click: stash one (at a workbench)."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	left.add_child(hint)
	var stash_scroll: Control = _stash_grid.get_parent()
	var stash_title: Control = box.get_child(stash_scroll.get_index() - 1)
	for moved in [_inventory_grid, stash_title, stash_scroll,
			box.get_node("DepositAllMaterials")]:
		moved.get_parent().remove_child(moved)
		left.add_child(moved)
	(stash_title as Label).text = "PROTECTED STASH  (survives death; click to take one at a workbench)"
	(stash_title as Label).add_theme_font_size_override("font_size", 12)
	(stash_title as Label).add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	stash_scroll.custom_minimum_size = Vector2(380, 150)
	var right := VBoxContainer.new()
	var actions_title := Label.new()
	actions_title.text = "ACTIONS"
	actions_title.add_theme_font_size_override("font_size", 18)
	actions_title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))
	right.add_child(actions_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_inventory_panel.remove_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	# The old one-line title is replaced by the column headers.
	if box.get_child_count() > 0 and box.get_child(0) is Label:
		box.get_child(0).queue_free()
	# Long action labels wrap instead of widening the window.
	for button in box.find_children("*", "Button", true, false):
		if button is OptionButton:
			continue
		(button as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(button as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
		(button as Button).add_theme_font_size_override("font_size", 12)
	columns.add_child(left)
	columns.add_child(right)
	_inventory_panel.add_child(columns)


func toggle_crafting() -> void:
	_craft_panel.visible = not _craft_panel.visible


func is_menu_open() -> bool:
	return _inventory_panel.visible or _craft_panel.visible


func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = not text.is_empty() # An empty pill would sit over the action bar.


## A big announcement in the middle of the screen (level ups, places you enter).
func banner(text: String, color: Color = Color(0.95, 0.78, 0.35)) -> void:
	if _skin != null:
		_skin.banner(text, color)


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
		"caravan_escort_paid":
			say("Convoy escort complete: +%d silver, Explorer XP and renown earned." % [
				int(event.get("silver", 0))])
		"caravan_defended":
			say("CARAVAN DEFENDED! All attackers defeated. Earn 15% extra silver on delivery.")
		"caravan_ambushed":
			if int(event.get("peer", 0)) == client.peer_id:
				say("CARAVAN AMBUSH! %d infected are converging on your cargo. Defend or flee!" % [
					int(event.get("count", 0))])
			else:
				say("ESCORT ALERT! Party courier attacked by %d infected. Regroup!" % [
					int(event.get("count", 0))])
		"site_discovered":
			say("DISCOVERED: %s · %d island landmarks visited! Explorer XP and renown earned." % [
				str(event.get("name", "Unknown")), int(event.get("count", 0))])
		"recall_started":
			say("Return charm: stand still for 8 seconds; avoid infected.")
		"recall_cancelled":
			say("Return interrupted (%s); charm preserved." % str(event.get("reason", "cancelled")))
		"recall_completed":
			say("Returned to the safe hub. One charm consumed.")
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
		"barricade_shot":
			if int(event.get("peer", -1)) == client.peer_id:
				say("BARRICADE HIT: -%d HP (remaining %d)." % [
					roundi(float(event.get("damage", 0.0))),
					roundi(float(event.get("hp", 0.0)))])
		"outlaw_bounty":
			if int(event.get("peer", -1)) == client.peer_id:
				say("OUTLAW BOUNTY: +%d silver for a wanted survivor." % int(event.get("silver", 0)))
		"party_triage":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Triage care received: +%d HP, -%d bleeding." % [
					roundi(float(event.get("heal", 0.0))),
					roundi(float(event.get("bleeding_stopped", 0.0)))])
		"party_aid":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Teammate treated you: +%d HP, -%d infection, -%d bleeding, -%d fracture." % [
					roundi(float(event.get("heal", 0.0))),
					roundi(float(event.get("cure", 0.0))),
					roundi(float(event.get("bleeding_stopped", 0.0))),
					roundi(float(event.get("fracture_treated", 0.0)))])
		"gathered":
			var harvest_extra: int = int(event.get("outpost_bonus", 0))
			say("+%d %s%s" % [event["amount"],
				Defs.item(event["item"]).get("name", event["item"]),
				" (outpost +%d)" % harvest_extra if harvest_extra > 0 else ""])
		"lightning_warning":
			say("THUNDERSTORM: lightning landing nearby — step out of the purple circle!")
		"lightning_struck":
			say("Lightning hit the ground! Moving away or dodging avoids the bolt.")
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
		"parried":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Parried infected attack! 70% less damage and wounds; enemy staggered.")
		"stealth_ambush":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Silent ambush! +45% melee damage against unaware infected.")
		"hit":
			if event.get("id", -1) == client.peer_id and event.get("kind", "") == "player":
				say("-%d health" % int(event["damage"]))
		"infection":
			if event.get("peer", -1) == client.peer_id:
				say("Infected wound: severity %d. Use antiseptic or antibiotics." % int(event.get("severity", 0)))
		"spore_enter":
			if int(event.get("peer", -1)) == client.peer_id:
				say("SPORE SWAMP: airborne infection! Use a field filter, sealed suit, or leave.")
		"spore_exit":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Clean air: escaped the infected spores.")
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
		"outpost_watch":
			say("WATCHTOWER ALERT: enemies at your fortified outpost #%d (X:%d Z:%d)! Rally defenders." % [
				int(event.get("id", 0)), roundi(float(event.get("x", 0.0))),
				roundi(float(event.get("z", 0.0)))])
		"siege_charge_armed":
			say("SIEGE CHARGE ARMED! Enemy wall will explode in %.0f seconds." %
				float(event.get("seconds", 4.0)))
		"siege_charge_detonated":
			if bool(event.get("broken", false)):
				say("SIEGE BREACH! Enemy barricade destroyed.")
			else:
				say("SIEGE BLAST: -%d wall HP, %d remains." % [
					roundi(float(event.get("damage", 0.0))),
					roundi(float(event.get("hp", 0.0)))])
		"siege_charge_fizzled":
			say("Siege charge detonated, but its target was already gone.")
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
		"raid_cone_warning":
			say("RAID CLEAVE in %.1fs! Move sideways out of the marked frontal sector." % float(event.get("seconds", 2.2)))
		"raid_cone_struck":
			say("Raid frontal cleave struck. Watch the boss's facing for the next sweep.")
		"raid_warning":
			say("RAID SLAM in %.1f seconds! Evade the %dm circle or coordinate attacks to interrupt." % [
				float(event.get("seconds", 2.0)), int(event.get("radius", 5))])
		"raid_interrupted":
			say("RAID INTERRUPTED! Two allies broke the slam. Boss exposed for %.1fs: +15%% damage!" % float(event.get("exposed_seconds", 0.0)))
		"raid_slam":
			var exposed: float = float(event.get("exposed_seconds", 0.0))
			if exposed > 0.0:
				say("RAID COUNTERATTACK! Boss exposed for %.1fs: +15%% damage. Strike now!" % exposed)
			else:
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


func _deliver_nearest_outpost_provisions() -> void:
	if client.you.is_empty():
		return
	var pos := Vector2(float(client.you.get("x", 0.0)), float(client.you.get("z", 0.0)))
	var nearest := -1
	var best := 4.01
	for flag in client.outposts:
		var distance := pos.distance_to(Vector2(float(flag["x"]), float(flag["z"])))
		if distance < best:
			best = distance
			nearest = int(flag["id"])
	if nearest < 0:
		say("Supplies: move within 4 metres of your outpost.")
	else:
		client.outpost_provision(nearest)


func _on_result(kind: String, data: Dictionary) -> void:
	if kind == "use" and bool(data.get("threat_scan", false)):
		if bool(data.get("ok", false)):
			say("SCOUT: %s threat at X:%d Z:%d — private moving marker for %ds." % [
				str(data.get("kind", "elite")).to_upper(),
				roundi(float(data.get("x", 0.0))),
				roundi(float(data.get("z", 0.0))),
				int(data.get("seconds", 50))])
		else:
			say("Threat scanner: %s (device not spent)." % str(
				data.get("reason", "rejected")))
		return
	if kind == "use" and data.has("storm_insulator_seconds"):
		say("Copper shock lining active for 180s: -60% lightning damage.")
		return
	if kind == "use" and bool(data.get("storm_insulator", false)):
		say("Storm insulation: " + str(data.get("reason", "rejected")) + " (kit not spent)")
		return
	if kind == "use" and data.has("coating_seconds"):
		say("Coated %s: +20%% vs regular/elite infected for %.0fs. Unequipping ends the effect." % [
			str(data.get("coating_weapon", "melee weapon")),
			float(data["coating_seconds"])])
		return
	if kind == "use" and str(data.get("reason", "")) in ["need_melee", "already_coated"] and (
			client.inventory.count("antiseptic_edge_oil") > 0):
		say("Weapon coating: " + str(data["reason"]) + " (oil not spent)")
		return
	if kind == "attack" and bool(data.get("riposte", false)):
		say("RIPOSTE! Perfect parry converted into a powerful counterstrike.")
		return
	if kind == "stagger_finisher":
		if bool(data.get("ok", false)):
			say("Stagger finisher: %d damage%s, %.0fs cooldown." % [
				roundi(float(data.get("damage", 0.0))),
				" (infected defeated!)" if bool(data.get("killed", false)) else "",
				float(data.get("cooldown", 6.0))])
		else:
			say("Stagger finisher: " + str(data.get("reason", "rejected")))
		return
	if kind == "use" and data.has("tire_grip_seconds"):
		say("Off-road tire grips fitted: %.0fs of improved traction." % float(data["tire_grip_seconds"]))
		return
	if kind == "use" and bool(data.get("tire_grips", false)):
		say("Tire grips: " + str(data.get("reason", "rejected")) + " (kit not spent)")
		return
	if kind == "caravan":
		if not bool(data.get("ok", false)):
			say("Caravan: " + str(data.get("reason", "unavailable")))
		else:
			match str(data.get("action", "")):
				"accept":
					var route: Dictionary = data.get("route", {})
					say("NEW CARAVAN: deliver %dx %s to %s (X:%d Z:%d) for %d silver." % [
						int(route.get("quantity", 0)), str(route.get("cargo", "")),
						str(route.get("destination", "")), roundi(float(route.get("dst_x", 0.0))),
						roundi(float(route.get("dst_z", 0.0))), int(route.get("silver", 0))])
				"deliver":
					var shares: Array = data.get("escorts", [])
					var bonus: int = int(data.get("defense_bonus", 0))
					if shares.is_empty():
						say("Caravan delivered: +%d silver (defense bonus +%d), Explorer XP." % [
							int(data.get("silver", 0)), bonus])
					else:
						say("Caravan delivered: +%d silver (defense +%d), paid %d escort(s) from base fare." % [
							int(data.get("silver", 0)), bonus, shares.size()])
				"abandon":
					say("Caravan route cancelled; no goods taken.")
		return
	if kind == "throw_flash":
		if bool(data.get("ok", false)):
			say("Flash charge interrupted %d infected; blast attracts attention." % int(data.get("hits", 0)))
		elif str(data.get("reason", "")) == "cooldown":
			say("Flash charge ready in %ds" % ceili(float(data.get("remaining", 0.0))))
		else:
			say("Flash charge: " + str(data.get("reason", "rejected")) + " (kit not spent)")
		return
	if kind == "sample_spores":
		if bool(data.get("ok", false)):
			say("Spore sample: %d cultures collected; infection +%.1f." % [
				int(data.get("count", 0)), float(data.get("infection", 0.0))])
		elif str(data.get("reason", "")) == "cooldown":
			say("Spore sampling: ready in %ds" % ceili(float(data.get("remaining", 0.0))))
		else:
			say("Spore sampling: " + str(data.get("reason", "rejected")))
		return
	if kind == "use" and data.has("flare_seconds"):
		say("Signal flare burning for 120s; infected and rival survivors see its light.")
		return
	if kind == "use" and str(data.get("reason", "")) in ["already_burning", "daylight"]:
		say("Flare cannot ignite: %s (nothing consumed)." % str(data["reason"]))
		return
	if kind == "use" and data.has("smoke_seconds"):
		say("Smoke deployed for nine seconds. Noise and blood scent still reveal you.")
		return
	if kind == "parry":
		if bool(data.get("ok", false)):
			say("Parry ready for 0.45s. Face the infected and time its strike!")
		else:
			say("Parry denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "survey_ruins":
		if bool(data.get("ok", false)):
			say("Ruin survey: T%d cache at X:%d Z:%d — private marker for 75s." % [
				int(data.get("zone", 2)) + 1,
				roundi(float(data.get("x", 0.0))), roundi(float(data.get("z", 0.0)))])
		else:
			say("Ruin survey: " + str(data.get("reason", "denied")) + " (chart not spent).")
		return
	if kind == "use" and data.has("chain_wrap_seconds"):
		say("Quiet bike chain fitted: %.0fs quieter riding." % float(data["chain_wrap_seconds"]))
		return
	if kind == "use" and bool(data.get("chain_wrap", false)):
		say("Bike chain wrap: " + str(data.get("reason", "rejected")) + " (no kit spent)")
		return
	if kind == "outpost_provision":
		if bool(data.get("ok", false)):
			say("Outpost supplied: +%ds hold time, %d deliveries left." % [
				int(data.get("extra_seconds", 0)), int(data.get("remaining_deliveries", 0))])
		else:
			say("Outpost supplies: " + str(data.get("reason", "rejected")))
		return
	if kind == "use" and data.has("recall_cast"):
		say("Return charm: casting for %d seconds." % int(data["recall_cast"]))
		return
	if kind == "use" and str(data.get("reason", "")) in ["full_loot_zone", "already_home",
			"cooldown", "infected_nearby", "in_combat", "recall_channeling", "in_duel"]:
		say("Cannot recall: %s (no charm spent)." % str(data["reason"]))
		return
	if kind == "collect_rain":
		if bool(data.get("ok", false)):
			say("Stormwater collected: %d clean bottles%s." % [
				int(data.get("count", 0)),
				" (filtered swamp rain)" if bool(data.get("filtered", false)) else ""])
		else:
			var reason: String = str(data.get("reason", "rejected"))
			if reason == "cooldown":
				say("Rain catcher: ready in %ds" % ceili(float(data.get("remaining", 0.0))))
			else:
				say("Rain catcher: " + reason)
		return
	if kind == "use" and data.has("neutralized"):
		say("Alkali kit: cleared %d active acid pools nearby." % int(data["neutralized"]))
		return
	if kind == "use" and str(data.get("reason", "")) == "no_acid_nearby":
		say("Alkali kit: no active acid nearby. Your supplies were not spent.")
		return
	if kind == "raid_vote":
		if bool(data.get("ok", false)):
			say("Raid trophy vote: %s recorded%s." % [
				str(data.get("choice", "")),
				"; winner decided" if bool(data.get("resolved", false)) else ""])
		else:
			say("Raid trophy vote: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_loot_mode":
		if bool(data.get("ok", false)):
			say("Future raid loot: " + str(data.get("mode", "free")).replace("_", " "))
		else:
			say("Raid loot mode: " + str(data.get("reason", "rejected")))
		return
	if kind == "raid_skip_turn":
		if bool(data.get("ok", false)):
			say("Raid turn passed. The next contributor can claim their share.")
		else:
			say("Cannot pass raid turn: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_focus":
		if bool(data.get("ok", false)):
			say("Party focus: infected #%d marked for %d seconds (+8%% PvE damage)." % [
				int(data.get("target", 0)), int(data.get("seconds", 18))])
		else:
			say("Party focus: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_ready":
		if not bool(data.get("ok", false)):
			say("Ready check: " + str(data.get("reason", "denied")))
		elif data.has("seconds"):
			say("Party ready check started. All members must respond within 30 seconds.")
		elif str(data.get("result", "pending")) == "all_ready":
			say("Party: everyone is ready for the expedition!")
		elif str(data.get("result", "pending")) == "not_ready":
			say("Party: a member is not ready. Regroup before departing.")
		else:
			say("Ready response recorded. Waiting for the rest of your party.")
		return
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
	if kind == "place_fish_trap":
		if bool(data.get("ok", false)):
			say("Shore net T%d deployed. Fish ready in 120 seconds." % int(data.get("tier", 1)))
		else:
			say("Fish trap: " + str(data.get("reason", "rejected")))
		return
	if kind == "collect_fish_trap":
		if bool(data.get("ok", false)):
			say("Shore net collected: %d x %s. Fishing XP earned." % [
				int(data.get("count", 0)), str(data.get("item", "raw_fish"))])
		elif str(data.get("reason", "")) == "not_ready":
			say("Fish trap: %ds until ready." % ceili(float(data.get("remaining", 0.0))))
		else:
			say("Fish trap: " + str(data.get("reason", "rejected")))
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
	if kind == "party_triage":
		if bool(data.get("ok", false)):
			say("Triage: treated %d allies (+%d HP total, -%d bleeding)." % [
				int(data.get("treated", 0)), roundi(float(data.get("heal", 0.0))),
				roundi(float(data.get("bleeding_stopped", 0.0)))])
		else:
			say("Triage denied: " + str(data.get("reason", "rejected")))
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
	if kind == "loot" and bool(data.get("round_robin", false)) and bool(data.get("ok", false)):
		say("Raid share: claimed %dx %s. Next contributor's turn!" % [
			int(data.get("quantity", 0)), Defs.item(str(data.get("item", ""))).get("name", str(data.get("item", "")))])
		return
	if kind == "loot" and str(data.get("reason", "")) == "not_your_turn":
		say("Raid round-robin: wait your turn (up to %ds)." % ceili(float(data.get("remaining", 0.0))))
		return
	if kind == "loot" and str(data.get("reason", "")) in ["item_unavailable", "invalid_item"]:
		say("Raid reward: that item is no longer available. Select another.")
		return
	if kind == "loot" and str(data.get("reason", "")) == "inventory_full":
		say("Raid loot: your inventory is full. Your turn was not spent.")
		return
	if kind == "loot" and str(data.get("reason", "")) == "raid_vote_pending":
		say("Raid infected cores: vote in progress (%.0fs left). Other supplies can still be looted." % float(data.get("remaining", 0.0)))
		return
	if kind == "loot" and str(data.get("reason", "")) == "raid_winner_reserved":
		say("Infected cores belong to the Need/Greed winner until raid reservation expires.")
		return
	if kind == "loot" and bool(data.get("core_locked", false)):
		say("Raid supplies collected. Infected cores remain protected for the trophy roll.")
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
	if kind == "shelter":
		if bool(data.get("ok", false)):
			say("Field tarp deployed: shared weather cover for 4 minutes.")
		else:
			say("Field tarp: " + str(data.get("reason", "rejected")))
		return
	if kind == "pack_shelter":
		if bool(data.get("ok", false)):
			say("Field tarp packed; materials are not refunded.")
		else:
			say("Pack tarp: " + str(data.get("reason", "rejected")))
		return
	if kind == "campfire":
		if bool(data.get("ok", false)):
			say("Campfire lit: shared warmth for 5 minutes.")
		else:
			say("Campfire: " + str(data.get("reason", "rejected")))
		return
	if kind == "refill_canteen":
		if bool(data.get("ok", false)):
			say("Canteen filled: +1 clean water bottle, -1 filter (12s shore cooldown).")
		else:
			say("Canteen: " + str(data.get("reason", "denied")))
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
			if str(data.get("reason", "")) == "already_listed":
				say("Market: only %d unlisted units remain in your backpack." % int(data.get("available", 0)))
			else:
				say("Market: " + str(data.get("reason", "rejected")))
		elif str(data.get("action", "")) == "list":
			_market_listings = data.get("orders", [])
			_refresh_market_options()
		elif str(data.get("action", "")) == "bought":
			say("Market: bought %dx %s for %d silver (tax %d; seller receives %d)." % [
				int(data.get("quantity", 0)), str(data.get("item", "")), int(data.get("total", 0)),
				int(data.get("tax", 0)), int(data.get("seller_net", 0))])
			client.market_list()
		else:
			say("Market: %s %s" % [str(data.get("action", "updated")), str(data.get("item", ""))])
			client.market_list()
		return
	if kind == "trade":
		if not bool(data.get("ok", false)):
			say("Trade rejected: " + str(data.get("reason", "unknown")))
		return
	if kind == "salvage_gear":
		if bool(data.get("ok", false)):
			say("Recycled %s: recovered %s" % [
				str(Defs.item(str(data.get("item", ""))).get("name", data.get("item", ""))),
				str(data.get("materials", {}))])
		else:
			say("Gear recycling: " + str(data.get("reason", "rejected")))
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
			if int(data.get("regional_bonus", 0)) > 0:
				say("Regional demand at %s: +%d silver per resource!" % [
					str(data.get("settlement", "trader")), int(data["regional_bonus"])])
		else:
			var messages := {
				"no_station": "Vendor: find a workbench (hub or village)",
				"dead": "Vendor: unavailable while dead",
				"invalid_quantity": "Vendor: invalid quantity",
				"not_traded": "Vendor: item is not traded here",
				"missing_items": "Vendor: insufficient resources",
				"insufficient_silver": "Vendor: insufficient silver",
				"no_space": "Vendor: backpack slots or stacks are full",
			}
			say(str(messages.get(str(data.get("reason", "")), "Vendor: rejected")))
		return
	if kind == "stash_bulk":
		if bool(data.get("ok", false)):
			var moved_items: Dictionary = data.get("moved", {})
			say("Banked %d materials (%d types)%s." % [
				int(data.get("total", 0)), moved_items.size(),
				"; %d units still carried (bank full)" % int(data.get("remaining", 0))
					if bool(data.get("partial", false)) else ""])
		else:
			var bulk_errors := {
				"dead": "Stash: cannot bank while dead.",
				"no_station": "Stash: return to the hub workbench.",
				"no_materials": "Stash: no raw or refined materials to store.",
				"no_space": "Stash: protected bank is full.",
				"transaction_failed": "Stash: transaction cancelled without moving items.",
			}
			say(str(bulk_errors.get(str(data.get("reason", "")), "Stash: deposit rejected.")))
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
	if _caravan_status != null:
		var job: Dictionary = client.you.get("caravan", {})
		if job.is_empty():
			_caravan_status.text = "No route. Take one at a village or fort merchant."
		else:
			var here := TravelNavigation.target(client.you, "x", "z")
			var destination := TravelNavigation.target(job, "dst_x", "dst_z")
			var remaining: int = TravelNavigation.distance_meters(here, destination)
			var heading: String = TravelNavigation.compass(here, destination)
			var direction_text := "%dm %s" % [remaining, heading] if remaining >= 0 else "position unavailable"
			_caravan_status.text = "Carry %dx %s to %s | %s | %d silver" % [
				int(job.get("quantity", 0)), str(job.get("cargo", "")),
				str(job.get("destination", "")), direction_text,
				int(job.get("silver", 0))]
			if bool(client.you.get("caravan_defended", false)):
				_caravan_status.text += " | DEFENDED +15% on delivery"
	_bars["health"].value = client.you["health"]
	_bars["hunger"].value = client.you["hunger"]
	_bars["thirst"].value = client.you["thirst"]
	_bars["infection"].value = float(client.you.get("infection", 0.0))
	_bars["bleeding"].value = float(client.you.get("bleeding", 0.0))
	_bars["fracture"].value = float(client.you.get("fracture", 0.0))
	_bars["exposure"].value = float(client.you.get("exposure", 0.0))
	_bars["wetness"].value = float(client.you.get("wetness", 0.0))
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
	if int(client.you.get("rested_xp_credit", 0)) > 0:
		_info_label.text += "\nRESTED TRAINING: %d bonus XP left (paid rest at hub/fire)" % int(
			client.you["rested_xp_credit"])
	for bag in client.bags.values():
		if not bool(bag.get("corpse_scent", false)):
			continue
		var offset := Vector2(float(bag["x"]) - float(client.you.get("x", 0.0)),
			float(bag["z"]) - float(client.you.get("z", 0.0)))
		if offset.length_squared() <= CorpseScent.RADIUS * CorpseScent.RADIUS:
			_info_label.text += "\nFRESH CORPSE: investigating infected may approach within 22 m"
			break
	# An exact server-derived recovery timer (not inferred from visual FX).
	for enemy in client.zombies.values():
		if bool(enemy.get("raid_boss", false)):
			var recovery: float = float(enemy.get("raid_exposed_seconds", 0.0))
			if recovery > 0.0:
				_info_label.text += "\nRAID BOSS EXPOSED: %.1fs (+15%% PvE damage)" % recovery
			break
	var insulation_left: float = float(client.you.get("storm_insulator_seconds", 0.0))
	if insulation_left > 0.0:
		_info_label.text += "\nSTORM INSULATION %.0fs | -60%% bolt damage" % insulation_left
	var bolt: Dictionary = client.lightning_telegraph
	if not bolt.is_empty():
		var warning_center := Vector2(float(bolt.get("x", 0.0)),
			float(bolt.get("z", 0.0)))
		var player_at := Vector2(float(client.you.get("x", 0.0)),
			float(client.you.get("z", 0.0)))
		var imminent: bool = player_at.distance_to(warning_center) <= StormLightning.RADIUS
		_info_label.text += "\nLIGHTNING %s %.1fs — move or dodge!" % [
			"ON YOUR POSITION" if imminent else "NEARBY",
			maxf(0.0, float(bolt.get("at", client.server_time)) - client.server_time)]
	var cone: Dictionary = client.raid_cone_telegraph
	if not cone.is_empty():
		var center_cone := Vector3(float(cone.get("x", 0.0)),
			float(cone.get("y", 0.0)), float(cone.get("z", 0.0)))
		var aim_cone := Vector2(float(cone.get("dx", 0.0)), float(cone.get("dz", 0.0)))
		var where := Vector3(float(client.you.get("x", 0.0)),
			float(client.you.get("y", 0.0)), float(client.you.get("z", 0.0)))
		var threatened: bool = RaidCone.in_sector(center_cone, aim_cone, where)
		var seconds: float = maxf(0.0, float(cone.get("until", client.server_time)) - client.server_time)
		_info_label.text += "\nRAID CLEAVE %s %.1fs — sidestep now!" % [
			"INCOMING" if threatened else "WARNING", seconds]
	var counter_time: float = float(client.you.get("riposte_seconds", 0.0))
	if counter_time > 0.0:
		_info_label.text += "\nRIPOSTE %.1fs — strike the infected you parried!" % counter_time
	var parry_ready: float = float(client.you.get("parry_window", 0.0))
	if parry_ready > 0.0:
		_info_label.text += "\nPARRY ACTIVE %.2fs — face incoming infected!" % parry_ready
	elif float(client.you.get("parry_cooldown", 0.0)) > 0.0:
		_info_label.text += "\nPARRY: %.1fs cooldown (F8)" % float(client.you["parry_cooldown"])
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
	var rain_remaining: float = float(client.you.get("rain_cooldown", 0.0))
	if rain_remaining > 0.0:
		_info_label.text += "\nRAIN CATCHER: next harvest in %ds" % ceili(rain_remaining)
	var spore_harvest_wait: float = float(client.you.get("spore_sample_cooldown", 0.0))
	if spore_harvest_wait > 0.0:
		_info_label.text += "\nSPORE SAMPLES: next in %ds" % ceili(spore_harvest_wait)
	var spore_state: Dictionary = client.you.get("spore", {})
	if bool(spore_state.get("active", false)):
		_info_label.text += "\nSPORE SWAMP: +%.2f infection/s | Total protection %d%%" % [
			float(spore_state.get("rate", 0.0)),
			int(round(100.0 * float(spore_state.get("protection", 0.0))))]
	var spore_filter_left: float = float(client.you.get("spore_filter_seconds", 0.0))
	if spore_filter_left > 0.0:
		_info_label.text += "\nSPORE FILTER: %.0fs remaining (airborne spores only)" % spore_filter_left
	var survey: Dictionary = client.you.get("ruin_survey", {})
	if not survey.is_empty():
		var destination := Vector2(float(survey["x"]), float(survey["z"]))
		var from := Vector2(float(client.you.get("x", 0.0)), float(client.you.get("z", 0.0)))
		_info_label.text += "\nRUIN CHART: X:%d Z:%d | %dm | %ds (F3)" % [
			roundi(destination.x), roundi(destination.y),
			roundi(from.distance_to(destination)), ceili(float(survey["remaining"]))]
	var flash_wait: float = float(client.you.get("flash_cooldown", 0.0))
	if flash_wait > 0.0:
		_info_label.text += "\nFLASH CHARGE: ready in %ds" % ceili(flash_wait)
	if bool(client.you.get("smoke_concealed", false)):
		_info_label.text += "\nSMOKE: quiet sight cover, no PvP immunity"
	if not client.smoke_clouds.is_empty() and client.world != null:
		var smoke_wind: Vector2 = Weather.wind_at(client.world,
			float(client.you.get("x", 0.0)), float(client.you.get("z", 0.0)),
			client.server_time)
		_info_label.text += "\nSMOKE DRIFT: %.1f m/s | cover moves with regional wind" % smoke_wind.length()
	var smoke_left: float = float(client.you.get("smoke_cooldown", 0.0))
	if smoke_left > 0.0:
		_info_label.text += "\nSMOKE: %ds recharge (F9)" % ceili(smoke_left)
	var grip_remaining: float = float(client.you.get("tire_grip_seconds", 0.0))
	if grip_remaining > 0.0:
		_info_label.text += "\nOFF-ROAD TIRES: %.0fs | less mud/sand/roots/rock drag" % grip_remaining
	var finisher_left: float = float(client.you.get("finisher_cooldown", 0.0))
	if finisher_left > 0.0:
		_info_label.text += "\nFINISHER: %.1fs cooldown | Shift+G vs stunned infected" % finisher_left
	var oil_left: float = float(client.you.get("coating_seconds", 0.0))
	if oil_left > 0.0:
		_info_label.text += "\nANTISEPTIC EDGE %s %.0fs: +20%% infected damage (no PvP/bosses)" % [
			str(client.you.get("coating_weapon", "")), oil_left]
	var quiet_left: float = float(client.you.get("chain_wrap_seconds", 0.0))
	if quiet_left > 0.0:
		_info_label.text += "\nQUIET CHAIN: %.0fs | Bike noise 9m" % quiet_left
	elif bool(client.you.get("mounted", false)):
		_info_label.text += "\nBIKE NOISE: 27m while moving (infected can hear)"
	var supported_kg: float = float(client.you.get("bike_cargo_kg", 0.0))
	if supported_kg > 0.0:
		_info_label.text += "\nBIKE PANNIERS: %.0f kg supported (on foot: full load)" % supported_kg
	if bool(client.you.get("on_road", false)):
		_info_label.text += "\nDIRT ROAD: +8% foot pace, stronger bicycle grip"
	if client.inventory.count("salvage_bike") > 0:
		_info_label.text += "\nBIKE SERVICE: %.0f m | PgUp service on foot" % float(client.you.get("bike_service_meters", 0.0))
		_info_label.text += "\nBIKE FRAME: %.0f%% | PgDn patch on foot" % float(client.you.get("bike_integrity", 100.0))
	_info_label.text += "\nTRAIL BIKE: %s | F4 mount/dismount | remount %.0fs" % [
		"RIDING" if bool(client.you.get("mounted", false)) else ("CARRIED" if client.inventory.count("salvage_bike") > 0 else "NOT OWNED"),
		float(client.you.get("mount_cooldown", 0.0))]
	if bool(client.you.get("mounted", false)):
		_info_label.text += "\nBIKE RATTLE: rolling attracts infected (wrap/service reduce sound)"
		var bike_biome: String = client.world.biome_at(float(client.you.get("x", 0.0)),
			float(client.you.get("z", 0.0)))
		_info_label.text += "\nBIKE GROUND: %s | slope changes riding speed" % bike_biome.to_upper()
	_info_label.text += "\nStorm insulation %d%% (equipped armor)" % int(
		round(100.0 * float(client.you.get("weather_insulation", 0.0))))
	if bool(client.you.get("tent_camouflaged", false)):
		_info_label.text += "\nCANOPY CAMOUFLAGE: infected see 25% less; sound, scent and fire still reveal"
	var visual: float = float(client.you.get("visual_signature", 1.0))
	if bool(client.you.get("crouching", false)):
		_info_label.text += "\nCROUCHED (Ctrl): slower, less visible to idle infected"
	if visual < 0.999:
		_info_label.text += "\nSTEALTH (STANCE / GEAR / TARP): infected visual range -%d%%" % [
			int(round(100.0 * (1.0 - visual)))]
	_info_label.text += "\nCAMP RENOWN %s: %d / %d | NPC buy discount %d%%" % [
		str(client.you.get("renown_rank", "Newcomer")),
		int(client.you.get("renown", 0)), int(client.you.get("renown_next", 40)),
		int(client.you.get("vendor_discount", 0))]
	var regional_offer: Dictionary = client.you.get("regional_trade", {})
	if not regional_offer.is_empty():
		_info_label.text += "\nLOCAL TRADE: %s buys %s for +%d%% (raw resource sales)" % [
			str(regional_offer["name"]), str(regional_offer["category"]).capitalize(),
			int(regional_offer["premium_percent"])]
	var mask_seconds: float = float(client.you.get("scent_mask_seconds", 0.0))
	if mask_seconds > 0.0:
		_info_label.text += "\nSCENT MASK: %.0fs remaining (vision and hearing unchanged)" % mask_seconds
	var flare_time: float = float(client.you.get("flare_seconds", 0.0))
	if flare_time > 0.0:
		_info_label.text += "\nSIGNAL FLARE: %ds | night infected notice 28m" % ceili(flare_time)
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
			"CAMPFIRE WARMTH" if bool(client.you.get("campfire_warm", false)) else (
				"FIELD TARP (-75% WEATHER)" if bool(client.you.get("tent_sheltered", false)) else (
				"SHELTERED" if bool(weather.get("sheltered", false)) else "EXPOSED")),
			int(client.you.get("exposure", 0.0)), int(ceil(float(client.you.get("warmth_seconds", 0.0))))
		]
	var wind_chill: Dictionary = client.you.get("wind_chill", {})
	if float(wind_chill.get("extra", 0.0)) > 0.0:
		_info_label.text += "\nWIND CHILL: %.1f m/s | +%.0f%% cold exposure intensity" % [
			float(wind_chill.get("speed", 0.0)), 100.0 * float(wind_chill["extra"])]
	var wet: float = float(client.you.get("wetness", 0.0))
	if wet > 0.0:
		_info_label.text += "\nWET CLOTHING: %d%% | cold increases exposure; dry at a campfire" % roundi(wet)
	var storm_cover: float = float(client.you.get("weather_sight", 1.0))
	if is_finite(storm_cover) and storm_cover < 1.0:
		_info_label.text += "\nSTORM COVER: infected sight -%d%% (sound, scent & fire still reveal)" % [
			int(round(100.0 * (1.0 - clampf(storm_cover, 0.0, 1.0))))]
	var return_seconds: float = float(client.you.get("recall_seconds", 0.0))
	if return_seconds > 0.0:
		_info_label.text += "\nRETURN CHARM: channeling %ds — stand still" % ceili(return_seconds)
	elif float(client.you.get("recall_cooldown", 0.0)) > 0.0:
		_info_label.text += "\nRETURN CHARM cooldown: %ds" % ceili(float(client.you["recall_cooldown"]))
	_info_label.text += "\nCARTOGRAPHY: %d landmarks mapped (J: island map)" % int(client.you.get("discovered_count", 0))
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
	_market_status.text = "%d listings | item then lowest price | %d%% seller tax" % [
		_market_listings.size(), MarketBoard.SALE_TAX_PERCENT]


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
	var loot_mode: String = str(state.get("loot_mode", "free"))
	_raid_loot_mode_button.disabled = group_id == 0 or int(state.get("leader", 0)) != client.peer_id
	_raid_loot_mode_button.text = "Raid loot: " + ("Round robin" if loot_mode == "round_robin" else ("Need/Greed" if loot_mode == "need_greed" else "Free"))
	_raid_skip_bag_id = -1
	var nearest_raid_distance: float = INF
	for reward in client.bags.values():
		if not bool(reward.get("raid_round_robin", false)) or not bool(reward.get("raid_your_turn", false)) or not bool(reward.get("can_loot", false)):
			continue
		var dx: float = float(reward.get("x", 0.0)) - float(client.you.get("x", 0.0))
		var dz: float = float(reward.get("z", 0.0)) - float(client.you.get("z", 0.0))
		var distance_sq: float = dx * dx + dz * dz
		if distance_sq <= (Defs.REACH + 0.5) * (Defs.REACH + 0.5) and distance_sq < nearest_raid_distance:
			nearest_raid_distance = distance_sq
			_raid_skip_bag_id = int(reward.get("id", -1))
	_raid_skip_button.disabled = _raid_skip_bag_id <= 0
	_raid_vote_bag_id = -1
	var nearest_vote_distance: float = INF
	var nearest_ballot: Dictionary = {}
	for bag in client.bags.values():
		var ballot: Dictionary = bag.get("raid_need_greed", {})
		if ballot.is_empty():
			continue
		var dx_vote: float = float(bag.get("x", 0.0)) - float(client.you.get("x", 0.0))
		var dz_vote: float = float(bag.get("z", 0.0)) - float(client.you.get("z", 0.0))
		var distance: float = dx_vote * dx_vote + dz_vote * dz_vote
		if distance <= Party.ASSIST_RANGE * Party.ASSIST_RANGE and distance < nearest_vote_distance:
			nearest_vote_distance = distance
			_raid_vote_bag_id = int(bag.get("id", -1))
			nearest_ballot = ballot
	var may_vote: bool = _raid_vote_bag_id > 0 and str(nearest_ballot.get("status", "")) == "voting" and str(nearest_ballot.get("your_vote", "")).is_empty()
	_raid_vote_need.disabled = not may_vote
	_raid_vote_greed.disabled = not may_vote
	_raid_vote_pass.disabled = not may_vote
	_raid_vote_label.text = "No active Need/Greed raid trophy ballot nearby."
	if _raid_vote_bag_id > 0:
		var ballot_status: String = str(nearest_ballot.get("status", ""))
		if ballot_status == "voting":
			_raid_vote_label.text = "Raid bag #%d: %d Infected Core. %d/%d votes, %.0fs. %s" % [
				_raid_vote_bag_id, int(nearest_ballot.get("amount", 0)),
				int(nearest_ballot.get("votes_cast", 0)),
				int(nearest_ballot.get("participants", 0)),
				float(nearest_ballot.get("remaining", 0.0)),
				"Choose Need, Greed or Pass" if may_vote else "Your vote: " + str(nearest_ballot.get("your_vote", ""))]
		elif ballot_status == "awarded":
			_raid_vote_label.text = "Raid bag #%d: %s" % [_raid_vote_bag_id,
				"YOU WON infected cores! Loot the bag." if bool(nearest_ballot.get("your_win", false)) else "Another contributor won the infected cores."]
		elif ballot_status == "free":
			_raid_vote_label.text = "Raid bag #%d: all passed. Infected cores open to eligible contributors." % _raid_vote_bag_id
	var chosen_bag: Dictionary = client.bags.get(_raid_skip_bag_id, {})
	var choices: Array = chosen_bag.get("raid_item_choices", [])
	var choices_signature: String = "%d:%s" % [_raid_skip_bag_id, JSON.stringify(choices)]
	if choices_signature != _raid_items_signature:
		var previous: String = ""
		if _raid_item_select.selected >= 0:
			previous = str(_raid_item_select.get_selected_metadata())
		_raid_items_signature = choices_signature
		_raid_item_select.clear()
		var preferred_index: int = 0
		for raw_id in choices:
			var item_id: String = str(raw_id)
			var item_name: String = str(Defs.item(item_id).get("name", item_id))
			_raid_item_select.add_item(item_name)
			var index: int = _raid_item_select.item_count - 1
			_raid_item_select.set_item_metadata(index, item_id)
			if item_id == previous:
				preferred_index = index
		if _raid_item_select.item_count > 0:
			_raid_item_select.select(preferred_index)
	_raid_item_select.disabled = choices.is_empty()
	_raid_claim_button.disabled = _raid_skip_bag_id <= 0 or choices.is_empty()
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
	if group_id != 0:
		_party_status.text += "\nRaid loot: %s (leader controls future boss drops)" % (
			"Round robin" if loot_mode == "round_robin" else "Free pickup")
	for reward in client.bags.values():
		if bool(reward.get("raid_round_robin", false)):
			_party_status.text += "\nRaid bag #%d: %s (%.0fs)" % [
				int(reward.get("id", 0)),
				"YOUR TURN" if bool(reward.get("raid_your_turn", false)) else "waiting",
				float(reward.get("raid_turn_seconds", 0.0))]
			break
	var focus_state: Dictionary = state.get("focus", {})
	if not focus_state.is_empty():
		_party_status.text += "\nFocus infected #%d: %ds remaining (+8%% PvE damage)" % [
			int(focus_state.get("target", -1)),
			int(ceil(float(focus_state.get("remaining", 0.0))))]
	var ready_state: Dictionary = state.get("ready_check", {})
	if not ready_state.is_empty():
		var votes: PackedStringArray = []
		for vote in ready_state.get("votes", []):
			var vote_id: int = int(vote.get("id", 0))
			var member_name := "#%d" % vote_id
			for member in roster:
				if int(member.get("id", 0)) == vote_id:
					member_name = str(member.get("name", member_name))
					break
			votes.append("%s: %s" % [member_name, str(vote.get("status", "pending"))])
		_party_status.text += "\nReady check [%s] %ds — %s" % [
			str(ready_state.get("result", "pending")),
			int(ceil(float(ready_state.get("remaining", 0.0)))), ", ".join(votes)]
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
	var escort: Dictionary = state.get("escort_caravan", {})
	if not escort.is_empty():
		var origin := TravelNavigation.target(client.you, "x", "z")
		var destination := TravelNavigation.target(escort, "dst_x", "dst_z")
		var remaining: int = TravelNavigation.distance_meters(origin, destination)
		var compass: String = TravelNavigation.compass(origin, destination)
		var guide := "%dm %s" % [remaining, compass] if remaining >= 0 else "unknown"
		_party_status.text += "\nEscort %s: %dx %s to %s | %s" % [
			str(escort.get("name", "Courier")), int(escort.get("quantity", 0)),
			str(escort.get("cargo", "")), str(escort.get("destination", "")), guide]
		if int(escort.get("owner", 0)) != client.peer_id:
			var contributed: Dictionary = state.get("escort_progress", {})
			_party_status.text += "\nEscort milestones %d/4 | travelled %dm (min 80m); up to 20%% of courier fare split with guards" % [
				int(contributed.get("stage", 0)), int(contributed.get("meters", 0))]
	var rally: Dictionary = state.get("rally", {})
	if not rally.is_empty():
		var from_position := TravelNavigation.target(client.you, "x", "z")
		var rally_position := TravelNavigation.target(rally, "x", "z")
		var distance: int = TravelNavigation.distance_meters(from_position, rally_position)
		var heading: String = TravelNavigation.compass(from_position, rally_position)
		var guidance: String = "%dm %s" % [distance, heading] if distance >= 0 else "location unavailable"
		_party_status.text += "\nRally: %s | %d seconds" % [
			guidance, int(ceil(float(rally["remaining"])))]
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


const TIER_COLORS := [Color(0.62, 0.64, 0.68), Color(0.62, 0.64, 0.68), Color(0.36, 0.82, 0.42), Color(0.36, 0.62, 1.0), Color(0.78, 0.42, 1.0)]


## A short tag for the kind of item, shown in its slot.
static func _kind_glyph(kind: String) -> String:
	match kind:
		"weapon": return "[ATK]"
		"armor": return "[DEF]"
		"tool": return "[TOOL]"
		"food": return "[FOOD]"
		"drink": return "[DRINK]"
		"medical": return "[MED]"
		"material": return "[MAT]"
	return "[%s]" % kind.substr(0, 4).to_upper() if kind != "" else ""


## An inventory slot card: dark, with a border in the colour of the item tier, gold when equipped.
func _style_slot(button: Button, item_id: String, equipped: bool) -> void:
	var tier: int = clampi(Defs.tier_of(item_id), 0, TIER_COLORS.size() - 1) if item_id != "" else 0
	var edge: Color = Color(0.95, 0.78, 0.35) if equipped else (TIER_COLORS[tier] if item_id != "" else Color(1, 1, 1, 0.08))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.06, 0.09, 0.92) if item_id != "" else Color(0.03, 0.035, 0.05, 0.6)
		if state == "hover":
			style.bg_color = Color(0.12, 0.13, 0.18, 0.96)
		elif state == "pressed":
			style.bg_color = Color(0.22, 0.18, 0.08, 0.98)
		style.set_corner_radius_all(8)
		style.set_border_width_all(2 if (equipped or state == "hover") else 1)
		style.border_width_bottom = 4 if item_id != "" else 1
		style.border_color = edge
		style.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color(1, 1, 1) if item_id != "" else Color(1, 1, 1, 0.3))


func _refresh_inventory() -> void:
	var signature := str(client.inventory.to_dict()) + "|" + str(client.stash.to_dict())
	if signature == _inventory_signature:
		return
	_inventory_signature = signature
	var previous: String = ""
	if _salvage_item.selected >= 0:
		previous = str(_salvage_item.get_item_metadata(_salvage_item.selected))
	_salvage_item.clear()
	_salvage_item.add_item("Select spare gear")
	_salvage_item.set_item_metadata(0, "")
	_salvage_item.select(0)
	var shown_ids: Array[String] = []
	for slot in client.inventory.slots:
		if slot.is_empty():
			continue
		var item_id: String = str(slot["id"])
		var kind: String = str(Defs.item(item_id).get("kind", ""))
		if kind not in ["weapon", "armor", "tool"] or shown_ids.has(item_id):
			continue
		shown_ids.append(item_id)
	shown_ids.sort()
	for item_id in shown_ids:
		_salvage_item.add_item(str(Defs.item(item_id).get("name", item_id)))
		var index: int = _salvage_item.item_count - 1
		_salvage_item.set_item_metadata(index, item_id)
		if item_id == previous:
			_salvage_item.select(index)
	for child in _inventory_grid.get_children():
		child.queue_free()
	for slot in client.inventory.slots:
		var button := Button.new()
		button.custom_minimum_size = Vector2(88, 60)
		button.add_theme_font_size_override("font_size", 11)
		if slot.is_empty():
			button.disabled = true
			button.text = ""
			_style_slot(button, "", false)
		else:
			var item_id: String = slot["id"]
			var equipped: bool = item_id == client.inventory.weapon or item_id == client.inventory.armor
			var info: Dictionary = Defs.item(item_id)
			button.text = "%s\n%s  x%d" % [str(info.get("name", item_id)), _kind_glyph(str(info.get("kind", ""))), int(slot["count"])]
			button.tooltip_text = "%s\n%s  Tier %d%s\nClick: use or equip   Right click: put one in the stash" % [
				str(info.get("name", item_id)), str(info.get("kind", "item")).capitalize(), maxi(1, Defs.tier_of(item_id)),
				"\nEQUIPPED" if equipped else ""]
			_style_slot(button, item_id, equipped)
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
	# Every slot counts: changes to fish, ore, medicine etc must refresh recipes,
	# not only the old special case of wood_1.
	var signature := str(client.inventory.slots) + str(client.you.get("crafting_level", 1)) \
		+ _craft_search.text + str(_craft_ready_only.button_pressed)
	if signature == _craft_signature:
		return
	_craft_signature = signature
	for child in _craft_list.get_children():
		child.queue_free()
	var entries: Array[Dictionary] = CraftingCatalog.entries(
		client.inventory, _craft_search.text, _craft_ready_only.button_pressed,
		int(client.you.get("crafting_level", 1)))
	_craft_result_count.text = "%d recipes | Click to craft one, MAX for a material-and-space-safe batch (limit 50)." % entries.size()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No matching recipes. Try fewer words or disable the filter."
		_craft_list.add_child(empty)
	for entry in entries:
		var recipe_id: String = str(entry["id"])
		var recipe: Dictionary = Defs.recipes()[recipe_id]
		var needs: Array[String] = []
		for input in recipe["inputs"]:
			needs.append("%dx %s" % [
				int(recipe["inputs"][input]), str(Defs.item(str(input)).get("name", input))])
		var row := HBoxContainer.new()
		var button := Button.new()
		var station: String = str(recipe["station"])
		var station_note := " [bench]" if station == "workbench" else (
			" [fire / bench]" if station == "campfire" else "")
		button.text = "%s  <-  %s%s" % [
			str(Defs.item(str(recipe["output"])).get("name", recipe["output"])),
			", ".join(needs), station_note]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(465, 0)
		var ready: bool = bool(entry["ready"])
		button.disabled = not ready
		if not ready:
			button.text += " [Lv%d]" % int(entry["tier"]) if bool(entry["skill_locked"]) else " [missing ingredients / space]"
		button.pressed.connect(func() -> void: client.craft(recipe_id, 1))
		row.add_child(button)
		var amount: int = int(entry["max_batches"])
		if ready and amount > 1:
			var max_button := Button.new()
			max_button.text = "MAX x%d" % amount
			max_button.tooltip_text = "Craft %d batches in one validated server request (no partial material consumption)." % amount
			max_button.pressed.connect(func() -> void: client.craft(recipe_id, amount))
			row.add_child(max_button)
		_craft_list.add_child(row)
