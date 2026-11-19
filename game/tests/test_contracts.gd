extends RefCounted
## Canonical game contracts: executable with the full server regression suite.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at_hub(server, player) -> void:
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	player.position = Vector3(hub.x, server.world.height_at(hub.x, hub.y), hub.y)


func run(t) -> void:
	t.current = "contract definitions and validation"
	var empty: Dictionary = Contracts.empty_state()
	t.check(Contracts.valid_state(empty), "fresh journal is valid")
	t.eq(Contracts.ORDER.size(), 4, "four unique missions are available")
	for id in Contracts.ORDER:
		t.check(Contracts.CATALOG.has(id), "valid mission " + id)
		var rule: Dictionary = Contracts.CATALOG[id]
		for key in ["deliver", "possess", "reward"]:
			for item in rule[key]:
				t.check(Defs.is_item(str(item)), "catalog contains valid item: " + str(item))
	var invalid: Dictionary = empty.duplicate(true)
	invalid["completed"] = ["weapon_training"]
	t.check(not Contracts.valid_state(invalid), "cannot skip prerequisite contracts")
	invalid = empty.duplicate(true)
	invalid["active"] = "infected_patrol"
	t.check(not Contracts.valid_state(invalid), "cannot select a future contract")
	invalid = empty.duplicate(true)
	invalid["progress"] = 1
	t.check(not Contracts.valid_state(invalid), "no kill progress without an active mission")
	invalid = empty.duplicate(true)
	invalid["progress"] = -1
	t.check(not Contracts.valid_state(invalid), "negative progress rejected")
	invalid = empty.duplicate(true)
	invalid["completed"] = [2]
	t.check(not Contracts.valid_state(invalid), "non-string completion rejected")

	t.current = "hub authorization and resource delivery"
	var server := GameServer.new(WorldGen.new(42), 9)
	var player = server.add_player(91, "Quest Survivor")
	player.position = Vector3(120.0, server.world.height_at(120.0, 120.0), 120.0)
	t.eq(server.cmd_contract(91, "accept")["reason"], "no_station",
		"contract requests require a real hub location")
	_at_hub(server, player)
	t.eq(server.cmd_contract(91, "unknown")["reason"], "unknown_action", "invalid command rejected")
	t.eq(server.cmd_contract(91, "claim")["reason"], "no_active", "cannot claim before accepting")
	t.check(server.cmd_contract(91, "accept")["ok"], "accept first camp task")
	t.eq(player.contract_state["active"], "camp_supplies", "correct first task")
	t.eq(server.cmd_contract(91, "accept")["reason"], "already_active", "cannot stack tasks")
	t.eq(server.cmd_contract(91, "claim")["reason"], "missing_items", "no reward for empty delivery")
	player.inventory.add("wood_1", 4)
	player.inventory.add("fiber_1", 3)
	var result: Dictionary = server.cmd_contract(91, "claim")
	t.check(result["ok"], "deliver required scavenged resources")
	t.eq(player.inventory.count("wood_1"), 0, "consume exact wood delivery")
	t.eq(player.inventory.count("fiber_1"), 0, "consume exact fiber delivery")
	t.eq(player.inventory.count("silver"), 12, "award silver exactly once")
	t.eq(player.inventory.count("bandage"), 3, "add bandage to starter kit")
	t.eq(server.cmd_contract(91, "claim")["reason"], "no_active", "replayed claim does not mint rewards")
	t.eq(player.inventory.count("silver"), 12, "repeated delivery does not increase silver")

	t.current = "crafting requirement and capacity rollback"
	t.check(server.cmd_contract(91, "accept")["ok"], "accept weapon trial")
	t.eq(server.cmd_contract(91, "claim")["reason"], "missing_items", "weapon required")
	player.inventory.add("plank_1", 3)
	t.check(server.cmd_craft(91, "club_1")["ok"], "actual crafting produces the trial weapon")
	t.eq(player.inventory.count("club_1"), 1, "crafting consumed planks")
	var test_full := Inventory.new(Defs.INVENTORY_SLOTS)
	test_full.add("club_1", 1)
	for id in Defs.items():
		if id in ["club_1", "silver", "water_bottle"]:
			continue
		test_full.add(id, 1)
	var full_before := test_full.to_dict()
	var stage := {"active": "weapon_training", "progress": 0, "completed": ["camp_supplies"]}
	t.eq(Contracts.claim(test_full, stage)["reason"], "no_space",
		"mission cannot pay when backpack is entirely full")
	t.eq(test_full.to_dict(), full_before, "failed claim leaves every stack untouched")
	t.eq(stage["active"], "weapon_training", "failed claim retains active task")
	t.check(server.cmd_contract(91, "claim")["ok"], "show crafted club and receive supplies")
	t.eq(player.inventory.count("club_1"), 1, "gear ownership trial does not consume weapon")
	t.eq(player.inventory.count("silver"), 30, "adds fixed weapon trial reward")

	t.current = "infected kills and save roundtrip"
	t.check(server.cmd_contract(91, "accept")["ok"], "begin infected patrol")
	t.eq(server.cmd_contract(91, "claim")["reason"], "incomplete", "kills must occur after accepting")
	var z1 = Zombie.new(server.new_id(), "walker", player.position + Vector3(4, 0, 0))
	var z2 = Zombie.new(server.new_id(), "walker", player.position + Vector3(6, 0, 0))
	server.zombies[z1.id] = z1
	server.zombies[z2.id] = z2
	server._damage_target(player, {"kind": "zombie", "id": z1.id}, 1000.0)
	t.eq(player.contract_state["progress"], 1, "real server kill credits the task")
	server._damage_target(player, {"kind": "zombie", "id": z1.id}, 1000.0)
	t.eq(player.contract_state["progress"], 1, "same zombie cannot count twice")
	var midway: Dictionary = server.character_data(player)
	t.check(server.valid_character_data(midway), "saved journal survives Nakama validation")
	player.contract_state = Contracts.empty_state()
	t.check(server.apply_character(player, midway), "can restore an in-progress journal")
	t.eq(player.contract_state["progress"], 1, "one kill survives reload")
	server._damage_target(player, {"kind": "zombie", "id": z2.id}, 1000.0)
	t.eq(player.contract_state["progress"], 2, "second unique zombie completes objective")
	t.check(server.cmd_contract(91, "claim")["ok"], "two kills give patrol reward")
	t.eq(player.inventory.count("silver"), 65, "all three rewards sum correctly")
	t.check(server.cmd_contract(91, "accept")["ok"], "open fourth ruin expedition")
	t.eq(player.contract_state["active"], "ruin_recovery", "ruin task becomes active")
	t.eq(server.cmd_contract(91, "claim")["reason"], "incomplete", "no payout without distinct crates")
	t.check(not Contracts.record_crate(Contracts.empty_state(), 12), "inactive journal ignores crate events")
	var crates: Array = []
	for cx in range(8, 30):
		if crates.size() >= 2:
			break
		for cz in range(8, 30):
			if crates.size() >= 2:
				break
			for found in server.world.chunk(Vector2i(cx, cz))["crates"]:
				if not server.world.is_water(float(found["x"]), float(found["z"])):
					crates.append(found)
					break
	t.eq(crates.size(), 2, "world contains two distinct ruin caches")
	if crates.size() == 2:
		for i in range(2):
			var cache: Dictionary = crates[i]
			var x: float = float(cache["x"])
			var z: float = float(cache["z"])
			player.position = Vector3(x - 1.0, server.world.height_at(x - 1.0, z), z)
			t.check(server.cmd_loot(91, int(cache["id"]))["ok"], "server authorizes ruin cache opening")
			t.eq(player.contract_state["progress"], i + 1, "opening advances contract once")
			t.eq(server.cmd_loot(91, int(cache["id"]))["reason"], "empty", "cache cannot reopen instantly")
			t.eq(player.contract_state["progress"], i + 1, "duplicate loot does not credit progress")
		server.opened_crates.erase(int(crates[0]["id"]))
		var old: Dictionary = crates[0]
		player.position = Vector3(float(old["x"]) - 1.0, 0.0, float(old["z"]))
		t.check(server.cmd_loot(91, int(old["id"]))["ok"], "same physical cache can refill")
		t.eq(player.contract_state["progress"], 2, "refilled cache cannot count a second time")
		var journal_save: Dictionary = server.character_data(player)
		t.check(server.apply_character(player, journal_save), "cache identifiers persist in a saved character")
		t.eq(player.contract_state["crate_ids"].size(), 2, "two unique IDs survive reload")
		player.position = Vector3(150.0, server.world.height_at(150.0, 0.0), 0.0)
		t.eq(server.cmd_contract(91, "claim")["reason"], "no_station", "offsite claim denied")
		_at_hub(server, player)
		var before_silver: int = player.inventory.count("silver")
		var before_ammo: int = player.inventory.count("ammo_9mm")
		t.check(server.cmd_contract(91, "claim")["ok"], "two distinct caches complete expedition")
		t.eq(player.inventory.count("silver"), before_silver + 60, "silver payout is exactly 60")
		t.eq(player.inventory.count("ammo_9mm"), before_ammo + 10, "payout includes ten bullets")
		t.eq(server.cmd_contract(91, "claim")["reason"], "no_active", "claim cannot repeat")
	t.eq(server.cmd_contract(91, "accept")["reason"], "all_complete", "finite mission chain ends")
	t.eq(player.contract_state["completed"].size(), 4, "four tasks in completion history")

	t.current = "corrupt saves reject all state changes"
	var original: Dictionary = server.character_data(player)
	invalid = original.duplicate(true)
	invalid["contracts"]["completed"] = ["camp_supplies", "camp_supplies"]
	t.check(not server.apply_character(player, invalid), "duplicate completed ID rejected")
	t.eq(player.contract_state["completed"].size(), 4, "failed save does not change journal")
	t.eq(player.inventory.count("silver"), 65, "failed save does not change wallet")
	invalid = original.duplicate(true)
	invalid["contracts"]["active"] = "hacked_rewards"
	t.check(not server.valid_character_data(invalid), "unrecognized client-forged task rejected")
	var invalid_crates: Dictionary = original.duplicate(true)
	invalid_crates["contracts"]["crate_ids"] = ["forged"]
	t.check(not server.valid_character_data(invalid_crates), "completed journal cannot hold active cache IDs")
	var legacy: Dictionary = original.duplicate(true)
	legacy.erase("contracts")
	t.check(server.apply_character(player, legacy), "pre-contract Nakama v1 save still loads")
	t.eq(player.contract_state["completed"].size(), 0, "legacy journal starts empty")
