extends CanvasLayer
const UiSafeArea = preload("res://scripts/client/ui_safe_area.gd")
## All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

const Defs = preload("res://scripts/shared/defs.gd")
const ReturnRate = preload("res://scripts/shared/return_rate.gd")
const Factions = preload("res://scripts/shared/factions.gd")
const Farming = preload("res://scripts/shared/farming.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const RaidCone = preload("res://scripts/shared/raid_cone.gd")
const Party = preload("res://scripts/shared/party.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const TrailRation = preload("res://scripts/shared/trail_ration.gd")
const CombatStress = preload("res://scripts/shared/combat_stress.gd")
const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")
const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const CraftingCatalog = preload("res://scripts/shared/crafting_catalog.gd")
const ExpeditionLoadout = preload("res://scripts/shared/expedition_loadout.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const FirstSteps = preload("res://scripts/client/first_steps.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const StoryCampaign = preload("res://scripts/shared/story_campaign.gd")
const StoryChapterTwo = preload("res://scripts/shared/story_chapter_two.gd")
const StoryChapterThree = preload("res://scripts/shared/story_chapter_three.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
const PartyFrames = preload("res://scripts/client/party_frames.gd")
const HudSkin = preload("res://scripts/client/hud_skin.gd")
const UiTheme = preload("res://scripts/client/ui_theme.gd")
const ItemIcons = preload("res://scripts/client/item_icons.gd")
const EquipmentPresets = preload("res://scripts/shared/equipment_presets.gd")

var client
var _bars: Dictionary = {}
var _zone_label: Label
var world_streaming_notice := ""
var _info_label: Label
var _vendor_water_button: Button
var _vendor_food_button: Button
var _radar
var _contract_label: Label
var _story_journal: Label # Chapter transcripts in the inventory's mission section.
var _story2_journal: Label # New chapter is independent of Chapter I saves.
var _story3_journal: Label # Branch-aware missing convoy radio records.
var _caravan_status: Label
var _prompt: Label
var _log: Label
var _inventory_panel: PanelContainer
var _inventory_grid: GridContainer
var _preset_labels: Array[Label] = []
# Where each tab of the inventory window starts in the action list: [child index, tab name], in build order.
var _action_sections: Array = [[0, "Gear"]]
var _inventory_summary: Label
var _inventory_tabs: TabContainer
var social # Nakama chat, guilds and friends (online_main sets it; null or signed out when playing offline).
var _left_column: VBoxContainer # "+", buffs and the party under the portrait.
var _buff_row: HFlowContainer
var _party_list: VBoxContainer
var _left_signature := ""
var _social_panel: PanelContainer
var _social_tabs: TabContainer
var _guild_status: Label
var _guild_results: VBoxContainer
var _friend_list: VBoxContainer
var _actions_panel: PanelContainer
var _doll: GridContainer # Equipment sockets of the bag window.
var _inventory_scroll: ScrollContainer
# Item categories shown in the bag and the workshop (side buttons switch them; all on = everything).
const ITEM_CATEGORIES := [["weapons", "Weapons", "machete"], ["gear", "Armor and clothes", "jacket"],
	["supplies", "Food, water and medicine", "canned_food"], ["materials", "Resources and materials", "wood"],
	["other", "Tools and everything else", "scrap"]]
var _bag_filter := {"weapons": true, "gear": true, "supplies": true, "materials": true, "other": true}
var _craft_filter := {"weapons": true, "gear": true, "supplies": true, "materials": true, "other": true}
var _doll_info: VBoxContainer
var _quick_slots := {"food": "", "potion": ""} # Client-side quick use picks, saved in user://quick_slots.cfg.
var _drag_role := "" # The doll socket the dragged item fits, lit while dragging.
var _stash_grid: GridContainer
var _craft_panel: PanelContainer
var _craft_list: VBoxContainer
var _craft_search: LineEdit
var _craft_ready_only: CheckBox
var _craft_use_stash: CheckBox
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
var _bid_select: OptionButton # Albion-style buy orders (highest price first).
var _market_bids: Array = []
var _guild_vault_select: OptionButton # Items in the guild bank (withdraw target).
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
	# Base 14 px plus the display's unsafe area (notches, overscan, handheld bezels).
	UiSafeArea.apply(margin, UiSafeArea.current(get_viewport()))
	add_child(margin)
	get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(margin):
			UiSafeArea.apply(margin, UiSafeArea.current(get_viewport())))


	var radar := SurvivalRadar.new()
	radar.name = "SurvivalRadar"
	radar.client = client
	radar.world = client.world
	add_child(radar)
	# The minimap sits in the lower right corner, as in most online RPGs; the menu buttons take the top right.
	radar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	radar.offset_left = -206.0
	radar.offset_top = -206.0
	radar.offset_right = -16.0
	radar.offset_bottom = -16.0
	_radar = radar
	_build_menu_bar()
	_build_left_column()

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
	var sweep_button := Button.new()
	sweep_button.name = "CollectNearbyPveLoot"
	sweep_button.text = "Collect nearby PvE bags (Shift+E / Shift+Q)"
	sweep_button.tooltip_text = "Up to five eligible ordinary infected drops. Raids, full-loot PvP and guarded cargo remain manual."
	sweep_button.pressed.connect(func() -> void: client.loot_sweep())
	inventory_box.add_child(sweep_button)
	var preset_title := Label.new()
	preset_title.text = "Gear presets: save / equip / clear at safe hub workbench"
	inventory_box.add_child(preset_title)
	for slot in EquipmentPresets.SLOT_COUNT:
		var index: int = slot
		var row := HBoxContainer.new()
		inventory_box.add_child(row)
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 220.0
		name_label.text = "Set %d: empty" % (index + 1)
		_preset_labels.append(name_label)
		row.add_child(name_label)
		for action in ["save", "equip", "clear"]:
			var button := Button.new()
			button.text = action.capitalize()
			button.tooltip_text = "Only next to the safe hub workbench, outside combat."
			button.pressed.connect(func() -> void: client.equipment_preset(action, index))
			row.add_child(button)
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
	var repair_button := Button.new()
	repair_button.name = "RepairGear"
	repair_button.text = "Repair gear (workbench, silver)"
	repair_button.tooltip_text = "Restores every damaged carried item to 100% durability. Broken (0%) gear only works at half strength."
	repair_button.pressed.connect(func() -> void: client.repair_gear())
	salvage_row.add_child(repair_button)
	for enchant_slot in ["weapon", "armor"]:
		var enchant_button := Button.new()
		enchant_button.name = "Enchant" + enchant_slot.capitalize()
		enchant_button.text = "Enchant %s" % enchant_slot
		enchant_button.tooltip_text = "Workbench only. Raises the equipped %s one level (.1 runes, .2 souls, .3 relics) plus silver: +10%% stats, +100 item power." % enchant_slot
		enchant_button.pressed.connect(func() -> void:
			var target: String = client.inventory.weapon if enchant_slot == "weapon" else client.inventory.armor
			if target == "":
				say("Enchant: equip a %s first." % enchant_slot)
			else:
				client.enchant(target))
		salvage_row.add_child(enchant_button)
	_action_sections.append([inventory_box.get_child_count(), "Field"])
	var trauma_button := Button.new()
	trauma_button.name = "UseExpeditionTraumaKit"
	trauma_button.text = "Expedition trauma kit (Shift+3): treat mixed injuries"
	trauma_button.tooltip_text = "Spend one crafted T2 kit: +38 HP, -15 infection, stop bleeding, -45 fracture. No treatment means no item consumed."
	trauma_button.pressed.connect(func() -> void: client.use_item("expedition_trauma_kit"))
	inventory_box.add_child(trauma_button)
	var campfire_button := Button.new()
	campfire_button.text = "Light field campfire (3 wood T1, 1 stone T1)"
	campfire_button.tooltip_text = "Shared warmth for 5 minutes, outside the safe settlement"
	campfire_button.pressed.connect(func() -> void:
		var pos: Vector3 = client.display_position()
		var direction := Vector2(sin(client.yaw), cos(client.yaw))
		client.light_campfire(Vector2(pos.x, pos.z) + direction * 2.8))
	inventory_box.add_child(campfire_button)
	var alarm_button := Button.new()
	alarm_button.name = "ArmCampAlarm"
	alarm_button.text = "Arm camp sentry alarm (Shift+O)"
	alarm_button.tooltip_text = "Uses 1 field-crafted Camp Sentry Alarm Kit at a live fire. Detects infected within 21m for up to 3 minutes; private alerts at most every 24s."
	alarm_button.pressed.connect(func() -> void:
		var id: int = client.nearest_campfire(client.display_position())
		if id < 0:
			say("Camp alarm: stand within 3m of a live campfire.")
		else:
			client.arm_camp_alarm(id))
	inventory_box.add_child(alarm_button)
	var pitch_button := Button.new()
	pitch_button.name = "PitchTarp"
	pitch_button.text = "Pitch field tarp (2 cloth T1, 2 fiber T1, 1 plank T1)"
	pitch_button.tooltip_text = "4 minutes of shared weather cover (-75% exposure), no PvP immunity."
	pitch_button.pressed.connect(func() -> void:
		var position: Vector3 = client.display_position()
		var heading := Vector2(sin(client.yaw), cos(client.yaw))
		client.pitch_shelter(Vector2(position.x, position.z) + heading * 2.8))
	inventory_box.add_child(pitch_button)
	var anchor_button := Button.new()
	anchor_button.name = "AnchorFieldTarp"
	anchor_button.text = "Anchor my field tarp (+180s, 90% storm cover)"
	anchor_button.tooltip_text = "Use one workbench-crafted Storm Tarp Anchor Kit at your nearby active tarp. One upgrade per tarp; no PvP protection."
	anchor_button.pressed.connect(func() -> void: client.use_item("storm_tarp_anchors"))
	inventory_box.add_child(anchor_button)
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
	var brace_button := Button.new()
	brace_button.name = "PrepareSiegeBlastBrace"
	brace_button.text = "Brace nearby owned wall (one siege blast)"
	brace_button.tooltip_text = "T2 crafted workbench kit: absorb 55% of one charge before the raid, 3m range, 180s."
	brace_button.pressed.connect(func() -> void: client.use_item("siege_blast_brace"))
	inventory_box.add_child(brace_button)
	var defusal_button := Button.new()
	defusal_button.name = "DisarmSiegeCharge"
	defusal_button.text = "Disarm siege charge (T2 defusal kit)"
	defusal_button.tooltip_text = "Only the wall owner. Requires crafted toolkit and 3m reach before the four-second fuse expires."
	defusal_button.pressed.connect(func() -> void:
		client.use_item("siege_defusal_kit"))
	inventory_box.add_child(defusal_button)
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
	var seal_button := Button.new()
	seal_button.name = "UseWoundSealant"
	seal_button.text = "Apply antiseptic bite seal (90s)"
	seal_button.tooltip_text = "Craft from wild herbs, antiseptic and cloth. 45% less infected bite infection for 90s; no acid, spore or PvP immunity."
	seal_button.pressed.connect(func() -> void: client.use_item("wound_sealant"))
	inventory_box.add_child(seal_button)
	var canteen_button := Button.new()
	canteen_button.name = "RefillFieldCanteen"
	canteen_button.text = "Refill canteen at shore (1 filter -> 1 clean water)"
	canteen_button.tooltip_text = "Requires a crafted canteen, one carbon filter and the shared lake cooldown."
	canteen_button.pressed.connect(func() -> void: client.refill_canteen())
	inventory_box.add_child(canteen_button)
	var pouch_button := Button.new()
	pouch_button.name = "FillRawWaterPouch"
	pouch_button.text = "Fill crafted water pouch at shore (Shift+2)"
	pouch_button.tooltip_text = "Craft an empty pouch from cloth + fiber. Fill near lake water, then craft Boiled Water using 1 wood at a live campfire (or hub workbench). Raw water cannot be drunk."
	pouch_button.pressed.connect(func() -> void: client.use_item("empty_water_pouch"))
	inventory_box.add_child(pouch_button)
	var raw_fish_button := Button.new()
	raw_fish_button.name = "EatRawFish"
	raw_fish_button.text = "Emergency food: eat raw fish (Alt+1, poisoning risk)"
	raw_fish_button.tooltip_text = "Eat one carried T1-T4 raw fish for limited hunger recovery. Causes food poisoning; cook it for a safe meal instead."
	raw_fish_button.pressed.connect(func() -> void:
		var chosen := ""
		for tier in range(1, 5):
			var candidate: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
			if client.inventory.count(candidate) > 0:
				chosen = candidate
				break
		if chosen == "":
			say("No raw fish carried. Try fishing at the shore.")
		else:
			client.use_item(chosen))
	inventory_box.add_child(raw_fish_button)
	var stomach_button := Button.new()
	stomach_button.name = "UseStomachRemedy"
	stomach_button.text = "Treat food poisoning (Shift+F11; herbal remedy)"
	stomach_button.tooltip_text = "Craft from 2 wild herbs, 1 charcoal filter and 1 clean water. Reduces food poisoning by 75 points; no effect if already healthy."
	stomach_button.pressed.connect(func() -> void: client.use_item("herbal_gut_tonic"))
	inventory_box.add_child(stomach_button)
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
	var prospect_button := Button.new()
	prospect_button.name = "UseProspectingChart"
	prospect_button.text = "Prospect high-tier ore and stone (180m; 1 chart)"
	prospect_button.tooltip_text = "Field craft: cloth, 2 scrap, stone. Spend only on a real T2+ vein; private 80s marker."
	prospect_button.pressed.connect(func() -> void: client.use_item("prospecting_chart"))
	inventory_box.add_child(prospect_button)
	var group_survey_button := Button.new()
	group_survey_button.name = "ShareMineralSurvey"
	group_survey_button.text = "Share scouted vein with party (1 crafted signal)"
	group_survey_button.tooltip_text = "First prospect a real T2+ node, then spend one field-made signal. Teammates receive a temporary amber mining waypoint."
	group_survey_button.pressed.connect(func() -> void: client.use_item("surveyor_signal"))
	inventory_box.add_child(group_survey_button)
	var mining_wedges_button := Button.new()
	mining_wedges_button.name = "EquipMiningWedges"
	mining_wedges_button.text = "Prepare mining wedges (3 T2+ deposits)"
	mining_wedges_button.tooltip_text = "Workbench craft: 1 T2 bar, 3 scrap, 2 stone. Requires a pickaxe. +2 ore/stone per eligible deposit, but mining noise rises to 42m."
	mining_wedges_button.pressed.connect(func() -> void: client.use_item("mining_wedges"))
	inventory_box.add_child(mining_wedges_button)
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
	var lamp_button := Button.new()
	lamp_button.name = "ToggleBikeDynamoLamp"
	lamp_button.text = "Switch bicycle night lamp ([; no item consumed)"
	lamp_button.tooltip_text = "Trade 13m forward illumination for infected exposure (23m). Switch on/off while riding or on foot."
	lamp_button.pressed.connect(func() -> void: client.use_item("bike_dynamo_lamp"))
	inventory_box.add_child(lamp_button)
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
	var restock_row := HBoxContainer.new()
	restock_row.name = "ExpeditionRestock"
	inventory_box.add_child(restock_row)
	var preset_select := OptionButton.new()
	preset_select.custom_minimum_size.x = 170.0
	for preset_id in ExpeditionLoadout.ORDER:
		preset_select.add_item(ExpeditionLoadout.title(preset_id))
		preset_select.set_item_metadata(preset_select.item_count - 1, preset_id)
	restock_row.add_child(preset_select)
	var restock_button := Button.new()
	restock_button.text = "RESTOCK KIT"
	restock_button.tooltip_text = "At the hub workbench, withdraw missing expedition supplies from your protected stash. Never buys or crafts items."
	restock_button.pressed.connect(func() -> void:
		if preset_select.selected >= 0:
			client.expedition_restock(str(preset_select.get_item_metadata(preset_select.selected))))
	restock_row.add_child(restock_button)

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

	_action_sections.append([inventory_box.get_child_count(), "Trade"])
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
	_action_sections.append([inventory_box.get_child_count(), "Field"])
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
	var storm_cast_button := Button.new()
	storm_cast_button.name = "StormCast"
	storm_cast_button.text = "Storm cast (red/black coast; 8s, +2 fish)"
	storm_cast_button.tooltip_text = "During real storms in full-loot regions; canceled if weather changes. No bait used."
	storm_cast_button.pressed.connect(func() -> void: client.fish(false, true))
	inventory_box.add_child(storm_cast_button)
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
	cook_button.pressed.connect(func() -> void: quick_cook(false))
	inventory_box.add_child(cook_button)
	var stew_cook_button := Button.new()
	stew_cook_button.name = "QuickCookCampFishStew"
	stew_cook_button.text = "Shift+0: Cook fish stew (fish + clean water + wood)"
	stew_cook_button.tooltip_text = "At an active campfire or the hub workbench. Makes 1 meal for hunger and thirst."
	stew_cook_button.pressed.connect(func() -> void: quick_cook(true))
	inventory_box.add_child(stew_cook_button)
	var stew_eat_button := Button.new()
	stew_eat_button.name = "EatCampFishStew"
	stew_eat_button.text = "Shift+1: Eat fish stew (+40 food, +38 water)"
	stew_eat_button.pressed.connect(func() -> void: client.use_item(Defs.CAMP_FISH_STEW))
	inventory_box.add_child(stew_eat_button)
	var smoked_craft := Button.new()
	smoked_craft.name = "QuickSmokeTrailFish"
	smoked_craft.text = "Alt+0: Smoke highest craftable fish (2 wood + 1 fiber)"
	smoked_craft.tooltip_text = "A lit campfire or hub workbench is required. Smoked fish T1-T4 is safe travel food and reduces hunger use for a short time."
	smoked_craft.pressed.connect(quick_smoke)
	inventory_box.add_child(smoked_craft)
	var smoked_eat := Button.new()
	smoked_eat.name = "EatSmokedTrailFish"
	smoked_eat.text = "Eat best carried smoked fish: travel hunger protection"
	smoked_eat.tooltip_text = "Consumes one real smoked ration. Tier 1-4 reduces natural hunger loss for 210-390 seconds. It does not increase combat power."
	smoked_eat.pressed.connect(eat_smoked)
	inventory_box.add_child(smoked_eat)
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

	# Narrative chapter is independent from the recurring camp contracts:
	# evidence and combat milestones are awarded only by authoritative play.
	var story_heading := Label.new()
	story_heading.text = StoryCampaign.TITLE + " (hub radio)"
	inventory_box.add_child(story_heading)
	var story_actions := HBoxContainer.new()
	inventory_box.add_child(story_actions)
	var tune_radio := Button.new()
	tune_radio.name = "StoryListen"
	tune_radio.text = "Listen to Beacon Seven"
	tune_radio.tooltip_text = "At any camp workbench: begin Chapter I. Only a real dangerous-zone ruin opens the evidence stage."
	tune_radio.pressed.connect(func() -> void: client.story("listen"))
	story_actions.add_child(tune_radio)
	var transmit := Button.new()
	transmit.name = "StoryTransmit"
	transmit.text = "Transmit the recording"
	transmit.tooltip_text = "Finish the chapter after recovering a ruin cache and defeating three infected; requires inventory space."
	transmit.pressed.connect(func() -> void: client.story("transmit"))
	story_actions.add_child(transmit)
	_story_journal = Label.new()
	_story_journal.name = "StoryJournal"
	_story_journal.text = "Waiting for an encrypted survivor radio channel..."
	_story_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_story_journal)

	var chapter_two_heading := Label.new()
	chapter_two_heading.text = StoryChapterTwo.TITLE + " (requires Chapter I)"
	inventory_box.add_child(chapter_two_heading)
	var chapter_two_actions := HBoxContainer.new()
	inventory_box.add_child(chapter_two_actions)
	var decode := Button.new()
	decode.name = "StoryDecode"
	decode.text = "Decode the underground signal"
	decode.tooltip_text = "Once Chapter I ends, decode the second radio transmission at a workbench."
	decode.pressed.connect(func() -> void: client.story("decode"))
	chapter_two_actions.add_child(decode)
	var seal := Button.new()
	seal.name = "StorySeal"
	seal.text = "Seal the signal"
	seal.tooltip_text = "Final choice: silence the research relay. This decision cannot be undone."
	seal.pressed.connect(func() -> void: client.story("seal"))
	chapter_two_actions.add_child(seal)
	var broadcast := Button.new()
	broadcast.name = "StoryBroadcast"
	broadcast.text = "Broadcast the truth"
	broadcast.tooltip_text = "Final choice: warn all surviving settlements. This decision cannot be undone."
	broadcast.pressed.connect(func() -> void: client.story("broadcast"))
	chapter_two_actions.add_child(broadcast)
	_story2_journal = Label.new()
	_story2_journal.name = "StoryChapterTwoJournal"
	_story2_journal.text = "Complete Chapter I to unlock the underground story."
	_story2_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_story2_journal)

	var chapter_three_heading := Label.new()
	chapter_three_heading.text = StoryChapterThree.TITLE + " (requires Chapter II)"
	inventory_box.add_child(chapter_three_heading)
	var chapter_three_actions := HBoxContainer.new()
	inventory_box.add_child(chapter_three_actions)
	var trace_convoy := Button.new()
	trace_convoy.name = "StoryTraceConvoy"
	trace_convoy.text = "Trace missing convoy"
	trace_convoy.tooltip_text = "After Chapter II, find the convoy frequency at a real workbench."
	trace_convoy.pressed.connect(func() -> void: client.story("trace"))
	chapter_three_actions.add_child(trace_convoy)
	var guide_convoy := Button.new()
	guide_convoy.name = "StoryGuideConvoy"
	guide_convoy.text = "Guide convoy to safety"
	guide_convoy.tooltip_text = "Final choice: reveal the safe route. ASH may hear the signal."
	guide_convoy.pressed.connect(func() -> void: client.story("guide"))
	chapter_three_actions.add_child(guide_convoy)
	var mask_convoy := Button.new()
	mask_convoy.name = "StoryMaskConvoy"
	mask_convoy.text = "Mask convoy route"
	mask_convoy.tooltip_text = "Final choice: send false coordinates and hide the survivors."
	mask_convoy.pressed.connect(func() -> void: client.story("mask"))
	chapter_three_actions.add_child(mask_convoy)
	_story3_journal = Label.new()
	_story3_journal.name = "StoryChapterThreeJournal"
	_story3_journal.text = "Finish Chapter II to reveal the missing convoy."
	_story3_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_story3_journal)

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

	_action_sections.append([inventory_box.get_child_count(), "Party"])
	var party_title := Label.new()
	party_title.text = "Survivor party (nearby invites, up to 5 players)"
	inventory_box.add_child(party_title)
	_party_status = Label.new()
	_party_status.text = "No party. Invite a nearby survivor to fight together."
	inventory_box.add_child(_party_status)
	_party_target = OptionButton.new()
	inventory_box.add_child(_party_target)
	var provision_row := HBoxContainer.new()
	inventory_box.add_child(provision_row)
	for kind in ["food", "water", "kit", "stew"]:
		var package_kind: String = kind
		var provision_button := Button.new()
		provision_button.name = "CampProvision" + package_kind.capitalize()
		provision_button.text = "Give " + package_kind.capitalize()
		provision_button.tooltip_text = "Give real supplies to the selected teammate at the same burning campfire (3.2m, shared aid cooldown)."
		provision_button.pressed.connect(func() -> void:
			var selected: int = _party_target.get_selected_id()
			if selected < 0:
				say("Choose a nearby party ally to provision.")
			else:
				client.party_provision(selected, package_kind))
		provision_row.add_child(provision_button)
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
	_action_sections.append([inventory_box.get_child_count(), "Combat"])
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
	var rescue_button := Button.new()
	rescue_button.name = "ShareLostGearWithParty"
	rescue_button.text = "Ask party to recover dropped gear"
	rescue_button.tooltip_text = "Opt-in: share your actual full-loot bag with teammates for up to 90 seconds. Loot remains public."
	rescue_button.pressed.connect(func() -> void: client.party_corpse_rescue())
	party_buttons.add_child(rescue_button)
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
	var shield_button := Button.new()
	shield_button.name = "PartyShieldWall"
	shield_button.text = "Shield Wall (party melee)"
	shield_button.tooltip_text = "Guardian with an owned melee weapon: nearby allies within 5.5m take 22% less infected claw damage (12% boss claw) for 6 seconds. Costs 30 energy, 32s cooldown; no PvP, acid or AoE."
	shield_button.pressed.connect(func() -> void: client.party_shield_wall())
	inventory_box.add_child(shield_button)
	var intercept_button := Button.new()
	intercept_button.name = "GuardianIntercept"
	intercept_button.text = "Guard ally (one PvE hit)"
	intercept_button.tooltip_text = "Melee guardian: choose a party ally above (within 4.5m). Spend 20 energy to block their next infected melee hit for up to 9s; 28s cooldown. Not PvP/AoE/acid."
	intercept_button.pressed.connect(func() -> void:
		var target_id: int = _party_target.get_selected_id()
		if target_id < 0:
			say("Guardian: choose a nearby party ally first.")
		else:
			client.guardian_intercept(target_id))
	inventory_box.add_child(intercept_button)
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
	# Equipment-free field support; real medicine, food or water is consumed.
	_action_sections.append([inventory_box.get_child_count(), "Party"])
	var aid_row := HBoxContainer.new()
	inventory_box.add_child(aid_row)
	var aid_items := OptionButton.new()
	aid_items.add_item("Auto (choose carried medicine)")
	aid_items.set_item_metadata(0, "auto")
	for item_id in PartyAid.medical_items():
		var index: int = aid_items.item_count
		aid_items.add_item(str(Defs.item(item_id).get("name", item_id)))
		aid_items.set_item_metadata(index, item_id)
	for item_id in ["berries", "canned_food", "water_bottle"]:
		var index: int = aid_items.item_count
		aid_items.add_item(str(Defs.item(item_id).get("name", item_id)))
		aid_items.set_item_metadata(index, item_id)
	aid_items.select(0)
	aid_row.add_child(aid_items)
	var aid_button := Button.new()
	aid_button.text = "Aid / Share"
	aid_button.tooltip_text = "Auto treats wounds only. Select a medical item, bite sealant, food or water to share manually. Bite sealant protects an ally for 90s, outside combat. Range 3.2m, cooldown 5s."
	aid_button.pressed.connect(func() -> void:
		var target: int = _party_target.get_selected_id()
		if target < 0 or aid_items.selected < 0:
			say("Aid / Share: select a nearby party member and a carried supply.")
		else:
			client.party_aid(target, str(aid_items.get_selected_metadata())))
	aid_row.add_child(aid_button)
	var supplies_row := HBoxContainer.new()
	inventory_box.add_child(supplies_row)
	var need_food := Button.new()
	need_food.text = "Request food"
	need_food.tooltip_text = "Ask your party for food only when hunger is 60 or lower. 30s shared signal cooldown."
	need_food.pressed.connect(func() -> void: client.party_supply_request("food"))
	supplies_row.add_child(need_food)
	var need_water := Button.new()
	need_water.text = "Request water"
	need_water.tooltip_text = "Ask your party for water only when thirst is 60 or lower. 30s shared signal cooldown."
	need_water.pressed.connect(func() -> void: client.party_supply_request("water"))
	supplies_row.add_child(need_water)
	var triage_button := Button.new()
	triage_button.text = "Triage nearby allies"
	triage_button.tooltip_text = "Spend one crafted pack to treat up to 3 nearby allies (5.5m, 18s cooldown). Infected fighting them may turn toward the medic."
	triage_button.pressed.connect(func() -> void: client.party_triage())
	inventory_box.add_child(triage_button)
	var cover_button := Button.new()
	cover_button.name = "MedicCover"
	cover_button.text = "Medic Cover (staff + guardian)"
	cover_button.tooltip_text = "Restore-staff medic: 24 energy, 30s cooldown. A nearby equipped frontline guardian intercepts up to 3 already engaged infected (not raid bosses). No free healing or PvP aggro."
	cover_button.pressed.connect(func() -> void: client.medic_cover())
	inventory_box.add_child(cover_button)
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

	_action_sections.append([inventory_box.get_child_count(), "Trade"])
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
	# Albion-style alliances (guild leaders, hub): invite the leader picked in the barter target list.
	var alliance_row := HBoxContainer.new()
	inventory_box.add_child(alliance_row)
	var ally_invite := Button.new()
	ally_invite.text = "Alliance invite"
	ally_invite.tooltip_text = "Guild leaders at the hub: invite the guild of the survivor chosen as barter target."
	ally_invite.pressed.connect(func() -> void:
		if _trade_target.selected < 0:
			say("Alliance: choose a survivor in the barter target list.")
		else:
			client.alliance("invite", _trade_target.get_item_id(_trade_target.selected)))
	alliance_row.add_child(ally_invite)
	for ally_action in ["accept", "leave", "status"]:
		var ally_button := Button.new()
		ally_button.text = "Alliance %s" % ally_action
		ally_button.pressed.connect(func() -> void: client.alliance(ally_action))
		alliance_row.add_child(ally_button)
	# Albion-style guild bank (hub): members deposit, officers withdraw.
	_guild_vault_select = OptionButton.new()
	_guild_vault_select.custom_minimum_size.x = 320.0
	_guild_vault_select.tooltip_text = "Guild bank contents (press Guild bank to refresh)."
	inventory_box.add_child(_guild_vault_select)
	var guild_row := HBoxContainer.new()
	inventory_box.add_child(guild_row)
	var vault_view := Button.new()
	vault_view.text = "Guild bank"
	vault_view.pressed.connect(func() -> void: client.guild_bank("list"))
	guild_row.add_child(vault_view)
	var vault_put := Button.new()
	vault_put.text = "Deposit barter item"
	vault_put.tooltip_text = "Moves the market quantity of the item chosen in the barter selector into the guild bank."
	vault_put.pressed.connect(func() -> void:
		if _trade_item.selected < 0:
			say("Guild bank: choose an item in the barter selector.")
		else:
			client.guild_bank("deposit", str(_trade_item.get_item_metadata(_trade_item.selected)), int(_market_quantity.value)))
	guild_row.add_child(vault_put)
	var vault_take := Button.new()
	vault_take.text = "Withdraw (officers)"
	vault_take.pressed.connect(func() -> void:
		if _guild_vault_select.selected < 0:
			say("Guild bank: open it and pick an item first.")
		else:
			client.guild_bank("withdraw", str(_guild_vault_select.get_item_metadata(_guild_vault_select.selected)), int(_market_quantity.value)))
	guild_row.add_child(vault_take)
	# Homestead farming: plant seeds from the hub trader in the green zone, harvest when ripe.
	var farm_row := HBoxContainer.new()
	inventory_box.add_child(farm_row)
	for crop in Farming.CROPS:
		var seed_id: String = str(Farming.CROPS[crop]["seed"])
		var plant_button := Button.new()
		plant_button.text = "Plant %s" % crop
		plant_button.tooltip_text = "Plants one %s in front of you (green zone, up to %d plots). Ripe in %d min." % [
			str(Defs.item(seed_id).get("name", seed_id)), Farming.MAX_PLOTS, int(float(Farming.CROPS[crop]["seconds"]) / 60.0)]
		plant_button.pressed.connect(func() -> void: client.plant(seed_id))
		farm_row.add_child(plant_button)
	var harvest_button := Button.new()
	harvest_button.text = "Harvest"
	harvest_button.tooltip_text = "Harvests your nearest ripe plot within 3 m."
	harvest_button.pressed.connect(func() -> void: client.harvest())
	farm_row.add_child(harvest_button)
	# Faction warfare (hub): enlist, raise or lower the flag, redeem faction points.
	var faction_row := HBoxContainer.new()
	inventory_box.add_child(faction_row)
	for faction_id in Factions.FACTIONS:
		var join := Button.new()
		join.text = "Join %s" % Factions.FACTIONS[faction_id]
		join.tooltip_text = "Enlist at the hub. Switching factions forfeits unspent faction points."
		join.pressed.connect(func() -> void: client.faction("enlist", faction_id))
		faction_row.add_child(join)
	var flag_button := Button.new()
	flag_button.text = "Faction flag on/off"
	flag_button.tooltip_text = "Flagged: fight flagged rival factions outside safe towns, even in the yellow zone. Lowering the flag takes 10 s."
	flag_button.pressed.connect(func() -> void:
		client.faction("unflag" if bool(client.you.get("faction_flagged", false)) else "flag"))
	faction_row.add_child(flag_button)
	var redeem_button := Button.new()
	redeem_button.text = "Redeem %d pts" % Factions.REDEEM_COST
	redeem_button.tooltip_text = "Hub only: %d faction points for 60 silver and 3 runes." % Factions.REDEEM_COST
	redeem_button.pressed.connect(func() -> void: client.faction("redeem"))
	faction_row.add_child(redeem_button)
	# Albion-style buy orders: escrow silver now, sellers fill it at the hub, goods wait for you there.
	_bid_select = OptionButton.new()
	_bid_select.custom_minimum_size.x = 320.0
	_bid_select.tooltip_text = "Buy orders (highest price first). Sell to one to get paid instantly."
	inventory_box.add_child(_bid_select)
	var bid_row := HBoxContainer.new()
	inventory_box.add_child(bid_row)
	var place_bid := Button.new()
	place_bid.text = "Place buy order"
	place_bid.tooltip_text = "Escrows quantity x price silver for the selected listing's item (or your barter item)."
	place_bid.pressed.connect(func() -> void:
		var bid_item := ""
		if _market_select.selected >= 0 and _market_select.selected < _market_listings.size():
			for order in _market_listings:
				if int(order["id"]) == int(_market_select.get_item_metadata(_market_select.selected)):
					bid_item = str(order["item"])
		if bid_item == "" and _trade_item.selected >= 0:
			bid_item = str(_trade_item.get_item_metadata(_trade_item.selected))
		if bid_item == "":
			say("Buy order: select a listing or an item first.")
		else:
			client.market_bid(bid_item, int(_market_quantity.value), int(_market_price.value)))
	bid_row.add_child(place_bid)
	var fill_bid := Button.new()
	fill_bid.text = "Sell to order"
	fill_bid.pressed.connect(func() -> void:
		if _bid_select.selected < 0:
			say("Buy order: select an order to sell into.")
		else:
			client.market_fill(int(_bid_select.get_item_metadata(_bid_select.selected)), int(_market_quantity.value)))
	bid_row.add_child(fill_bid)
	var cancel_bid := Button.new()
	cancel_bid.text = "Cancel my order"
	cancel_bid.pressed.connect(func() -> void:
		if _bid_select.selected >= 0:
			client.market_cancel_bid(int(_bid_select.get_item_metadata(_bid_select.selected))))
	bid_row.add_child(cancel_bid)

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
	_craft_use_stash = CheckBox.new()
	_craft_use_stash.text = "Use bank"
	_craft_use_stash.tooltip_text = "Craft with carried + protected stash materials at the main HUB workbench only. Finished items enter your backpack. Cannot use at other villages or field stations."
	_craft_use_stash.toggled.connect(func(_value: bool) -> void:
		_craft_signature = ""
		_refresh_crafting())
	craft_controls.add_child(_craft_use_stash)
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
	# A fixed-width card centred on the screen; long messages wrap instead of running off the right edge.
	_death.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death.offset_left = -340.0
	_death.offset_right = 340.0
	_death.offset_top = -70.0
	_death.offset_bottom = 70.0
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
		if event.physical_keycode == KEY_QUOTELEFT and _skin != null: # Every F key is a game action; ` is the usual debug key.
			set_details_visible(not _skin.details_visible)
		if event.physical_keycode == KEY_M and _radar != null:
			_radar.visible = not _radar.visible


## Invoked from the online '0' key and inventory button.
func quick_cook(stew: bool = false) -> void:
	if stew:
		# Same server-side crafting rules as any manually selected campfire recipe.
		client.craft(Defs.CAMP_FISH_STEW, 1)
		return
	var recipe_id: String = QuickCooking.best_recipe(
		client.inventory, int(client.you.get("crafting_level", 1)))
	if recipe_id.is_empty():
		say("Cooking: need fish, matching wood and sufficient crafting mastery")
	else:
		client.craft(recipe_id, 1)


func quick_smoke() -> void:
	var recipe: String = TrailRation.best_recipe(
		client.inventory, int(client.you.get("crafting_level", 1)))
	if recipe.is_empty():
		say("Smoking fish needs raw fish, 2 matching wood and 1 fiber, plus crafting mastery.")
	else:
		client.craft(recipe, 1)


func eat_smoked() -> void:
	for tier in range(Defs.MAX_TIER, 0, -1):
		var item_id: String = "smoked_fish" if tier == 1 else "smoked_fish_%d" % tier
		if client.inventory.count(item_id) > 0:
			client.use_item(item_id)
			return
	say("No smoked fish carried. Cook some at a campfire first.")


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	_actions_panel.visible = _inventory_panel.visible and not _craft_panel.visible
	if _inventory_panel.visible:
		var view: Vector2 = get_viewport().get_visible_rect().size
		var content: Vector2 = _inventory_scroll.get_child(0).get_combined_minimum_size()
		_inventory_scroll.custom_minimum_size = Vector2(content.x + 14.0, view.y - 84.0 - 112.0 - 32.0)
		_dock(_inventory_panel, false)
		_dock(_actions_panel, true)
		client.market_list()


## Windows sit against a side of the screen, under the menu buttons and above the action bar, like the bag and the
## workshop windows of an online RPG, so the character in the middle stays in view.
func _dock(panel: Control, left: bool) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var width: float = maxf(panel.get_combined_minimum_size().x, 300.0)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16.0 if left else view.x - width - 16.0, 84.0)
	panel.size = Vector2(width, minf(view.y - 84.0 - 112.0, maxf(panel.get_combined_minimum_size().y, 300.0)))


## The inventory window holds the backpack, the stash and dozens of actions added over time. Laid out like the bag of an
## online RPG: the bag docked on the right (what you wear on top, then icon slots for the backpack and the protected
## stash), the actions docked on the left and sorted into tabs (gear, field, trade, party, combat), so each tab is one
## short list instead of a hundred buttons in a row.
func _arrange_inventory_window() -> void:
	var box: VBoxContainer = _inventory_panel.get_child(0)
	# The section marks are positions in this list as built: take it before anything moves out of it.
	var built: Array = box.get_children()
	_inventory_panel.remove_child(box)
	var window := VBoxContainer.new()
	window.add_theme_constant_override("separation", 8)
	window.add_child(_window_header("Inventory", "Your bag", toggle_inventory))
	_inventory_summary = Label.new()
	_inventory_summary.add_theme_font_size_override("font_size", 12)
	_inventory_summary.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	window.add_child(_inventory_summary)
	# The character's equipment as a paper doll: three sockets over three, the carry weight beside it.
	var doll_row := HBoxContainer.new()
	doll_row.add_theme_constant_override("separation", 14)
	doll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	window.add_child(doll_row)
	_doll = GridContainer.new()
	_doll.columns = 3
	_doll.add_theme_constant_override("h_separation", 10)
	_doll.add_theme_constant_override("v_separation", 10)
	doll_row.add_child(_doll)
	_doll_info = VBoxContainer.new()
	_doll_info.alignment = BoxContainer.ALIGNMENT_CENTER
	_doll_info.custom_minimum_size.x = 130
	doll_row.add_child(_doll_info)
	_load_quick_slots()
	window.add_child(_rule())
	window.add_child(_section_label("BACKPACK", "Double click or drag onto a lit slot: equip.  Right click: stash one at a workbench."))
	var stash_scroll: Control = _stash_grid.get_parent()
	var stash_title: Control = box.get_child(stash_scroll.get_index() - 1)
	_inventory_grid.get_parent().remove_child(_inventory_grid)
	_inventory_grid.columns = 6
	_inventory_grid.add_theme_constant_override("h_separation", 6)
	_inventory_grid.add_theme_constant_override("v_separation", 6)
	window.add_child(_inventory_grid)
	stash_title.get_parent().remove_child(stash_title)
	stash_title.queue_free()
	window.add_child(_section_label("PROTECTED STASH", "Survives death. Click to take one out at a workbench."))
	stash_scroll.get_parent().remove_child(stash_scroll)
	stash_scroll.custom_minimum_size = Vector2(6 * 70, 60)
	_stash_grid.columns = 7
	_stash_grid.add_theme_constant_override("h_separation", 5)
	_stash_grid.add_theme_constant_override("v_separation", 5)
	window.add_child(stash_scroll)
	for moved in [box.get_node("DepositAllMaterials"), box.get_node("ExpeditionRestock")]:
		moved.get_parent().remove_child(moved)
		window.add_child(moved)
		for inner in moved.get_children():
			(inner as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The bag scrolls when the screen is shorter than everything in it (toggle_inventory sizes it to the screen).
	_inventory_scroll = ScrollContainer.new()
	_inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_scroll.add_child(window)
	var bag_row := HBoxContainer.new()
	bag_row.add_theme_constant_override("separation", 8)
	bag_row.add_child(_category_bar(_bag_filter, func() -> void: _inventory_signature = ""))
	bag_row.add_child(_inventory_scroll)
	_inventory_panel.add_child(bag_row)

	# The actions, in build order, split at the section marks into tabs, in their own window on the left.
	_actions_panel = PanelContainer.new()
	_actions_panel.name = "ActionsWindow"
	_actions_panel.visible = false
	add_child(_actions_panel)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_actions_panel.add_child(actions)
	actions.add_child(_window_header("Actions", "Survivor's", func() -> void: _actions_panel.visible = false))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(430, 560)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_tabs = tabs
	actions.add_child(tabs)
	var pages: Dictionary = {}
	var children: Array = built
	var section := 0
	for index in children.size():
		while section + 1 < _action_sections.size() and index >= int(_action_sections[section + 1][0]):
			section += 1
		var child: Node = children[index]
		if child.is_queued_for_deletion() or child.get_parent() != box:
			continue
		if index == 0 and child is Label:
			child.queue_free() # The old one-line title; the window header replaces it.
			continue
		var tab_name: String = str(_action_sections[section][1])
		if not pages.has(tab_name):
			var scroll := ScrollContainer.new()
			scroll.name = tab_name
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var page := VBoxContainer.new()
			page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			page.add_theme_constant_override("separation", 6)
			scroll.add_child(page)
			tabs.add_child(scroll)
			pages[tab_name] = page
		box.remove_child(child)
		(pages[tab_name] as VBoxContainer).add_child(child)
	box.queue_free()
	for page in pages.values():
		_style_action_page(page)
	tabs.current_tab = 0
	# The workshop gets the same window header; its old one-line title becomes the hint under it.
	var craft_box: VBoxContainer = _craft_panel.get_child(0)
	var craft_hint: Label = craft_box.get_child(0)
	craft_hint.text = "At a workbench in the hub or a village, or the field bench of a held outpost."
	craft_hint.add_theme_font_size_override("font_size", 12)
	craft_hint.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	var craft_header := _window_header("Workshop", "Survivor's", toggle_crafting)
	craft_box.add_child(craft_header)
	craft_box.move_child(craft_header, 0)
	_craft_panel.remove_child(craft_box)
	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 8)
	craft_row.add_child(_category_bar(_craft_filter, func() -> void: _craft_signature = ""))
	craft_row.add_child(craft_box)
	_craft_panel.add_child(craft_row)


## A window title: small owner line over a large name, a close button on the right.
func _window_header(title: String, owner: String, close_action: Callable) -> Control:
	var row := HBoxContainer.new()
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	var small := Label.new()
	small.text = owner
	small.add_theme_font_size_override("font_size", 12)
	small.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	names.add_child(small)
	var big := Label.new()
	big.text = title
	big.add_theme_font_size_override("font_size", 26)
	big.add_theme_color_override("font_color", UiTheme.INK)
	names.add_child(big)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var close := Button.new()
	close.text = "X"
	close.tooltip_text = "Close"
	close.custom_minimum_size = Vector2(30, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var round := UiTheme._box(UiTheme.WOOD, 15, 2.0, UiTheme.CREAM, 0)
	for state in ["normal", "hover", "pressed"]:
		close.add_theme_stylebox_override(state, round if state != "hover" else UiTheme._box(UiTheme.ACCENT, 15, 2.0, UiTheme.CREAM, 0))
	close.pressed.connect(close_action)
	row.add_child(close)
	return row


## Round buttons in the top right corner for every window: each presses the window's own hotkey, so the mouse and the
## keyboard always do exactly the same thing.
func _build_menu_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "MenuBar"
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -16.0
	bar.offset_top = 14.0
	add_child(bar)
	for entry in [["menu_inventory", "Inventory (I)", KEY_I], ["menu_crafting", "Crafting (C)", KEY_C], ["menu_skills", "Skills and perks (K)", KEY_K],
			["menu_map", "World map (J)", KEY_J], ["menu_help", "Controls (F2)", KEY_F2]]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(46, 46)
		button.tooltip_text = str(entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.icon = load("res://assets/icons/ui/%s.svg" % entry[0]) if ResourceLoader.exists("res://assets/icons/ui/%s.svg" % entry[0]) else null
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for state in ["normal", "hover", "pressed"]:
			var round := StyleBoxFlat.new()
			round.anti_aliasing = true
			round.bg_color = Color(0.3, 0.2, 0.12) if state == "normal" else (Color(0.42, 0.29, 0.17) if state == "hover" else UiTheme.ACCENT)
			round.set_corner_radius_all(23)
			round.set_border_width_all(3)
			round.border_color = Color(0.72, 0.55, 0.3) if state != "hover" else UiTheme.GOLD
			round.set_content_margin_all(10)
			round.shadow_color = Color(0, 0, 0, 0.4)
			round.shadow_size = 4
			round.shadow_offset = Vector2(0, 2)
			button.add_theme_stylebox_override(state, round)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, Color(0.98, 0.92, 0.8))
		var key: int = entry[2]
		button.pressed.connect(func() -> void: _press_key(key))
		bar.add_child(button)


func _press_key(key: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)


# Effects on you, as round icons under the portrait: [snapshot key, icon, name, debuff, how the number reads].
# "pct" shows the value as percent, "s" as seconds left, "hits" as charges, "" as a flag.
const EFFECTS := [
	["infection", "spore_culture", "Infection: grows until treated with antiseptic or antibiotics", true, "pct"],
	["food_poisoning", "herbal_gut_tonic", "Food poisoning: extra thirst and gradual health loss. Use herbal stomach remedy.", true, "pct"],
	["bleeding", "bandage", "Bleeding: bandage it", true, "pct"],
	["fracture", "field_splint", "Fracture: slows you; a splint helps", true, "pct"],
	["exposure", "thermal_wrap", "Cold: warm up at a fire, in shelter or with a heat pack", true, "pct"],
	["combat_tag_seconds", "machete", "In combat: logging out now drops your gear in full-loot zones", true, "s"],
	["meal_seconds", "cooked_fish", "Hearty meal: better regeneration", false, "s"],
	["ration_seconds", "smoked_fish", "Smoked travel ration: slower hunger drain", false, "s"],
	["coating_seconds", "antiseptic_edge_oil", "Antiseptic edge oil on your weapon", false, "s"],
	["sharpened_hits", "field_whetstone", "Sharpened weapon", false, "hits"],
	["sighted_hits", "field_sighting_kit", "Sighted weapon", false, "hits"],
	["plated_hits", "field_armor_plate", "Armor plate", false, "hits"],
	["scent_mask_seconds", "herbal_scent_mask", "Scent salve: the infected smell you less", false, "s"],
	["soft_sole_seconds", "soft_sole_wraps", "Soft soles: quieter steps", false, "s"],
	["spore_filter_seconds", "spore_filter", "Spore filter", false, "s"],
	["storm_insulator_seconds", "storm_insulator", "Storm insulation", false, "s"],
	["chain_wrap_seconds", "bike_chain_wrap", "Quiet bike chain", false, "s"],
	["tire_grip_seconds", "trail_tire_grips", "Tire grips", false, "s"],
	["flare_seconds", "signal_flare", "Signal flare burning", false, "s"],
	["warmth_seconds", "stormproof_briquette", "Warm", false, "s"],
	["tent_sheltered", "storm_tarp_anchors", "Sheltered under a tarp", false, ""],
	["rested_xp_credit", "return_charm", "Rested: bonus training", false, ""],
	["warden_ward", "warden_jacket", "Warden's ward", false, ""],
	["guardian_guarded_seconds", "siege_blast_brace", "Guarded by an ally", false, "s"],
	["recall_seconds", "return_charm", "Returning to the settlement", false, "s"],
]


## The column under the portrait: the "+" for the community window and your buffs and debuffs on one row, the party
## below it. The quest card follows under it (hud_skin.gd reads where this column ends).
func _build_left_column() -> void:
	_left_column = VBoxContainer.new()
	_left_column.name = "LeftColumn"
	_left_column.position = Vector2(40, 102)
	_left_column.add_theme_constant_override("separation", 8)
	_left_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_child(row)
	var plus := Button.new()
	plus.text = "+"
	plus.tooltip_text = "Community: group, guild, friends"
	plus.custom_minimum_size = Vector2(28, 28)
	plus.focus_mode = Control.FOCUS_NONE
	plus.add_theme_font_size_override("font_size", 20)
	plus.add_theme_color_override("font_color", UiTheme.GOLD)
	for state in ["normal", "hover", "pressed"]:
		var round := StyleBoxFlat.new()
		round.anti_aliasing = true
		round.bg_color = Color(0.3, 0.2, 0.12) if state == "normal" else (Color(0.42, 0.29, 0.17) if state == "hover" else UiTheme.ACCENT)
		round.set_corner_radius_all(14)
		round.set_border_width_all(2)
		round.border_color = Color(0.72, 0.55, 0.3)
		round.content_margin_top = -5
		button_shadow(round)
		plus.add_theme_stylebox_override(state, round)
	plus.pressed.connect(toggle_social)
	row.add_child(plus)
	# The effects sit right under the health and energy bars, as in the portrait frames of online RPGs.
	_buff_row = HFlowContainer.new()
	_buff_row.name = "Effects"
	_buff_row.position = Vector2(96, 78)
	_buff_row.size = Vector2(230, 26)
	_buff_row.add_theme_constant_override("h_separation", 4)
	_buff_row.add_theme_constant_override("v_separation", 4)
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buff_row)
	_party_list = VBoxContainer.new()
	_party_list.add_theme_constant_override("separation", 4)
	_party_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_child(_party_list)


static func button_shadow(style: StyleBoxFlat) -> void:
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)


## Rebuilds the buffs and the party when they change (numbers in whole seconds, so about once a second at most).
func _refresh_left_column() -> void:
	if _left_column == null:
		return
	var you: Dictionary = client.you
	var shown: Array = []
	# Food and water always lead the row; they turn red when running out.
	shown.append([["hunger", "canned_food", "Food: eat before it runs out", float(you.get("hunger", 100.0)) < 20.0, "pct"], float(you.get("hunger", 100.0))])
	shown.append([["thirst", "water_bottle", "Water: drink at a lake or from a bottle", float(you.get("thirst", 100.0)) < 20.0, "pct"], float(you.get("thirst", 100.0))])
	for effect in EFFECTS:
		var raw: Variant = you.get(effect[0], 0)
		var value: float = 1.0 if raw is bool and raw else (float(raw) if (raw is float or raw is int) else 0.0)
		if (effect[0] in ["infection", "food_poisoning", "bleeding", "fracture", "exposure"] and value < 0.5) or value <= 0.0:
			continue
		shown.append([effect, value])
	var roster: Array = []
	var party: Variant = you.get("party", {})
	if party is Dictionary and int(party.get("id", 0)) > 0 and party.get("roster", []) is Array:
		roster = party["roster"]
	var signature := ""
	for entry in shown:
		signature += "%s:%d," % [entry[0][0], int(entry[1])]
	signature += "|" + str(roster) + "|" + str(party.get("leader", 0) if party is Dictionary else 0)
	if signature != _left_signature:
		_left_signature = signature
		for child in _buff_row.get_children():
			child.queue_free()
		for entry in shown:
			_buff_row.add_child(_effect_icon(entry[0], entry[1]))
		for child in _party_list.get_children():
			child.queue_free()
		for member in roster.slice(0, PartyFrames.MAX_VISIBLE_MEMBERS):
			if member is Dictionary:
				_party_list.add_child(_party_member_row(member, int(party.get("leader", 0))))
	if _skin != null:
		_skin._vitals_bottom = maxf(_buff_row.position.y + _buff_row.get_combined_minimum_size().y,
			_left_column.position.y + _left_column.get_combined_minimum_size().y)


func _effect_icon(effect: Array, value: float) -> Control:
	var debuff: bool = effect[3]
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(26, 26)
	var round := StyleBoxFlat.new()
	round.anti_aliasing = true
	round.bg_color = Color(0.32, 0.08, 0.07, 0.92) if debuff else Color(0.12, 0.2, 0.1, 0.92)
	if not debuff and effect[0] in ["hunger", "thirst"]:
		round.bg_color = Color(0.16, 0.11, 0.07, 0.92)
	round.set_corner_radius_all(13)
	round.set_border_width_all(2)
	round.border_color = Color(0.95, 0.35, 0.3) if debuff else (Color(0.72, 0.55, 0.3) if effect[0] in ["hunger", "thirst"] else Color(0.55, 0.85, 0.4))
	holder.add_theme_stylebox_override("panel", round)
	var unit: String = effect[4]
	var amount := ""
	match unit:
		"pct":
			amount = str(int(value)) if effect[0] in ["hunger", "thirst"] else "%d%%" % int(value)
		"s":
			amount = "%ds" % ceili(value) if value < 100.0 else "%dm" % ceili(value / 60.0)
		"hits":
			amount = str(int(value))
	holder.tooltip_text = str(effect[2]) + ("  (%s)" % amount if amount != "" else "")
	var art := TextureRect.new()
	art.texture = ItemIcons.icon(str(effect[1]))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	art.modulate = Color(1.0, 0.9, 0.86) if debuff else Color(0.95, 0.98, 0.9)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)
	if amount != "":
		var label := Label.new()
		label.text = amount
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, -2)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(label)
	return holder


## One party member under the "+": a round marker (gold for the leader), the name and a health bar.
func _party_member_row(member: Dictionary, leader: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var alive: bool = bool(member.get("alive", false))
	var marker := Panel.new()
	marker.custom_minimum_size = Vector2(26, 26)
	var round := StyleBoxFlat.new()
	round.anti_aliasing = true
	round.bg_color = Color(0.3, 0.24, 0.18) if alive else Color(0.25, 0.25, 0.25)
	round.set_corner_radius_all(13)
	round.set_border_width_all(2)
	round.border_color = UiTheme.GOLD if int(member.get("id", -1)) == leader else Color(0.72, 0.55, 0.3)
	marker.add_theme_stylebox_override("panel", round)
	var face := TextureRect.new()
	face.texture = load("res://assets/icons/ui/portrait.svg")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	face.modulate = Color(0.95, 0.88, 0.74)
	marker.add_child(face)
	row.add_child(marker)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	var name_label := Label.new()
	var name_text: String = str(member.get("name", "Survivor")).substr(0, PartyFrames.MAX_NAME_CHARS)
	name_label.text = ("★ " if int(member.get("id", -1)) == leader else "") + name_text + ("  (you)" if int(member.get("id", -1)) == client.peer_id else "") + ("" if alive else "  DOWN")
	name_label.add_theme_font_size_override("font_size", 12)
	column.add_child(name_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 7)
	bar.show_percentage = false
	bar.max_value = 100.0
	var health: float = float(member.get("health", 0.0))
	bar.value = clampf(health if is_finite(health) else 0.0, 0.0, 100.0) if alive else 0.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.2, 0.16)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.05, 0.03, 0.85)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	column.add_child(bar)
	row.add_child(column)
	return row


# --- Community window ("+"): group, guild, friends -----------------------------------------------------------------

func toggle_social() -> void:
	if _social_panel == null:
		_build_social_window()
	_social_panel.visible = not _social_panel.visible
	if _social_panel.visible:
		_actions_panel.visible = false
		_craft_panel.visible = false
		_dock(_social_panel, true)
		_refresh_guild_tab()
		_refresh_friends()


func _build_social_window() -> void:
	_social_panel = PanelContainer.new()
	_social_panel.name = "CommunityWindow"
	_social_panel.theme = UiTheme.paper_theme()
	_social_panel.visible = false
	add_child(_social_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_social_panel.add_child(box)
	box.add_child(_window_header("Community", "Survivor's", toggle_social))
	_social_tabs = TabContainer.new()
	_social_tabs.custom_minimum_size = Vector2(430, 520)
	box.add_child(_social_tabs)
	# Group: the party actions move here from the actions window.
	var party_page: Node = _inventory_tabs.get_node_or_null("Party") if _inventory_tabs != null else null
	if party_page != null:
		_inventory_tabs.remove_child(party_page)
		party_page.name = "Group"
		_social_tabs.add_child(party_page)
	# Guild: finder, create, members, leave.
	var guild_scroll := ScrollContainer.new()
	guild_scroll.name = "Guild"
	guild_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var guild := VBoxContainer.new()
	guild.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guild.add_theme_constant_override("separation", 8)
	guild_scroll.add_child(guild)
	_social_tabs.add_child(guild_scroll)
	_guild_status = Label.new()
	_guild_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guild.add_child(_guild_status)
	var guild_actions := HBoxContainer.new()
	var members := Button.new()
	members.text = "Members"
	members.pressed.connect(_show_guild_members)
	guild_actions.add_child(members)
	var leave := Button.new()
	leave.text = "Leave guild"
	leave.pressed.connect(func() -> void:
		if _social_ready():
			await social.leave_guild()
			_refresh_guild_tab())
	guild_actions.add_child(leave)
	guild.add_child(guild_actions)
	guild.add_child(_section_label("FIND A GUILD", "Search by the start of the name; empty lists every guild."))
	var search_row := HBoxContainer.new()
	var search := LineEdit.new()
	search.placeholder_text = "Guild name..."
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(search)
	var find := Button.new()
	find.text = "Search"
	find.pressed.connect(func() -> void: _search_guilds(search.text))
	search.text_submitted.connect(func(text: String) -> void: _search_guilds(text))
	search_row.add_child(find)
	guild.add_child(search_row)
	_guild_results = VBoxContainer.new()
	_guild_results.add_theme_constant_override("separation", 4)
	guild.add_child(_guild_results)
	guild.add_child(_section_label("FOUND A GUILD", "Three letters or more."))
	var create_row := HBoxContainer.new()
	var new_name := LineEdit.new()
	new_name.placeholder_text = "New guild name"
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(new_name)
	var create := Button.new()
	create.text = "Create"
	create.pressed.connect(func() -> void:
		if not _social_ready():
			return
		var result: Dictionary = await social.create_guild(new_name.text)
		say("Guild created." if result.get("ok", false) else "Guild: %s" % str(result.get("reason", "failed")))
		_refresh_guild_tab())
	create_row.add_child(create)
	guild.add_child(create_row)
	# Friends: list and requests.
	var friends_scroll := ScrollContainer.new()
	friends_scroll.name = "Friends"
	friends_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var friends := VBoxContainer.new()
	friends.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends.add_theme_constant_override("separation", 8)
	friends_scroll.add_child(friends)
	_social_tabs.add_child(friends_scroll)
	var add_row := HBoxContainer.new()
	var friend_name := LineEdit.new()
	friend_name.placeholder_text = "Player name"
	friend_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(friend_name)
	var add := Button.new()
	add.text = "Add friend"
	add.pressed.connect(func() -> void:
		if not _social_ready():
			return
		var result: Dictionary = await social.add_friend(friend_name.text)
		say("Friend request sent." if result.get("ok", false) else "Friends: %s" % str(result.get("reason", "failed")))
		_refresh_friends())
	add_row.add_child(add)
	friends.add_child(add_row)
	_friend_list = VBoxContainer.new()
	_friend_list.add_theme_constant_override("separation", 4)
	friends.add_child(_friend_list)
	_social_tabs.current_tab = 0


## Guilds and friends live in the online account; offline play has neither.
func _social_ready() -> bool:
	if social == null or social.session == null or social.session.is_exception():
		say("Guilds and friends need the online account (a Nakama server).")
		return false
	return true


func _refresh_guild_tab() -> void:
	if _guild_status == null:
		return
	if social == null or social.session == null:
		_guild_status.text = "Offline: guilds and friends need the online account (a Nakama server)."
		return
	_guild_status.text = "Your guild: %s" % str(social.guild.get("name", "none")) if not social.guild.is_empty() else "You are not in a guild yet. Find one below or found your own."


func _search_guilds(prefix: String) -> void:
	if not _social_ready():
		return
	for child in _guild_results.get_children():
		child.queue_free()
	var found: Array = await social.list_guilds(prefix.strip_edges())
	if found.is_empty():
		var none := Label.new()
		none.text = "No guild found."
		_guild_results.add_child(none)
	for entry in found:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s   ·   %d members%s" % [str(entry["name"]), int(entry["members"]), "" if bool(entry["open"]) else "   ·   invite only"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var join := Button.new()
		join.text = "Join"
		join.disabled = not social.guild.is_empty()
		var guild_id: String = str(entry["id"])
		join.pressed.connect(func() -> void:
			var result: Dictionary = await social.join_guild(guild_id)
			say("Joined the guild." if result.get("ok", false) else "Guild: %s" % str(result.get("reason", "request sent")))
			_refresh_guild_tab())
		row.add_child(join)
		_guild_results.add_child(row)


func _show_guild_members() -> void:
	if not _social_ready():
		return
	var names: Array = await social.guild_members()
	say("Guild members: %s" % (", ".join(names) if not names.is_empty() else "none"))


func _refresh_friends() -> void:
	if _friend_list == null:
		return
	for child in _friend_list.get_children():
		child.queue_free()
	if social == null or social.session == null:
		var offline := Label.new()
		offline.text = "Offline: friends need the online account."
		_friend_list.add_child(offline)
		return
	var friends: Array = await social.list_friends()
	if friends.is_empty():
		var none := Label.new()
		none.text = "No friends yet. Add someone by name above."
		_friend_list.add_child(none)
	for entry in friends:
		var label := Label.new()
		var state: String = ["", "  (request sent)", "  (wants to be friends: add them back)", "  (blocked)"][clampi(int(entry["state"]), 0, 3)]
		label.text = "%s %s%s" % ["●" if bool(entry["online"]) else "○", str(entry["name"]), state]
		label.add_theme_color_override("font_color", Color(0.2, 0.5, 0.15) if bool(entry["online"]) else UiTheme.INK_SOFT)
		_friend_list.add_child(label)


## The category an item belongs to, for the side buttons.
static func _item_category(item_id: String) -> String:
	match str(Defs.item(item_id).get("kind", "")):
		"weapon", "ammo":
			return "weapons"
		"armor", "head", "cape", "hands", "feet", "armor_plate", "carry_pack":
			return "gear"
		"food", "drink", "medical", "party_medical", "stimulant":
			return "supplies"
		"resource", "material", "currency":
			return "materials"
	return "other"


static func _filter_all(filter: Dictionary) -> bool:
	for key in filter:
		if not bool(filter[key]):
			return false
	return true


## A column of round toggle buttons on the side of a window: "All" and one per item category. Several can be on at once;
## "All" turns every category on, and off again when all already are.
func _category_bar(filter: Dictionary, changed: Callable) -> VBoxContainer:
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var buttons: Dictionary = {}
	var all := _category_button("res://assets/icons/ui/menu_inventory.svg", "All items (click again to clear)")
	bar.add_child(all)
	for entry in ITEM_CATEGORIES:
		var button := _category_button(ItemIcons.DIR + str(entry[2]) + ".svg", str(entry[1]))
		buttons[entry[0]] = button
		bar.add_child(button)
	var sync := func() -> void:
		all.set_pressed_no_signal(_filter_all(filter))
		for key in buttons:
			(buttons[key] as Button).set_pressed_no_signal(bool(filter[key]))
	all.pressed.connect(func() -> void:
		var everything: bool = not _filter_all(filter)
		for key in filter:
			filter[key] = everything
		sync.call()
		changed.call())
	for key in buttons:
		var category: String = key
		(buttons[key] as Button).pressed.connect(func() -> void:
			filter[category] = not bool(filter[category])
			sync.call()
			changed.call())
	sync.call()
	return bar


func _category_button(icon_path: String, tip: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(40, 40)
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var round := StyleBoxFlat.new()
		round.anti_aliasing = true
		var on: bool = state.contains("pressed")
		round.bg_color = Color(0.5, 0.17, 0.12) if on else Color(0.72, 0.62, 0.47)
		if state.begins_with("hover"):
			round.bg_color = round.bg_color.lightened(0.12)
		round.set_corner_radius_all(20)
		round.set_border_width_all(2)
		round.border_color = UiTheme.GOLD if on else Color(UiTheme.WOOD.r, UiTheme.WOOD.g, UiTheme.WOOD.b, 0.5)
		round.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, round)
	for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		button.add_theme_color_override(state, Color(UiTheme.WOOD.r, UiTheme.WOOD.g, UiTheme.WOOD.b, 0.75))
	for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
		button.add_theme_color_override(state, Color(1.0, 0.94, 0.82))
	return button


## A heading with a small hint under it.
func _section_label(text: String, hint: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", UiTheme.HEADING)
	column.add_child(header)
	if hint != "":
		var small := Label.new()
		small.text = hint
		small.add_theme_font_size_override("font_size", 12)
		small.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		column.add_child(small)
	return column


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(UiTheme.WOOD.r, UiTheme.WOOD.g, UiTheme.WOOD.b, 0.3)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _style_action_page(page: VBoxContainer) -> void:
	# A row with more buttons than fit becomes a grid of four columns, so no label is cut off.
	for child in page.get_children():
		if child is HBoxContainer and child.get_children().filter(func(n: Node) -> bool: return n is Button).size() > 4:
			var grid := GridContainer.new()
			grid.columns = 4
			grid.name = child.name
			var at: int = child.get_index()
			for inner in child.get_children():
				child.remove_child(inner)
				grid.add_child(inner)
			page.add_child(grid)
			page.move_child(grid, at)
			child.queue_free()
	for child in page.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Label:
			var label := child as Label
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 13)
			if label.text.length() < 70 and not label.text.contains("\n"):
				label.add_theme_color_override("font_color", UiTheme.HEADING)
		elif child is Button and not child is OptionButton:
			var button := child as Button
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_font_size_override("font_size", 13)
			button.custom_minimum_size.y = 34
		elif child is Container:
			for inner in child.find_children("*", "Control", true, false):
				if inner is Button:
					(inner as Button).add_theme_font_size_override("font_size", 12)
					(inner as Button).clip_text = true
					(inner as Button).custom_minimum_size.y = 30
				if inner.get_parent() == child and (inner is Button or inner is OptionButton):
					(inner as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if inner is Label and inner.get_parent() == child:
					(inner as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					(inner as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
					(inner as Label).custom_minimum_size.x = 120


func toggle_crafting() -> void:
	_craft_panel.visible = not _craft_panel.visible
	if _craft_panel.visible:
		_actions_panel.visible = false # The workshop takes the left side.
		_dock(_craft_panel, true)
	elif _inventory_panel.visible:
		_actions_panel.visible = true


func is_menu_open() -> bool:
	return _inventory_panel.visible or _craft_panel.visible or (_actions_panel != null and _actions_panel.visible) \
		or (_social_panel != null and _social_panel.visible)


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
	var my_group: int = int(client.you.get("party", {}).get("id", 0))
	match event["type"]:
		"story":
			if int(event.get("peer", -1)) == client.peer_id:
				banner("BEACON SEVEN / CHAPTER I", Color(0.85, 0.75, 0.42))
				say(str(event.get("line", "")))
		"story2":
			if int(event.get("peer", -1)) == client.peer_id:
				banner("CHAPTER II / THE DEEP SIGNAL", Color(0.5, 0.85, 0.96))
				say(str(event.get("line", "")))
		"story3":
			if int(event.get("peer", -1)) == client.peer_id:
				banner("CHAPTER III / THE MISSING CONVOY", Color(0.96, 0.72, 0.5))
				say(str(event.get("line", "")))
		# Territory and sieges: the server tells everyone, so the world hears when an outpost falls.
		"outpost_taken":
			if my_group > 0 and int(event.get("owner", 0)) == my_group:
				banner("OUTPOST CAPTURED", Color(0.45, 0.9, 0.5))
			else:
				say("An outpost has changed hands.")
		"outpost_lost":
			say("An outpost has fallen and stands unclaimed.")
		"outpost_breached":
			if my_group > 0 and int(event.get("by_group", 0)) != my_group:
				banner("YOUR OUTPOST IS BREACHED (level %d)" % int(event.get("level", 0)), Color(0.95, 0.4, 0.3))
		"outpost_fortified":
			if my_group > 0 and int(event.get("owner", 0)) == my_group:
				say("Outpost fortified to level %d." % int(event.get("level", 0)))
		"outpost_provisioned":
			if my_group > 0 and int(event.get("owner", 0)) == my_group:
				say("Outpost provisioned: +%d min of supplies." % int(float(event.get("extended", 0.0)) / 60.0))
		"siege_contract_declared":
			if my_group > 0 and int(event.get("defender", 0)) == my_group:
				banner("SIEGE DECLARED ON YOUR OUTPOST", Color(0.98, 0.55, 0.2))
			elif my_group > 0 and int(event.get("attacker", 0)) == my_group:
				banner("SIEGE DECLARED", Color(0.98, 0.75, 0.3))
			else:
				say("A siege has been declared somewhere on the island.")
		"siege_contract_result":
			var involved: bool = my_group > 0 and (int(event.get("attacker", 0)) == my_group or int(event.get("defender", 0)) == my_group)
			if involved:
				banner("SIEGE %s" % str(event.get("result", "over")).to_upper().replace("_", " "), Color(0.95, 0.78, 0.35))
		# Combat feedback that used to show only as numbers.
		"incident":
			var spot := Vector2(float(event.get("x", 0.0)), float(event.get("z", 0.0)))
			var me := Vector2(client.predicted.x, client.predicted.z)
			var offset: Vector2 = spot - me
			if offset.length() <= 160.0:
				var bearing: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(fposmod(atan2(offset.x, -offset.y), TAU) / (TAU / 8.0))) % 8]
				match str(event.get("kind", "")):
					"horde":
						banner("A HORDE IS MOVING IN — %s, %d m" % [bearing, int(offset.length())], Color(1.0, 0.5, 0.35))
					"cache":
						banner("SURVIVORS' CACHE SPOTTED — %s, %d m (guarded)" % [bearing, int(offset.length())], Color(0.95, 0.82, 0.4))
					"screamer":
						banner("A SCREAMER STALKS NEARBY — %s, %d m" % [bearing, int(offset.length())], Color(0.85, 0.65, 1.0))
		"bed_respawn":
			if int(event.get("peer", -1)) == client.peer_id:
				say("You wake up in your own bed.")
		"howl":
			var heard_from := Vector2(float(event.get("x", 0.0)), float(event.get("z", 0.0)))
			var me := Vector2(client.predicted.x, client.predicted.z)
			if me.distance_to(heard_from) <= float(event.get("radius", 40.0)) + 10.0:
				banner("A HOWL ECHOES — %d INFECTED STIR" % int(event.get("woken", 0)), Color(0.85, 0.65, 1.0))
		"eel_bite":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Something bit you in the dark water! (-%d)" % int(event.get("damage", 0.0)))
		"drowning":
			if int(event.get("peer", -1)) == client.peer_id:
				banner("OUT OF AIR — SURFACE!", Color(0.5, 0.8, 1.0))
		"restoration_pulse":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Restoration pulse: %d ally%s treated." % [int(event.get("count", 0)), "" if int(event.get("count", 0)) == 1 else "s"])
		"camp_alarm":
			banner("CAMP ALERT: %d INFECTED NEAR YOUR FIRE" % int(
				event.get("count", 0)), Color(1.0, 0.62, 0.25))
		"snare_triggered":
			say("A snare caught an infected.")
		"barricade_broken":
			say("A barricade was smashed.")
		"gathered":
			if int(event.get("peer", -1)) == client.peer_id and int(event.get("wedge_bonus", 0)) > 0:
				say("Reinforced extraction: +%d %s, loud pickaxe work attracts infected (42m)." % [
					int(event["wedge_bonus"]), str(event.get("item", "ore"))])
		"caravan_escort_paid":
			say("Convoy escort complete: +%d silver, Explorer XP and renown earned." % [
				int(event.get("silver", 0))])
		"caravan_defended":
			say("CARAVAN DEFENDED! All attackers defeated. Earn 15% extra silver on delivery.")
		"ruin_ambush_cleared":
			if int(event.get("peer", -1)) == client.peer_id:
				say("RUIN SECURED! All %d awakened infected defeated." % int(event.get("count", 0)))
			elif my_group > 0 and int(event.get("group", 0)) == my_group:
				say("RUIN SECURED! The group has cleared the infected ambush.")
		"ruin_ambush":
			if int(event.get("peer", -1)) == client.peer_id:
				say("RUIN AMBUSH! %d infected awakened by your T%d cache. Fight or retreat!" % [
					int(event.get("count", 0)), int(event.get("tier", 3))])
			elif my_group > 0 and int(event.get("group", 0)) == my_group:
				say("RUIN ALERT! A teammate woke %d infected. Regroup or fall back!" % [
					int(event.get("count", 0))])
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
		"medic_cover":
			if int(event.get("peer", -1)) == client.peer_id:
				say("MEDIC COVER: guardian #%d pulled %d infected off you!" % [
					int(event.get("by", -1)), int(event.get("count", 0))])
			elif int(event.get("by", -1)) == client.peer_id:
				say("MEDIC COVER: drew %d attacking infected from medic #%d." % [
					int(event.get("count", 0)), int(event.get("peer", -1))])
		"party_triage":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Triage care received: +%d HP, -%d bleeding." % [
					roundi(float(event.get("heal", 0.0))),
					roundi(float(event.get("bleeding_stopped", 0.0)))])
		"party_supply_request":
			if int(event.get("peer", -1)) != client.peer_id:
				say("%s needs %s (%d/100)! Meet at x%d z%d and use Aid / Share." % [
					str(event.get("name", "Party member")),
					str(event.get("need", "supplies")).to_upper(),
					int(event.get("level", 0)),
					roundi(float(event.get("x", 0.0))),
					roundi(float(event.get("z", 0.0)))])
		"party_aid":
			if int(event.get("peer", -1)) == client.peer_id:
				if float(event.get("food", 0.0)) > 0.0 or float(event.get("drink", 0.0)) > 0.0:
					say("Teammate shared supplies: +%d hunger, +%d thirst." % [
						roundi(float(event.get("food", 0.0))),
						roundi(float(event.get("drink", 0.0)))])
				elif float(event.get("food_poison_treated", 0.0)) > 0.0:
					say("Teammate treated food poisoning: -%d severity." % roundi(float(event.get("food_poison_treated", 0.0))))
				else:
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
		"party_flank":
			if int(event.get("peer", -1)) == client.peer_id:
				say("COORDINATED FLANK! +%d%% melee damage while your ally holds the infected." % int(event.get("bonus", 18)))
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
			say("SIEGE CHARGE X:%d Z:%d! %.0fs to detonation; wall owner can defuse within 3m." % [
				roundi(float(event.get("x", 0.0))),
				roundi(float(event.get("z", 0.0))),
				float(event.get("seconds", 4.0))])
		"siege_charge_disarmed":
			say("SIEGE DEFUSED! A defending survivor removed the live charge.")
		"siege_brace_placed":
			say("SIEGE BRACE: wall prepared for one blast (180 seconds).")
		"siege_brace_absorbed":
			say("SIEGE BRACE BROKE! %.0f raw blast damage absorbed." % float(
				event.get("raw_absorbed", 0.0)))
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
		"guardian_retribution":
			if int(event.get("peer", -1)) == client.peer_id:
				say("GUARDIAN COUNTERSTRIKE! +25% melee damage against the intercepted infected.")
		"party_shield_wall_block":
			if int(event.get("peer", -1)) == client.peer_id:
				say("SHIELD WALL: guardian #%d prevented %.1f infected melee damage to you!" % [
					int(event.get("by", -1)), float(event.get("prevented", 0.0))])
			elif int(event.get("by", -1)) == client.peer_id:
				say("SHIELD WALL: prevented %.1f infected damage to ally #%d." % [
					float(event.get("prevented", 0.0)), int(event.get("peer", -1))])
		"guardian_intercept":
			if int(event.get("by", -1)) == client.peer_id:
				if bool(event.get("counter_ready", false)):
					say("GUARDIAN INTERCEPT: saved ally #%d (%.1f damage). Counter ready for 4s: strike the same infected!" % [
						int(event.get("peer", -1)), float(event.get("damage", 0.0))])
				else:
					say("GUARDIAN INTERCEPT: shielded ally #%d (%.1f damage). No counter available." % [
						int(event.get("peer", -1)), float(event.get("damage", 0.0))])
			elif int(event.get("peer", -1)) == client.peer_id:
				say("GUARDIAN INTERCEPT: ally #%d took the infected hit for you!" % int(event.get("by", -1)))
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
			say("RAID PHASE %d: %d new infected! WARD: %d guards, boss resists %d%% damage." % [
				int(event.get("phase", 1)), int(event.get("count", 0)),
				int(event.get("guards", 0)), int(event.get("reduction_percent", 0))])
		"raid_ward_changed":
			var guards: int = int(event.get("guards", 0))
			if guards > 0:
				say("RAID WARD: %d guards remain. Boss resists %d%% damage." % [
					guards, int(event.get("reduction_percent", 0))])
			else:
				say("RAID WARD BROKEN! Boss now takes full damage.")
		"scavenging":
			if event.get("peer", -1) == client.peer_id:
				say("+%d scavenging XP (rank %d)" % [
					int(event.get("xp", 0)), int(event.get("level", 1))])
		"crate":
			say("You search the crate...")
		"rage":
			if int(event.get("peer", -1)) == client.peer_id:
				say("RAGE!" if bool(event.get("active", false)) else "Rage fades.")
		"masterwork":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Crafted %s!" % str(Defs.item(str(event.get("item", ""))).get("name", "")))
		"market_sale":
			if int(event.get("peer", -1)) == client.peer_id:
				say("Market: sold %dx %s, +%d silver." % [int(event.get("quantity", 0)), str(Defs.item(str(event.get("item", ""))).get("name", event.get("item", ""))), int(event.get("net", 0))])
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
	if kind == "alliance":
		if bool(data.get("ok", false)):
			var allies: Array = data.get("allied_guilds", [])
			var pending: String = str(data.get("invite_from", ""))
			say("Alliance: %s%s" % ["allied with " + ", ".join(allies) if not allies.is_empty() else "no alliance",
				(" | invite pending from %s" % pending) if pending != "" else ""])
		else:
			say("Alliance: %s" % {"no_guild": "join a guild first", "leaders_only": "only guild leaders manage alliances", "no_station": "visit the hub",
				"target_not_leader": "that survivor does not lead a guild", "target_allied": "their guild is already allied", "alliance_full": "alliances hold up to 4 guilds",
				"no_invite": "no pending invitation", "invalid_target": "choose a leader of another guild"}.get(str(data.get("reason", "")), str(data.get("reason", "rejected"))))
		return
	if kind == "guild_bank":
		if bool(data.get("ok", false)):
			var vault: Dictionary = data.get("vault", {})
			_guild_vault_select.clear()
			var ids: Array = vault.keys()
			ids.sort()
			for id in ids:
				_guild_vault_select.add_item("%s x%d" % [str(Defs.item(str(id)).get("name", id)), int(vault[id])])
				_guild_vault_select.set_item_metadata(_guild_vault_select.item_count - 1, str(id))
			var ledger: Array = data.get("ledger", [])
			var last: String = ""
			if not ledger.is_empty():
				var entry: Dictionary = ledger[-1]
				last = " Last: %s %s %dx %s." % [str(entry["who"]), str(entry["action"]), int(entry["count"]), str(Defs.item(str(entry["item"])).get("name", entry["item"]))]
			say("%s guild bank: %d item kinds.%s" % [str(data.get("guild", "")), vault.size(), last])
		else:
			say("Guild bank: %s" % {"no_guild": "join a guild first", "no_station": "visit the hub", "officers_only": "only the leader and officers can withdraw",
				"missing_items": "you do not carry that many", "not_in_vault": "not enough of that in the vault", "vault_full": "the vault is full", "no_space": "no backpack space"}.get(str(data.get("reason", "")), str(data.get("reason", "rejected"))))
		return
	if kind == "farm":
		if bool(data.get("ok", false)):
			if data.has("crop"):
				say("Planted %s: ripe in %d minutes." % [str(data["crop"]), int(float(data.get("seconds", 0.0)) / 60.0)])
			else:
				var got: Array = []
				var items: Dictionary = data.get("items", {})
				for id in items:
					got.append("%d %s" % [int(items[id]), str(Defs.item(str(id)).get("name", id))])
				say("Harvested %s." % ", ".join(got))
		else:
			say("Farming: %s" % {"green_zone_only": "plots only grow in the green zone", "missing_seed": "buy seeds from the hub trader",
				"too_many_plots": "you already tend %d plots" % Farming.MAX_PLOTS, "too_close": "too close to another plot", "water": "not in water",
				"not_ripe": "not ripe yet", "no_plot": "stand next to one of your plots"}.get(str(data.get("reason", "")), str(data.get("reason", "rejected"))))
		return
	if kind == "faction":
		if bool(data.get("ok", false)):
			var fname: String = str(Factions.FACTIONS.get(str(data.get("faction", "")), "no faction"))
			match str(data.get("action", "")):
				"enlist":
					say("You serve the %s." % fname)
				"flag":
					say("Faction flag raised: flagged rivals can now attack you outside safe towns.")
				"unflag":
					say("Lowering the faction flag in %.0fs." % float(data.get("unflag_in", 0.0)))
				"redeem":
					say("Faction rewards claimed. %d points left." % int(data.get("points", 0)))
		else:
			say("Faction: %s" % {"no_station": "visit the hub", "not_enlisted": "join a faction first", "flagged": "lower your flag first",
				"need_points": "not enough faction points (%d)" % int(data.get("points", 0)), "no_space": "free some backpack space"}.get(str(data.get("reason", "")), str(data.get("reason", "rejected"))))
		return
	if kind == "craft":
		match str(data.get("reason", "")):
			"focus_needs_city":
				say("Focus crafting works only at a safe settlement workbench.")
				return
			"need_focus":
				say("Not enough focus: %d needed, %d left (refills over a day)." % [int(data.get("cost", 0)), int(data.get("focus", 0))])
				return
		var back: Dictionary = data.get("returned", {})
		if bool(data.get("ok", false)) and not back.is_empty():
			var parts: Array = []
			for id in back:
				parts.append("%d %s" % [int(back[id]), str(Defs.item(str(id)).get("name", id))])
			say("Focus returned: %s." % ", ".join(parts))
	if (kind == "stash" or kind == "stash_bulk") and bool(data.get("ok", false)):
		FirstSteps.note_deposit()
	if kind == "door" and not bool(data.get("ok", false)):
		say({"locked": "The door is barred from inside — break it or ask the owner.", "blocked": "Something is in the doorway.",
			"too_far": "Too far from the door."}.get(str(data.get("reason", "")), "The door will not move."))
		return
	if kind == "arcane_bolt" or kind == "ultimate":
		var label: String = "Arcane Bolt" if kind == "arcane_bolt" else "Cataclysm"
		if bool(data.get("ok", false)):
			if kind == "ultimate":
				say("Cataclysm! %d infected caught in the blast." % int(data.get("hits", 0)))
		elif str(data.get("reason", "")) == "cooldown":
			say("%s ready in %.0fs." % [label, ceilf(float(data.get("remaining", 0.0)))])
		else:
			say("%s: %s." % [label, str(data.get("reason", "rejected")).replace("_", " ")])
		return
	if kind == "gear_skill":
		if bool(data.get("ok", false)):
			say("%s!" % str(data.get("skill", "")).replace("_", " ").capitalize())
		elif str(data.get("reason", "")) == "no_item":
			say("Equip a %s to use that ability." % {"armor": "chest piece", "head": "helmet", "feet": "pair of boots"}.get(str(data.get("slot", "")), "piece"))
		elif str(data.get("reason", "")) == "cooldown":
			say("Ability ready in %.0fs." % float(data.get("remaining", 0.0)))
		return
	if kind == "enchant":
		if bool(data.get("ok", false)):
			var made: String = str(data.get("item", ""))
			say("Enchanted: %s (item power %d)." % [str(Defs.item(made).get("name", made)), int(data.get("item_power", 0))])
		else:
			match str(data.get("reason", "")):
				"no_station":
					say("Enchant: stand at a workbench.")
				"need_materials":
					var parts: Array = []
					var cost: Dictionary = data.get("cost", {})
					for id in cost:
						parts.append("%d %s" % [int(cost[id]), str(Defs.item(str(id)).get("name", id))])
					say("Enchant needs: %s." % ", ".join(parts))
				"cannot_enchant":
					say("Enchant: already at .3 or not enchantable.")
				_:
					say("Enchant: %s" % str(data.get("reason", "rejected")))
		return
	if kind == "repair_gear":
		if bool(data.get("ok", false)):
			say("Repaired %d item(s) for %d silver." % [(data.get("items", []) as Array).size(), int(data.get("cost", 0))])
		else:
			match str(data.get("reason", "")):
				"no_station":
					say("Repair: stand at a workbench.")
				"nothing_to_repair":
					say("Repair: all your gear is at 100%.")
				"need_silver":
					say("Repair costs %d silver." % int(data.get("cost", 0)))
				_:
					say("Repair: %s" % str(data.get("reason", "rejected")))
		return
	if kind == "smart_provision":
		if bool(data.get("ok", false)):
			var item_id: String = str(data.get("item", ""))
			say("Survival supplies: used %s." % str(Defs.item(item_id).get("name", item_id)))
		elif str(data.get("reason", "")) == "no_provision":
			say("Survival supplies: no suitable safe ration or drink, or not needed yet.")
		else:
			say("Survival supplies: %s (no items spent)." % str(data.get("reason", "rejected")))
		return
	if kind == "use" and bool(data.get("trail_ration", false)):
		say("Smoked fish consumed. Trail ration T%d: hunger use reduced for %.0fs." % [
			int(data.get("tier", 1)), float(data.get("seconds", 0.0))])
		return
	if kind == "use" and bool(data.get("ate_raw_fish", false)):
		say("Raw fish eaten! Food poisoning %d/100. Cook catches for safety; use a herbal stomach remedy." % int(data.get("severity", 0)))
		return
	if kind == "use" and bool(data.get("stomach_remedy", false)):
		say("Stomach treatment applied. Food poisoning remaining: %d/100." % int(data.get("remaining", 0)))
		return
	if kind == "quick_medicine":
		if bool(data.get("ok", false)):
			var id: String = str(data.get("item", ""))
			say("Field treatment: used %s." % str(Defs.item(id).get("name", id)))
		elif str(data.get("reason", "")) == "no_treatment":
			say("Field treatment: no useful medicine carried for current wounds.")
		else:
			say("Field treatment: %s (nothing spent)." % str(data.get("reason", "rejected")))
		return
	if kind == "use" and bool(data.get("wound_seal", false)):
		if bool(data.get("ok", false)):
			say("Wound seal active: -45% infected bite infection for 90s (not acid or spores).")
		else:
			say("Wound seal: " + str(data.get("reason", "rejected")) + " (dose not spent)")
		return
	if kind == "use" and bool(data.get("ok", false)) and str(data.get("item", "")) == "murky_water":
		say("Collected unboiled lake water. Boil with 1 wood at a lit campfire or the hub workbench.")
		return
	if kind == "use" and bool(data.get("survey_signal", false)):
		if bool(data.get("ok", false)):
			say("Party mineral signal: T%d %s deposit shared for %.0fs. Allies can navigate there." % [
				int(data.get("tier", 2)), str(data.get("material", "ore")),
				float(data.get("seconds", 0.0))])
		else:
			say("Party mineral signal: %s (signal not spent)." % str(
				data.get("reason", "rejected")))
		return
	if kind == "corpse_rescue":
		if bool(data.get("ok", false)):
			say("RESCUE SIGNAL: lost backpack shared privately for %ds. Loot stays public." % [
				ceili(float(data.get("seconds", 0.0)))])
		else:
			say("Rescue signal: %s (no position shared)." % str(
				data.get("reason", "rejected")))
		return
	if kind == "use" and bool(data.get("mining_wedges", false)):
		if bool(data.get("ok", false)):
			say("Mining wedges fitted: %d T2+ ore/stone harvests grant +2 extra material. Noise 42m." % int(data.get("charges", 0)))
		else:
			say("Mining wedges: %s (kit not spent)." % str(data.get("reason", "rejected")))
		return
	if kind == "use" and bool(data.get("tarp_anchor", false)):
		if bool(data.get("ok", false)):
			say("Storm tarp anchored: %.0fs of shelter remain; exposure reduction 90%%." % float(data.get("remaining", 0.0)))
		else:
			say("Tarp anchors: " + str(data.get("reason", "rejected")) + " (kit not spent)")
		return
	if kind == "use" and bool(data.get("siege_brace", false)):
		if bool(data.get("ok", false)):
			say("Siege brace fitted: 55%% of next blast absorbed for up to %ds." % int(
				data.get("seconds", 0)))
		else:
			say("Siege brace: %s (no kit spent)." % str(data.get("reason", "rejected")))
		return
	if kind == "use" and bool(data.get("defusal", false)):
		if bool(data.get("ok", false)):
			say("Siege defusal successful; one toolkit spent, wall safe.")
		else:
			say("Defusal: %s (kit not spent)." % str(data.get("reason", "rejected")))
		return
	if kind == "craft_stash":
		if bool(data.get("ok", false)):
			var made_id: String = str(data.get("recipe", ""))
			var recipe: Dictionary = Defs.recipes().get(made_id, {})
			say("Crafted from bank: %d × %s, materials debited safely." % [
				int(data.get("times", 1)) * int(recipe.get("count", 1)),
				str(Defs.item(str(recipe.get("output", ""))).get("name", made_id))])
		else:
			var errors := {
				"dead": "unavailable while dead",
				"mounted": "dismount first",
				"recall_channeling": "finish recall first",
				"no_station": "only at the hub workbench",
				"unknown_recipe": "unknown recipe",
				"need_skill": "crafting level too low",
				"missing_inputs": "materials missing from both containers",
				"no_space": "backpack has no room for the finished items",
			}
			say("Craft from bank: %s" % str(errors.get(
				str(data.get("reason", "")), "rejected")))
		return
	if kind == "equipment_preset":
		if bool(data.get("ok", false)):
			say("Gear set %d: %s." % [
				int(data.get("slot", 0)) + 1, str(data.get("action", "updated"))])
		else:
			say("Gear set: " + str(data.get("reason", "unavailable")))
		return
	if kind == "use" and bool(data.get("prospecting", false)):
		if bool(data.get("ok", false)):
			say("Prospecting: T%d %s at X:%d Z:%d — private 80s marker." % [
				int(data.get("tier", 2)), str(data.get("kind", "rock")),
				roundi(float(data.get("x", 0.0))),
				roundi(float(data.get("z", 0.0)))])
		else:
			say("Prospecting: %s (chart not spent)." % str(
				data.get("reason", "rejected")))
		return
	if kind == "use" and bool(data.get("threat_scan", false)):
		if bool(data.get("ok", false)):
			var audience := "shared with your current party" if bool(data.get("party_shared", false)) else "private"
			say("SCOUT: %s threat at X:%d Z:%d — %s moving marker for %ds." % [
				str(data.get("kind", "elite")).to_upper(),
				roundi(float(data.get("x", 0.0))),
				roundi(float(data.get("z", 0.0))),
				audience, int(data.get("seconds", 50))])
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
	if kind == "use" and bool(data.get("bike_lamp", false)):
		if bool(data.get("ok", false)):
			say("Dynamo lamp %s. The beam attracts infected when riding at night." % (
				"armed" if bool(data.get("bike_lamp_enabled", false)) else "switched off"))
		else:
			say("Dynamo lamp: " + str(data.get("reason", "rejected")) + " (no item spent)")
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
					say("NEW CARAVAN: deliver %dx %s to %s (X:%d Z:%d) for %d silver; +20%% for verified night travel." % [
						int(route.get("quantity", 0)), str(route.get("cargo", "")),
						str(route.get("destination", "")), roundi(float(route.get("dst_x", 0.0))),
						roundi(float(route.get("dst_z", 0.0))), int(route.get("silver", 0))])
				"deliver":
					var shares: Array = data.get("escorts", [])
					var bonus: int = int(data.get("defense_bonus", 0))
					var night_bonus: int = int(data.get("night_bonus", 0))
					if shares.is_empty():
						say("Caravan delivered: +%d silver (defense +%d, night +%d), Explorer XP." % [
							int(data.get("silver", 0)), bonus, night_bonus])
					else:
						say("Caravan delivered: +%d silver (defense +%d, night +%d), paid %d escort(s) from base fare." % [
							int(data.get("silver", 0)), bonus, night_bonus, shares.size()])
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
	if kind == "party_shield_wall":
		if bool(data.get("ok", false)):
			say("SHIELD WALL active for %.0fs; protecting %d nearby allies." % [
				float(data.get("seconds", 0.0)), int(data.get("allies", 0))])
		else:
			say("Shield Wall: " + str(data.get("reason", "rejected")))
		return
	if kind == "guardian_intercept":
		if bool(data.get("ok", false)):
			say("GUARD LINK: ally #%d guarded for %.0fs, next melee hit only." % [
				int(data.get("target", 0)), float(data.get("seconds", 0.0))])
		else:
			say("Guardian intercept: " + str(data.get("reason", "rejected")))
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
	if kind == "medic_cover":
		if bool(data.get("ok", false)):
			say("Medic Cover: %d engaged infected redirected to guardian #%d." % [
				int(data.get("count", 0)), int(data.get("guardian", -1))])
		else:
			say("Medic Cover denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_triage":
		if bool(data.get("ok", false)):
			say("Triage: treated %d allies (+%d HP total, -%d bleeding)." % [
				int(data.get("treated", 0)), roundi(float(data.get("heal", 0.0))),
				roundi(float(data.get("bleeding_stopped", 0.0)))])
		else:
			say("Triage denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_supply_request":
		if bool(data.get("ok", false)):
			say("Party request sent: need %s (%d/100). Next signal in %ds." % [
				str(data.get("need", "")), int(data.get("level", 0)),
				int(data.get("seconds", 30))])
		else:
			say("Party request denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "party_aid":
		if bool(data.get("ok", false)):
			if data.has("wound_seal_seconds"):
				say("Expedition ready: ally #%d sealed for %.0fs (-45%% infected bite infection)." % [
					int(data.get("peer", 0)), float(data["wound_seal_seconds"])])
			elif float(data.get("food", 0.0)) > 0.0 or float(data.get("drink", 0.0)) > 0.0:
				say("Supplies shared: +%d hunger, +%d thirst." % [
					roundi(float(data.get("food", 0.0))),
					roundi(float(data.get("drink", 0.0)))])
			elif float(data.get("food_poison_treated", 0.0)) > 0.0:
				say("Field aid: treated ally food poisoning (-%d severity)." % roundi(float(data.get("food_poison_treated", 0.0))))
			else:
				say("Field aid: +%d HP, -%d infection, -%d bleeding." % [
					roundi(float(data.get("heal", 0.0))),
					roundi(float(data.get("cure", 0.0))),
					roundi(float(data.get("bleeding_stopped", 0.0)))])
		else:
			say("Field aid / share denied: " + str(data.get("reason", "rejected")))
		return
	if kind == "loot_sweep":
		if bool(data.get("ok", false)):
			say("PICKUP: %d items from %d PvE bags (%d emptied)." % [
				int(data.get("items", 0)), int(data.get("bags", 0)), int(data.get("emptied", 0))])
		else:
			say("Nearby pickup: %s." % str(data.get("reason", "rejected")))
		return
	if kind == "loot" and str(data.get("reason", "")) == "dive_to_reach":
		say("The cache lies on the bottom. Hold crouch to dive down to it.")
		return
	if kind == "loot" and bool(data.get("sunken", false)) and bool(data.get("ok", false)):
		say("You pry open the sunken cache.")
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
	if kind == "party_provision":
		if bool(data.get("ok", false)):
			say("Camp supplies delivered: %s (5s shared support cooldown)." % str(data.get("items", {})))
		else:
			var reasons := {
				"not_in_party": "Select a current party member.",
				"too_far": "Move within 3.2m of your teammate.",
				"no_fire": "Both teammates need the same burning campfire.",
				"missing_supplies": "Required food or water is not in your backpack.",
				"no_space": "Teammate's backpack has no room.",
				"cooldown": "Wait for your shared party aid timer.",
				"in_combat": "Finish combat before resupplying.",
			}
			say("Camp supplies: " + str(reasons.get(
				str(data.get("reason", "")), str(data.get("reason", "rejected")))))
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
	if kind == "camp_alarm_arm":
		if bool(data.get("ok", false)):
			say("Camp sentry armed for %d seconds; detects infected within %dm." % [
				int(data.get("seconds", 0)), int(data.get("radius", 21))])
		else:
			say("Camp alarm: " + str(data.get("reason", "rejected")) + " (kit not spent).")
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
		if bool(data.get("hooked", false)):
			say("Fishing: hooked! A bigger catch is coming in.")
			return
		if str(data.get("reason", "")) in ["no_bite", "already_struck"]:
			say("Fishing: %s" % ("too early or too late, the fish slipped away" if str(data["reason"]) == "no_bite" else "you already struck"))
			return
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
			_market_bids = data.get("bids", [])
			if int(data.get("collected_silver", 0)) > 0 or int(data.get("collected_items", 0)) > 0:
				say("Market: collected %d silver and %d returned items." % [int(data.get("collected_silver", 0)), int(data.get("collected_items", 0))])
			if int(data.get("pending_silver", 0)) > 0:
				say("Market: %d silver waits for backpack space." % int(data.get("pending_silver", 0)))
			_refresh_market_options()
		elif str(data.get("action", "")) == "filled":
			say("Market: sold %dx %s into a buy order for %d silver (tax %d)." % [int(data.get("quantity", 0)), str(data.get("item", "")), int(data.get("total", 0)), int(data.get("tax", 0))])
			client.market_list()
		elif str(data.get("action", "")) == "bid_created":
			say("Market: buy order placed, %d silver held in escrow." % int(data.get("escrowed", 0)))
			client.market_list()
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
	if kind == "story":
		if bool(data.get("ok", false)):
			say(str(data.get("line", StoryCampaign.TITLE)))
			say("Next objective: " + str(data.get("objective", "")))
		else:
			say("Beacon Seven: " + str(data.get("reason", "transmission rejected")))
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
	if kind == "expedition_restock":
		if bool(data.get("ok", false)):
			var entries: Array[String] = []
			for item_id in data.get("moved", {}):
				entries.append("%s x%d" % [
					str(Defs.item(str(item_id)).get("name", item_id)),
					int(data["moved"][item_id])])
			say("Restocked %s: %s%s" % [
				ExpeditionLoadout.title(str(data.get("preset", ""))),
				", ".join(entries),
				" (partial; more supplies needed)" if bool(data.get("partial", false)) else ""])
		else:
			var reasons := {
				"dead": "Restock: unavailable while dead.",
				"no_station": "Restock: return to the hub workbench.",
				"unknown_preset": "Restock: unknown kit.",
				"already_supplied": "Restock: already carrying the kit targets.",
				"no_stock": "Restock: required supplies are not in stash.",
				"no_space": "Restock: backpack slots are full.",
				"transaction_failed": "Restock: cancelled without moving items.",
			}
			say(str(reasons.get(str(data.get("reason", "")), "Restock rejected.")))
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
			var night: Dictionary = client.you.get("caravan_night", {})
			if not night.is_empty():
				_caravan_status.text += " | NIGHT %d/%dm" % [
					int(night.get("night_meters", 0)), int(night.get("required_meters", 0))]
				if bool(night.get("qualified", false)):
					_caravan_status.text += " (+%d silver earned)" % int(night.get("bonus_silver", 0))
				else:
					_caravan_status.text += " (+%d silver if completed)" % int(night.get("potential_bonus", 0))
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
	if not world_streaming_notice.is_empty():
		_info_label.text += "\n" + world_streaming_notice
	var combat_stress: float = float(client.you.get("combat_stress", 0.0))
	if combat_stress >= CombatStress.HUD_THRESHOLD:
		_info_label.text += "\nINFECTED PRESSURE: %d/100 | passive stamina recovery -%d%%. Regroup or find shelter." % [
			roundi(combat_stress),
			roundi(100.0 * (1.0 - float(client.you.get("combat_stress_regen", 1.0))))]
	var flank_hint: Dictionary = client.you.get("party_flank_hint", {})
	if not flank_hint.is_empty():
		_info_label.text += "\nFLANK OPEN: infected #%d (+%d%% basic melee) — stay behind while ally tanks" % [
			int(flank_hint.get("zombie", -1)), int(flank_hint.get("bonus", 18))]
	var wall_active: float = float(client.you.get("shield_wall_seconds", 0.0))
	var wall_cooldown: float = float(client.you.get("shield_wall_cooldown", 0.0))
	if wall_active > 0.0:
		_info_label.text += "\nSHIELD WALL: %.1fs (allies -22%% infected claw, raid -12%%)" % wall_active
	elif wall_cooldown > 0.0:
		_info_label.text += "\nShield Wall ready in %.0fs" % wall_cooldown
	var guarded_for: float = float(client.you.get("shield_wall_guarded_seconds", 0.0))
	if guarded_for > 0.0:
		_info_label.text += "\nSHIELDED by guardian #%d: %.1fs (PvE melee only)" % [
			int(client.you.get("shield_wall_guarded_by", -1)), guarded_for]
	var cover_cooldown: float = float(client.you.get("medic_cover_cooldown", 0.0))
	if cover_cooldown > 0.0:
		_info_label.text += "\nMedic Cover ready in %.0fs (staff + guardian)" % cover_cooldown
	var intercept_active: float = float(client.you.get("guardian_intercept_seconds", 0.0))
	var intercept_cooldown: float = float(client.you.get("guardian_intercept_cooldown", 0.0))
	if intercept_active > 0.0:
		_info_label.text += "\nGUARD LINK to ally #%d: %.1fs (next infected melee hit)" % [
			int(client.you.get("guardian_intercept_target", -1)), intercept_active]
	elif intercept_cooldown > 0.0:
		_info_label.text += "\nGuard link ready in %.0fs" % intercept_cooldown
	var counter_window: float = float(client.you.get("guardian_counter_seconds", 0.0))
	if counter_window > 0.0:
		_info_label.text += "\nGUARD COUNTER READY: %.1fs — melee strike enemy #%d (+25%%)" % [
			counter_window, int(client.you.get("guardian_counter_target", -1))]
	var protected_for: float = float(client.you.get("guardian_guarded_seconds", 0.0))
	if protected_for > 0.0:
		_info_label.text += "\nPROTECTED by guardian #%d for %.1fs" % [
			int(client.you.get("guardian_guarded_by", -1)), protected_for]
	if float(client.you.get("trail_pack_kg", 0.0)) > 0.0:
		_info_label.text += "\nTRAIL PACK: 14 kg on-foot support (full-loot; no extra slots)"
	if float(client.you.get("cargo_factor", 1.0)) < 0.9999 and \
			not bool(client.you.get("mounted", false)):
		_info_label.text += "\nHEAVY CARGO: footsteps draw infected attention; crouch to stay quieter."
	var dropped: Dictionary = client.you.get("death_recovery", {})
	if not dropped.is_empty():
		var destination := TravelNavigation.target(dropped, "x", "z")
		var here := TravelNavigation.target(client.you, "x", "z")
		var distance: int = TravelNavigation.distance_meters(here, destination)
		if distance >= 0:
			_info_label.text += "\nLOST BACKPACK: %dm %s | %.0fs until public loot expires (open map to track)" % [
				distance, TravelNavigation.compass(here, destination),
				float(dropped.get("remaining", 0.0))]
	var mud_traction: float = float(client.you.get("storm_mud_factor", 1.0))
	if mud_traction < 0.999:
		_info_label.text += "\nSTORM MUD: ground travel -%.0f%% | roads reduce the penalty." % [
			(1.0 - mud_traction) * 100.0]
	if int(client.you.get("rested_xp_credit", 0)) > 0:
		_info_label.text += "\nRESTED TRAINING: %d bonus XP left (+50-95%% by skill and practice)" % int(
			client.you["rested_xp_credit"])
	var practice_branches: int = int(client.you.get("practice_branches", 0))
	if practice_branches > 0:
		_info_label.text += "\nCROSS-TRAINING: %d/3 branches in 3 min (+20%% rested XP rate when active)" % mini(
			practice_branches, 3)
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
			var ward_guards: int = int(enemy.get("raid_ward_guards", 0))
			if ward_guards > 0:
				_info_label.text += "\nRAID WARD: %d guards | -%d%% boss damage. Defeat adds!" % [
					ward_guards, int(enemy.get("raid_ward_reduction", 0))]
			var recovery: float = float(enemy.get("raid_exposed_seconds", 0.0))
			if recovery > 0.0:
				_info_label.text += "\nRAID BOSS EXPOSED: %.1fs (+15%% PvE damage)" % recovery
			break
	# Group-only raid boss threat view comes from the authoritative private snapshot.
	# Never derive another player's hidden hate values from public enemy positions.
	var raid_aggro: Dictionary = client.you.get("raid_aggro", {})
	if not raid_aggro.is_empty():
		var target_id: int = int(raid_aggro.get("target", 0))
		var target_name: String = "unknown / other group"
		if target_id == client.peer_id:
			target_name = "YOU"
		elif target_id > 0:
			target_name = "#%d" % target_id
			for ally in client.you.get("party", {}).get("roster", []):
				if int(ally.get("id", 0)) == target_id:
					target_name = str(ally.get("name", target_name))
					break
		var own_percent: int = int(raid_aggro.get("your_pct", 0))
		_info_label.text += "\nRAID AGGRO: boss targets %s | your threat %d%% of party peak" % [
			target_name, own_percent]
		var pull_percent: int = int(raid_aggro.get("pull_pct", -1))
		if target_id != client.peer_id and pull_percent >= 0:
			_info_label.text += " | %d%% of aggro-switch threshold" % pull_percent
			if pull_percent >= 85:
				_info_label.text += " — ease damage or let guardian hold!"
		if bool(raid_aggro.get("taunted", false)):
			_info_label.text += " | GUARDIAN TAUNT %.1fs" % float(raid_aggro.get("taunt_seconds", 0.0))
	var wedge_left: int = int(client.you.get("mining_wedge_charges", 0))
	if wedge_left > 0:
		_info_label.text += "\nMINING WEDGES: %d T2+ vein bonuses left (+2 ore/stone, noise 42m)" % wedge_left
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
	var seal_left: float = float(client.you.get("wound_seal_seconds", 0.0))
	if seal_left > 0.0:
		_info_label.text += "\nWOUND SEAL: %.0fs remaining (-45%% bite infection only)" % seal_left
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
		if client.inventory.count("bike_dynamo_lamp") > 0:
			_info_label.text += "\nDYNAMO LAMP: %s | [ toggle; lit bike attracts infected" % (
				"ON (visible)" if bool(client.you.get("bike_lamp_lit", false)) else (
				"ARMED (daylight/on foot)" if bool(client.you.get("bike_lamp_enabled", true)) else "MANUAL OFF"))
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
	if bool(client.you.get("tent_anchored", false)):
		_info_label.text += "\nANCHORED TARP: -90% weather exposure, shared camp cover"
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
	var wade: float = float(client.you.get("wading_depth_m", 0.0))
	if wade > 0.0:
		_info_label.text += "\nWADING: %.1f m deep | slowed travel; water above 0.25 m blocks sprint" % wade
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
	var story_data: Dictionary = client.you.get("story",
		StoryCampaign.public_state(StoryCampaign.empty_state()))
	if not story_data.is_empty():
		var chapter_objective: String = str(story_data.get("objective", ""))
		_contract_label.text += "\nSTORY: " + chapter_objective
		if _story_journal != null:
			var transcript_text: String = str(story_data.get("title", StoryCampaign.TITLE)) \
				+ "\nOBJECTIVE: " + chapter_objective
			for recovered_line in story_data.get("transcript", []):
				transcript_text += "\n\n" + str(recovered_line)
			if _story_journal.text != transcript_text:
				_story_journal.text = transcript_text
	var followup: Dictionary = client.you.get("story2", {})
	if not followup.is_empty():
		var followup_objective: String = str(followup.get("objective", ""))
		_contract_label.text += "\nCHAPTER II: " + followup_objective
		if _story2_journal != null:
			var chapter_two_text: String = str(followup.get("title", StoryChapterTwo.TITLE)) \
				+ "\nOBJECTIVE: " + followup_objective
			for entry in followup.get("transcript", []):
				chapter_two_text += "\n\n" + str(entry)
			if _story2_journal.text != chapter_two_text:
				_story2_journal.text = chapter_two_text
	var convoy_story: Dictionary = client.you.get("story3", {})
	if not convoy_story.is_empty():
		var convoy_objective: String = str(convoy_story.get("objective", ""))
		_contract_label.text += "\nCHAPTER III: " + convoy_objective
		if _story3_journal != null:
			var convoy_text: String = str(convoy_story.get("title", StoryChapterThree.TITLE)) \
				+ "\nOBJECTIVE: " + convoy_objective
			for entry in convoy_story.get("transcript", []):
				convoy_text += "\n\n" + str(entry)
			if _story3_journal.text != convoy_text:
				_story3_journal.text = convoy_text
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
	var ration_left: float = float(client.you.get("ration_seconds", 0.0))
	var ration_tier: int = int(client.you.get("ration_tier", 0))
	if ration_left > 0.0 and ration_tier > 0:
		_equipped.text += "\nTrail ration T%d: %.0fs | %.0f%% less hunger drain" % [
			ration_tier, ration_left, TrailRation.hunger_savings(ration_tier) * 100.0]
	_refresh_left_column()
	_party_frames.text = PartyFrames.describe(client.you.get("party", {}), client.peer_id)
	_party_frames.visible = not _party_frames.text.is_empty()
	_death.visible = not bool(client.you.get("alive", true))
	_death.text = "YOU DIED\n%s" % (
		"All carried items dropped. Track your LOST BACKPACK on the map after respawning."
		if bool(client.you.get("last_death_full_loot", false))
		else "Carried equipment retained.")
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
	if _bid_select != null:
		_bid_select.clear()
		for bid in _market_bids:
			var bid_item: String = str(bid["item"])
			_bid_select.add_item("WANTED %s x%d | %d silver/item | %s%s" % [str(Defs.item(bid_item).get("name", bid_item)),
				int(bid["quantity"]), int(bid["price"]), str(bid.get("buyer_name", "?")), " (yours)" if bool(bid.get("own", false)) else ""])
			_bid_select.set_item_metadata(_bid_select.item_count - 1, int(bid["id"]))


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


const QUALITY_COLORS := [Color.WHITE, Color.WHITE, Color(0.75, 0.85, 1.0), Color(0.55, 0.9, 0.55), Color(0.8, 0.55, 1.0), Color(1.0, 0.8, 0.3)]
const TIER_COLORS := [Color(0.62, 0.64, 0.68), Color(0.62, 0.64, 0.68), Color(0.36, 0.82, 0.42), Color(0.36, 0.62, 1.0), Color(0.78, 0.42, 1.0),
	Color(1.0, 0.78, 0.25), Color(1.0, 0.52, 0.22), Color(0.95, 0.28, 0.28), Color(0.96, 0.96, 0.98)]


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


## An inventory slot card: a tile coloured by what the item is for (weapons red, armor blue, food green, ...) with a frame in
## the tier colour, gold when equipped; an empty slot is a pale socket in the parchment.
func _style_slot(button: Button, item_id: String, equipped: bool) -> void:
	var tier: int = clampi(Defs.tier_of(item_id), 0, TIER_COLORS.size() - 1) if item_id != "" else 0
	var kind: String = str(Defs.item(item_id).get("kind", "")) if item_id != "" else ""
	var tile: Color = _kind_tile(kind)
	var edge: Color = UiTheme.GOLD if equipped else (TIER_COLORS[tier].darkened(0.15) if item_id != "" else Color(0.62, 0.52, 0.38))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.anti_aliasing = true
		style.bg_color = tile if item_id != "" else Color(0.82, 0.74, 0.6)
		if state == "hover":
			style.bg_color = tile.lightened(0.15)
		elif state == "pressed":
			style.bg_color = tile.darkened(0.2)
		style.set_corner_radius_all(9)
		style.set_border_width_all(3 if (equipped or state == "hover") else 2)
		style.border_color = edge if state != "hover" else edge.lightened(0.25)
		style.set_content_margin_all(2)
		if item_id != "":
			style.shadow_color = Color(0.2, 0.12, 0.05, 0.35)
			style.shadow_size = 3
			style.shadow_offset = Vector2(0, 2)
		button.add_theme_stylebox_override(state, style)


## The tile colour of an item slot.
static func _kind_tile(kind: String) -> Color:
	match kind:
		"weapon", "ammo":
			return Color(0.56, 0.2, 0.16)
		"armor", "armor_plate", "carry_pack", "siege_brace", "head", "cape", "hands", "feet":
			return Color(0.22, 0.32, 0.5)
		"medical", "party_medical", "stimulant":
			return Color(0.6, 0.26, 0.32)
		"food", "drink":
			return Color(0.3, 0.46, 0.22)
		"resource", "material":
			return Color(0.5, 0.38, 0.24)
		"currency":
			return Color(0.42, 0.42, 0.46)
		"tool":
			return Color(0.36, 0.38, 0.32)
	return Color(0.38, 0.3, 0.46)


func _refresh_presets() -> void:
	var presets: Array = client.you.get("equipment_presets", [])
	for slot in _preset_labels.size():
		var name_label: Label = _preset_labels[slot]
		if slot >= presets.size() or not (presets[slot] is Dictionary) or \
				(presets[slot] as Dictionary).is_empty():
			name_label.text = "Set %d: empty" % (slot + 1)
			continue
		var record: Dictionary = presets[slot]
		var weapon: String = str(record.get("weapon", ""))
		var armor: String = str(record.get("armor", ""))
		var weapon_name: String = str(Defs.item(weapon).get("name", "Unarmed"))
		var armor_name: String = str(Defs.item(armor).get("name", "No armor"))
		var active: bool = weapon == client.inventory.weapon and armor == client.inventory.armor
		name_label.text = "Set %d: %s / %s%s" % [
			slot + 1, weapon_name, armor_name, " [ACTIVE]" if active else ""]


func _refresh_inventory() -> void:
	_refresh_presets()
	var signature := str(client.inventory.to_dict()) + "|" + str(client.stash.to_dict()) + str(_bag_filter) + str(_quick_slots)
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
	var used := 0
	var showing_all: bool = _filter_all(_bag_filter)
	for slot in client.inventory.slots:
		if slot.is_empty():
			if showing_all: # A filtered view lists only the matching items.
				_inventory_grid.add_child(_item_card("", 0, false, Vector2(64, 64)))
			continue
		used += 1
		var item_id: String = slot["id"]
		if not bool(_bag_filter.get(_item_category(item_id), true)):
			continue
		var equipped: bool = client.inventory.is_equipped(item_id)
		var info: Dictionary = Defs.item(item_id)
		var card := _item_card(item_id, int(slot["count"]), equipped, Vector2(64, 64))
		var durability: float = client.inventory.durability(item_id) if client.inventory.has_method("durability") else 100.0
		var power: int = Defs.item_power(item_id)
		card.tooltip_text = ("Item power %d\n" % power if power > 0 and str(info.get("kind", "")) in Defs.ENCHANT_KINDS else "") + "%s\n%s  ·  Tier %d%s%s\n\nDouble click or drag to a lit slot: equip\nRight click: put one in the stash" % [
			str(info.get("name", item_id)), str(info.get("kind", "item")).capitalize().replace("_", " "), maxi(1, Defs.tier_of(item_id)),
			"\nEQUIPPED" if equipped else "",
			("\nDurability %d%%%s" % [int(round(durability)), "  BROKEN - repair at a workbench" if durability <= 0.0 else ""]) if durability < 100.0 else ""]
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				client.move_stash(item_id, 1, true)
			elif event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
				_put_in_doll(item_id))
		card.set_drag_forwarding(func(_at: Vector2) -> Variant: return _drag_item(item_id), Callable(), Callable())
		_inventory_grid.add_child(card)
	for child in _stash_grid.get_children():
		child.queue_free()
	var stashed := 0
	for slot in client.stash.slots:
		if slot.is_empty():
			continue
		stashed += 1
		var item_id: String = slot["id"]
		if not bool(_bag_filter.get(_item_category(item_id), true)):
			continue
		var card := _item_card(item_id, int(slot["count"]), false, Vector2(54, 54))
		card.tooltip_text = "%s  x%d\nClick: take one out (at a workbench)" % [Defs.item(item_id).get("name", item_id), int(slot["count"])]
		card.pressed.connect(func() -> void: client.move_stash(item_id, 1, false))
		_stash_grid.add_child(card)
	if stashed == 0:
		var empty := Label.new()
		empty.text = "Empty. Bank resources here at a workbench."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		_stash_grid.add_child(empty)
	_refresh_equipment()
	if _inventory_summary != null:
		_inventory_summary.text = "%d / %d slots   ·   stash %d / %d   ·   %d silver" % [
			used, client.inventory.slots.size(), stashed, client.stash.slots.size(), client.inventory.count("silver")]


## A square item card: the item's silhouette tinted by its use, the tier as a small badge, the count in the corner and a
## frame in the tier colour (gold when equipped). An empty card is a dim socket.
func _item_card(item_id: String, count: int, equipped: bool, size: Vector2) -> Button:
	var card := Button.new()
	card.custom_minimum_size = size
	card.focus_mode = Control.FOCUS_NONE
	_style_slot(card, item_id, equipped)
	if item_id.is_empty():
		card.disabled = true
		return card
	var inset: float = size.x * 0.14
	for layer in 2: # A soft dark copy under the white silhouette lifts it off the coloured tile.
		var art := TextureRect.new()
		art.texture = ItemIcons.icon(item_id)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = Color(0.08, 0.04, 0.02, 0.55) if layer == 0 else Color(1.0, 0.98, 0.94)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		var shift: float = 2.0 if layer == 0 else 0.0
		art.offset_left = inset + shift
		art.offset_top = inset + shift
		art.offset_right = -inset + shift
		art.offset_bottom = -inset + shift
		card.add_child(art)
	var tier: int = Defs.tier_of(item_id)
	if tier >= 1 and item_id.rfind("_") > 0 and item_id.substr(item_id.rfind("_") + 1).is_valid_int():
		card.add_child(_card_badge(["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"][clampi(tier, 0, 8)], TIER_COLORS[clampi(tier, 0, TIER_COLORS.size() - 1)], Control.PRESET_TOP_LEFT))
	if count > 1:
		card.add_child(_card_badge(_short_count(count), Color(1, 1, 1), Control.PRESET_BOTTOM_RIGHT))
	if Defs.quality_of(item_id) > 1:
		card.add_child(_card_badge("★".repeat(Defs.quality_of(item_id) - 1), QUALITY_COLORS[Defs.quality_of(item_id)], Control.PRESET_BOTTOM_LEFT))
	if equipped:
		card.add_child(_card_badge("E", UiTheme.GOLD, Control.PRESET_TOP_RIGHT))
	return card


func _card_badge(text: String, color: Color, corner: int) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", color)
	badge.add_theme_constant_override("outline_size", 0)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.12, 0.08, 0.05, 0.85)
	pill.set_corner_radius_all(8)
	pill.content_margin_left = 4
	pill.content_margin_right = 4
	pill.content_margin_top = 0
	pill.content_margin_bottom = 0
	badge.add_theme_stylebox_override("normal", pill)
	badge.custom_minimum_size = Vector2(16, 15)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE, 3)
	return badge


# The equipment sockets of the paper doll: [role, caption, ghost icon item].
const DOLL_SLOTS := [["bag", "Bag", "trail_backpack"], ["head", "Head", "hood_1"], ["cape", "Cape", "cloak_1"],
	["weapon", "Weapon", "club"], ["armor", "Armor", "jacket"], ["hands", "Hands", "gloves_1"],
	["food", "Food", "canned_food"], ["feet", "Feet", "boots_1"], ["potion", "Potion", "bandage"],
	["", "", ""], ["mount", "Mount", "salvage_bike"], ["", "", ""]]


## Which doll socket an item belongs in ("" for none): weapons and armor are worn, a carry pack and a bike count while
## carried, food and medicine go in the two quick-use sockets.
static func _doll_role(item_id: String) -> String:
	match str(Defs.item(item_id).get("kind", "")):
		"weapon":
			return "weapon"
		"armor":
			return "armor"
		"head", "cape", "hands", "feet":
			return str(Defs.item(item_id).get("kind", ""))
		"carry_pack":
			return "bag"
		"mount":
			return "mount"
		"food", "drink":
			return "food"
		"medical", "party_medical", "stimulant":
			return "potion"
	return ""


## What fills a socket now.
func _doll_item(role: String) -> String:
	match role:
		"weapon":
			return client.inventory.weapon
		"armor":
			return client.inventory.armor
		"head", "cape", "hands", "feet":
			var worn: String = str(client.inventory.gear.get(role, ""))
			return worn if client.inventory.count(worn) > 0 else ""
		"food", "potion":
			var picked: String = str(_quick_slots[role])
			return picked if picked != "" and client.inventory.count(picked) > 0 else ""
	for slot in client.inventory.slots:
		if not slot.is_empty() and _doll_role(str(slot["id"])) == role:
			return str(slot["id"])
	return ""


func _refresh_equipment() -> void:
	if _doll == null:
		return
	for child in _doll.get_children():
		child.queue_free()
	for entry in DOLL_SLOTS:
		var role: String = entry[0]
		if role == "":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(62, 62)
			_doll.add_child(gap)
			continue
		var item_id: String = _doll_item(role)
		var count: int = client.inventory.count(item_id) if role in ["food", "potion"] and item_id != "" else 0
		var card := _item_card(item_id, count, false, Vector2(62, 62))
		card.disabled = false
		if item_id == "":
			# An empty socket shows a faint outline of what goes there.
			var ghost := TextureRect.new()
			ghost.texture = ItemIcons.icon(str(entry[2]))
			ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ghost.modulate = Color(UiTheme.WOOD.r, UiTheme.WOOD.g, UiTheme.WOOD.b, 0.28)
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
			card.add_child(ghost)
		card.tooltip_text = "%s: %s" % [entry[1], str(Defs.item(item_id).get("name", item_id)) if item_id != "" else "empty"]
		match role:
			"food", "potion":
				card.tooltip_text += "\nClick: use one.  Right click: clear.  Double click or drag food or medicine here."
				card.pressed.connect(func() -> void:
					if item_id != "":
						client.use_item(item_id))
				card.gui_input.connect(func(event: InputEvent) -> void:
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
						_set_quick_slot(role, ""))
			"mount":
				card.tooltip_text += "\nClick: mount or get off (F4)."
				card.pressed.connect(func() -> void: _press_key(KEY_F4))
			"bag":
				card.tooltip_text += "\nA carried pack eases heavy loads by itself."
		if _drag_role == role:
			var glow := StyleBoxFlat.new()
			glow.bg_color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.35)
			glow.set_corner_radius_all(9)
			glow.set_border_width_all(3)
			glow.border_color = UiTheme.GOLD
			glow.shadow_color = Color(1.0, 0.85, 0.4, 0.6)
			glow.shadow_size = 8
			card.add_theme_stylebox_override("normal", glow)
		var accepts := func(_at: Vector2, data: Variant) -> bool:
			return data is Dictionary and _doll_role(str(data.get("item", ""))) == role
		var receive := func(_at: Vector2, data: Variant) -> void:
			_put_in_doll(str(data.get("item", "")))
		card.set_drag_forwarding(Callable(), accepts, receive)
		_doll.add_child(card)
	# Silver and carried weight beside the sockets.
	for child in _doll_info.get_children():
		child.queue_free()
	var silver := Label.new()
	silver.text = "Silver  %d" % client.inventory.count("silver")
	silver.add_theme_font_size_override("font_size", 13)
	_doll_info.add_child(silver)
	var weight: float = client.inventory.total_weight()
	var load := Label.new()
	load.text = "Load  %.1f kg" % weight
	load.add_theme_font_size_override("font_size", 13)
	_doll_info.add_child(load)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 10)
	bar.show_percentage = false
	bar.max_value = Defs.CARRY_HEAVY_KG
	bar.value = minf(weight, Defs.CARRY_HEAVY_KG)
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(5)
	fill.bg_color = Color(0.45, 0.6, 0.25) if weight <= Defs.CARRY_COMFORT_KG else (Color(0.85, 0.6, 0.2) if weight < Defs.CARRY_HEAVY_KG else Color(0.75, 0.2, 0.15))
	bar.add_theme_stylebox_override("fill", fill)
	bar.tooltip_text = "Comfortable up to %d kg, heavy at %d kg." % [int(Defs.CARRY_COMFORT_KG), int(Defs.CARRY_HEAVY_KG)]
	_doll_info.add_child(bar)


## Equip or assign an item, as dropping it on its socket or double clicking it does.
func _put_in_doll(item_id: String) -> void:
	match _doll_role(item_id):
		"weapon", "armor", "head", "cape", "hands", "feet":
			if not client.inventory.is_equipped(item_id):
				client.use_item(item_id) # The server equips worn items on use.
		"food", "potion":
			_set_quick_slot(_doll_role(item_id), item_id)
		"bag", "mount":
			say("%s works while you carry it." % str(Defs.item(item_id).get("name", item_id)))
		_:
			client.use_item(item_id)


func _set_quick_slot(role: String, item_id: String) -> void:
	_quick_slots[role] = item_id
	var config := ConfigFile.new()
	for key in _quick_slots:
		config.set_value("quick", key, _quick_slots[key])
	config.save("user://quick_slots.cfg")
	_inventory_signature = "" # Redraw the bag.


func _load_quick_slots() -> void:
	var config := ConfigFile.new()
	if config.load("user://quick_slots.cfg") == OK:
		for key in _quick_slots:
			_quick_slots[key] = str(config.get_value("quick", key, ""))


## Picking up a backpack item: a ghost of its icon follows the mouse and the socket it fits lights up.
func _drag_item(item_id: String) -> Variant:
	var preview := TextureRect.new()
	preview.texture = ItemIcons.icon(item_id)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(48, 48)
	preview.size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = Vector2(-24, -24)
	_inventory_panel.set_drag_preview(holder)
	_drag_role = _doll_role(item_id)
	_refresh_equipment()
	return {"item": item_id}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_role != "":
		_drag_role = ""
		_inventory_signature = ""


static func _short_count(count: int) -> String:
	if count >= 10000:
		return "%dk" % (count / 1000)
	return str(count)


func _refresh_crafting() -> void:
	# Every slot counts: changes to fish, ore, medicine etc must refresh recipes,
	# not only the old special case of wood_1.
	var use_bank: bool = _craft_use_stash.button_pressed
	var signature := str(client.inventory.slots) + str(client.you.get("crafting_level", 1)) \
		+ _craft_search.text + str(_craft_ready_only.button_pressed) \
		+ str(use_bank) + (str(client.stash.slots) if use_bank else "") + str(_craft_filter)
	if signature == _craft_signature:
		return
	_craft_signature = signature
	for child in _craft_list.get_children():
		child.queue_free()
	var entries: Array[Dictionary] = CraftingCatalog.entries(
		client.inventory, _craft_search.text, _craft_ready_only.button_pressed,
		int(client.you.get("crafting_level", 1)),
		client.stash if use_bank else null)
	entries.assign(entries.filter(func(entry: Dictionary) -> bool:
		return bool(_craft_filter.get(_item_category(str(Defs.recipes()[str(entry["id"])]["output"])), true))))
	_craft_result_count.text = "%d recipes | %s | MAX is a safe batch (limit 50)." % [
		entries.size(), "Hub bank materials + backpack" if use_bank else "Backpack materials only"]
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No matching recipes. Try fewer words or disable the filter."
		_craft_list.add_child(empty)
	for entry in entries:
		var recipe_id: String = str(entry["id"])
		var recipe: Dictionary = Defs.recipes()[recipe_id]
		# A recipe row in the manner of an RPG workshop: the product as a big tile (click it to craft), its name, and the
		# ingredients as small tiles with have / need under each, red where something is missing.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ready: bool = bool(entry["ready"])
		var output_id: String = str(recipe["output"])
		var tile := _item_card(output_id, int(recipe.get("count", 1)), false, Vector2(58, 58))
		tile.disabled = not ready
		tile.modulate = Color(1, 1, 1) if ready else Color(1, 1, 1, 0.55)
		var station: String = str(recipe["station"])
		tile.tooltip_text = "%s\n%s%s" % [str(Defs.item(output_id).get("name", output_id)),
			"Click to craft" if ready else ("Needs crafting level %d" % int(entry["tier"]) if bool(entry["skill_locked"]) else "Missing ingredients or space"),
			"  (at a workbench)" if station == "workbench" else ("  (campfire or workbench)" if station == "campfire" else "")]
		tile.pressed.connect(func() -> void:
			if use_bank:
				client.craft_from_stash(recipe_id, 1)
			else:
				client.craft(recipe_id, 1))
		row.add_child(tile)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 2)
		var title := Label.new()
		title.text = str(Defs.item(output_id).get("name", output_id))
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", UiTheme.INK if ready else UiTheme.INK_SOFT)
		body.add_child(title)
		var parts := HBoxContainer.new()
		parts.add_theme_constant_override("separation", 6)
		for input in recipe["inputs"]:
			var need: int = int(recipe["inputs"][input])
			var have: int = client.inventory.count(str(input)) + (client.stash.count(str(input)) if use_bank else 0)
			var part := VBoxContainer.new()
			part.add_theme_constant_override("separation", 0)
			var small := _item_card(str(input), 0, false, Vector2(32, 32))
			small.mouse_filter = Control.MOUSE_FILTER_PASS
			small.tooltip_text = str(Defs.item(str(input)).get("name", input))
			for badge in small.get_children():
				if badge is Label:
					badge.queue_free() # Too small for tier badges; the tile colour and frame tell the tier.
			part.add_child(small)
			var amount := Label.new()
			amount.text = "%d/%d" % [mini(have, 999), need]
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			amount.add_theme_font_size_override("font_size", 12)
			amount.add_theme_color_override("font_color", UiTheme.INK_SOFT if have >= need else Color(0.7, 0.15, 0.1))
			part.add_child(amount)
			parts.add_child(part)
		body.add_child(parts)
		row.add_child(body)
		var amount_max: int = int(entry["max_batches"])
		if ready and amount_max > 1:
			var max_button := Button.new()
			max_button.text = "x%d" % amount_max
			max_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			max_button.tooltip_text = "Craft %d batches in one validated server request (no partial material consumption)." % amount_max
			max_button.pressed.connect(func() -> void:
				if use_bank:
					client.craft_from_stash(recipe_id, amount_max)
				else:
					client.craft(recipe_id, amount_max))
			row.add_child(max_button)
		if ready and not use_bank and station == "workbench":
			var focus_button := Button.new()
			focus_button.text = "Focus"
			focus_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			focus_button.tooltip_text = "Craft with focus at a city workbench: 35%% of the materials come back. Costs %d focus (you have %d; it refills over a day)." % [
				ReturnRate.focus_cost(output_id, maxi(1, Defs.tier_of(output_id)), 1), int(client.you.get("focus", 0))]
			focus_button.pressed.connect(func() -> void: client.craft_focus(recipe_id, 1))
			row.add_child(focus_button)
		var divider := VBoxContainer.new()
		divider.add_theme_constant_override("separation", 6)
		divider.add_child(row)
		divider.add_child(_rule())
		row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(divider)
		divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_craft_list.add_child(row)
