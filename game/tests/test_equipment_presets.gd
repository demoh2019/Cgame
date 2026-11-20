extends RefCounted
## Player-owned classless weapon/armor presets. No client item grants or
## remote / mid-combat changes; strict backward-compatible character storage.
const EquipmentPresets = preload("res://scripts/shared/equipment_presets.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _hub(server, player) -> void:
	var at := GameServer.WORKBENCH_POSITION
	player.position = Vector3(at.x, server.world.height_at(at.x, at.y), at.y)


func run(t) -> void:
	t.current = "three bounded persistent classless equipment slots"
	var sets: Array = EquipmentPresets.empty_slots()
	t.eq(sets.size(), 3, "exactly three slots are available")
	t.check(EquipmentPresets.valid_state(sets), "empty defaults validate")
	var pack := Inventory.new()
	t.eq(EquipmentPresets.save_slot(sets, 0, pack).get("reason"), "nothing_equipped",
		"empty-handed player does not create an active preset")
	t.eq(EquipmentPresets.save_slot(sets, -1, pack).get("reason"), "invalid_slot",
		"negative preset ID rejected")
	t.eq(EquipmentPresets.save_slot(sets, 3, pack).get("reason"), "invalid_slot",
		"oversized preset ID rejected")
	pack.add("club_1", 1)
	pack.add("jacket_1", 1)
	pack.add("bow_2", 1)
	pack.add("jacket_2", 1)
	t.check(pack.equip("club_1") and pack.equip("jacket_1"), "melee kit is owned")
	t.check(EquipmentPresets.save_slot(sets, 0, pack).get("ok", false),
		"first kit remembers real equipped items")
	t.eq(sets[0], {"weapon": "club_1", "armor": "jacket_1"},
		"record contains only two verified item IDs")
	t.check(pack.equip("bow_2") and pack.equip("jacket_2"), "ranged kit is owned")
	t.check(EquipmentPresets.save_slot(sets, 1, pack).get("ok", false),
		"second kit can be different")
	var items_before: Array = pack.slots.duplicate(true)
	var switched: Dictionary = EquipmentPresets.equip_slot(sets, 0, pack)
	t.check(switched.get("ok", false), "switch to saved melee kit")
	t.eq(pack.weapon, "club_1", "saved weapon was equipped")
	t.eq(pack.armor, "jacket_1", "saved armor was equipped")
	t.eq(pack.slots, items_before, "switching gear creates or removes no items")
	t.eq(EquipmentPresets.equip_slot(sets, 2, pack).get("reason"), "empty_slot",
		"empty slot cannot become an imaginary starter kit")
	t.check(EquipmentPresets.clear_slot(sets, 1).get("ok", false),
		"player may remove their saved kit without dropping equipment")
	t.eq(pack.weapon, "club_1", "clearing saved kit does not unequip actual item")
	t.eq(sets[1], {}, "removed slot is really empty")

	t.current = "missing or malformed items cannot partially equip or mint gear"
	pack.equip("bow_2")
	pack.equip("jacket_2")
	var before_weapon: String = pack.weapon
	var before_armor: String = pack.armor
	pack.remove("club_1", 1)
	t.eq(EquipmentPresets.equip_slot(sets, 0, pack).get("reason"), "missing_items",
		"selling or losing saved weapon blocks the entire switch")
	t.eq(pack.weapon, before_weapon, "failed switch leaves current weapon unchanged")
	t.eq(pack.armor, before_armor, "failed switch leaves current armor unchanged")
	t.eq(EquipmentPresets.save_slot(sets, 9, pack).get("reason"), "invalid_slot",
		"cannot write an out-of-bounds preset")
	t.eq(EquipmentPresets.clear_slot(sets, -5).get("reason"), "invalid_slot",
		"cannot clear an out-of-bounds preset")
	t.check(not EquipmentPresets.valid_state([{}]), "wrong array length rejected")
	t.check(not EquipmentPresets.valid_state([{}, {}, 1]), "non-dictionary slot rejected")
	t.check(not EquipmentPresets.valid_state([
		{"weapon": "silver", "armor": "jacket_1"}, {}, {}]),
		"currency cannot masquerade as a weapon")
	t.check(not EquipmentPresets.valid_state([
		{"weapon": "club_1", "armor": "wood_1"}, {}, {}]),
		"resource cannot masquerade as armor")
	t.check(not EquipmentPresets.valid_state([
		{"weapon": "god_sword", "armor": ""}, {}, {}]),
		"nonexistent item IDs rejected")
	t.check(not EquipmentPresets.valid_state([
		{"weapon": "club_1", "armor": "", "quantity": 99999}, {}, {}]),
		"extra item quantities or stats forbidden")
	t.check(not EquipmentPresets.valid_state([
		{"weapon": 123, "armor": ""}, {}, {}]),
		"numeric item ID injection rejected")
	t.check(not EquipmentPresets.valid_state([
		{"weapon": "", "armor": ""}, {}, {}]),
		"empty records must use an empty dictionary")

	t.current = "real server requires safe workbench and no combat"
	var sim := GameServer.new(WorldGen.new(24), 24)
	var player = sim.add_player(701, "Survivor")
	t.eq(sim.cmd_equipment_preset(999, "save", 0).get("reason"), "unknown_player",
		"unknown peer ID cannot touch a saved preset")
	player.inventory.add("club_1", 1)
	player.inventory.add("jacket_1", 1)
	player.inventory.add("bow_2", 1)
	player.inventory.add("jacket_2", 1)
	player.inventory.equip("club_1")
	player.inventory.equip("jacket_1")
	t.eq(sim.cmd_equipment_preset(701, "save", 0).get("reason"), "no_station",
		"remote survivor cannot save loadouts anywhere in the world")
	_hub(sim, player)
	t.eq(sim.cmd_equipment_preset(701, "save", -1).get("reason"), "invalid_slot",
		"server bounds-checks requested slot")
	t.eq(sim.cmd_equipment_preset(701, "admin", 0).get("reason"), "invalid_action",
		"only save, equip and clear are allowed")
	player.mounted = true
	t.eq(sim.cmd_equipment_preset(701, "save", 0).get("reason"), "busy",
		"mounting forbids instant inventory swaps")
	player.mounted = false
	player.combat_tag_until = sim.time + 40.0
	t.eq(sim.cmd_equipment_preset(701, "save", 0).get("reason"), "busy",
		"PvP combat tag cannot be bypassed at hub")
	player.combat_tag_until = 0.0
	player.action = {"type": "gather"}
	t.eq(sim.cmd_equipment_preset(701, "save", 0).get("reason"), "busy",
		"busy survivors cannot change saved kits")
	player.action = {}
	t.check(sim.cmd_equipment_preset(701, "save", 0).get("ok", false),
		"server records first equipped kit")
	t.eq(sim.snapshot_for(701)["you"]["equipment_presets"][0]["weapon"], "club_1",
		"private snapshot shows the owner their saved equipment")
	player.inventory.equip("bow_2")
	player.inventory.equip("jacket_2")
	player.edge_coating_weapon = "bow_2"
	player.edge_coating_seconds = 30.0
	player.sharpened_weapon = "bow_2"
	player.sharpened_hits = 4
	player.plated_armor = "jacket_2"
	player.plated_hits = 4
	player.parry_window = 0.25
	player.guardian_brace = 3.0
	var server_swap: Dictionary = sim.cmd_equipment_preset(701, "equip", 0)
	t.check(server_swap.get("ok", false), "real authenticated safe swap works")
	t.eq(player.inventory.weapon, "club_1", "server equips recorded weapon")
	t.eq(player.inventory.armor, "jacket_1", "server equips recorded armor")
	t.eq(player.edge_coating_seconds, 0.0, "weapon swap cancels timed coating")
	t.eq(player.sharpened_weapon, "", "weapon swap cancels old whetstone effect")
	t.eq(player.plated_armor, "", "armor swap cancels old plate")
	t.eq(player.guardian_brace, 0.0, "swapping cannot prolong frontline brace")
	t.eq(player.parry_window, 0.0, "switching resets melee parry window")
	t.check(player.dirty_inventory and player.dirty_character,
		"loadout changes replicate inventory and schedule persistent save")
	var loaded: Dictionary = sim.character_data(player)
	t.eq(loaded["equipment_presets"][0]["weapon"], "club_1",
		"character save remembers owned set without quantity")
	var copy = sim.add_player(702, "Restored")
	t.check(sim.apply_character(copy, loaded), "save survives relog")
	t.eq(copy.equipment_presets[0]["armor"], "jacket_1",
		"restored character retains the preset")
	var bad: Dictionary = loaded.duplicate(true)
	bad["equipment_presets"][0]["weapon"] = "silver"
	t.check(not sim.apply_character(copy, bad), "forged equipment ID save rejected")
	t.eq(copy.equipment_presets[0]["weapon"], "club_1",
		"invalid save leaves previously loaded state unchanged")
	var legacy: Dictionary = loaded.duplicate(true)
	legacy.erase("equipment_presets")
	t.check(sim.apply_character(copy, legacy), "old accounts without presets still load")
	t.eq(copy.equipment_presets, EquipmentPresets.empty_slots(),
		"legacy character starts with blank presets")
