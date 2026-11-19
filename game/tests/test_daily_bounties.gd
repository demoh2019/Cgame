extends RefCounted
## UTC daily missions on top of existing combat, scavenging, inventory,
## renown, Nakama saves and the server-only camp-contract command.

const Daily = preload("res://scripts/shared/daily_bounties.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at_hub(server, player) -> void:
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	player.position = Vector3(hub.x, server.world.height_at(hub.x, hub.y), hub.y)


func _fulfill_real_server_day(server, player, today: int, t) -> void:
	var rule: Dictionary = Daily.assignment(today)
	match str(rule["kind"]):
		"kills":
			for index in int(rule["goal"]):
				var zombie = Zombie.new(server.new_id(), "walker",
					player.position + Vector3(4.0 + index, 0.0, 0.0))
				server.zombies[zombie.id] = zombie
				server._damage_target(player, {"kind": "zombie", "id": zombie.id}, 1000.0)
		"crates":
			var crates: Array = []
			for cx in range(8, 31):
				if crates.size() >= int(rule["goal"]):
					break
				for cz in range(8, 31):
					if crates.size() >= int(rule["goal"]):
						break
					for entry in server.world.chunk(Vector2i(cx, cz))["crates"]:
						if not server.world.is_water(float(entry["x"]), float(entry["z"])):
							crates.append(entry)
							break
			t.eq(crates.size(), int(rule["goal"]), "real world has distinct mission crates")
			for crate in crates:
				var x: float = float(crate["x"])
				var z: float = float(crate["z"])
				player.position = Vector3(x - 1.0, server.world.height_at(x - 1.0, z), z)
				t.check(bool(server.cmd_loot(player.id, int(crate["id"])).get("ok", false)),
					"only legitimate nearby unopened ruins advance today's bounty")
		"deliver":
			for id in rule["deliver"]:
				player.inventory.add(str(id), int(rule["deliver"][id]))


func run(t) -> void:
	t.current = "UTC calendar and rotating daily objectives"
	t.check(Daily.utc_day() > 20000, "server computes a positive modern UTC day")
	t.eq(Daily.assignment(-1), {}, "negative UTC day cannot choose quest")
	t.eq(Daily.assignment(Daily.MAX_DAY + 1), {}, "oversized UTC day cannot choose quest")
	for i in Daily.BOUNTIES.size():
		var day: int = 21000 + i
		var rule: Dictionary = Daily.assignment(day)
		t.eq(str(rule["id"]), str(Daily.BOUNTIES[i]["id"]),
			"three predictable daily missions rotate without client selection")
		t.check(str(rule["title"]).begins_with("Daily:"), "client has localized mission heading")
		for category in ["deliver", "reward"]:
			for id in rule[category]:
				t.check(Defs.is_item(str(id)), "daily input/reward must exist in shared catalog")
		t.check(int(rule["renown"]) > 0 and int(rule["renown"]) <= 5,
			"bounty rewards modest bounded reputation")
		var journal: Dictionary = Daily.empty_state()
		t.check(Daily.valid_state(journal), "legacy empty daily record valid")
		t.check(Daily.refresh(journal, day), "new day initializes server-owned quest")
		t.eq(int(journal["day"]), day, "server day is persisted in journal")
		t.check(not Daily.refresh(journal, day), "same day does not wipe genuine progress")

	t.current = "confirmed infected kills only and no replay after reward"
	var day_kills := 21000
	var combat: Dictionary = Daily.empty_state()
	Daily.refresh(combat, day_kills)
	t.check(Daily.description(combat, day_kills).contains("infected"),
		"combat quest shows objective and current progress")
	t.check(Daily.record_kill(combat, day_kills), "confirmed kill increments progress")
	t.eq(int(combat["progress"]), 1, "kill counted exactly once per real call")
	t.check(not Daily.record_crate(combat, day_kills, 100), "crate does not count as infected")
	for index in 10:
		Daily.record_kill(combat, day_kills)
	t.eq(int(combat["progress"]), 4, "excess kills cannot inflate bounded mission progress")
	var carrying := Inventory.new()
	t.check(bool(Daily.claim(carrying, combat, day_kills).get("ok", false)),
		"completed kill mission delivers camp supplies")
	t.eq(carrying.count("silver"), 24, "silver reward granted exactly once")
	t.eq(Daily.claim(carrying, combat, day_kills)["reason"], "already_claimed",
		"same UTC day never pays a second time")
	t.check(not Daily.record_kill(combat, day_kills), "post-claim kills cannot reopen bounty")
	t.eq(carrying.count("silver"), 24, "repeated claim cannot mint currency")
	t.check(not Daily.refresh(combat, day_kills - 1), "backwards host clock does not reopen quest")
	t.eq(int(combat["day"]), day_kills, "old date cannot roll back journal")
	t.check(Daily.refresh(combat, day_kills + 1), "next UTC day resets once-only reward")
	t.eq(combat["claimed"], false, "new day offers a fresh distinct mission")
	t.eq(Daily.claim(carrying, combat, day_kills + 1)["reason"], "incomplete",
		"new mission cannot be claimed using yesterday's progress")

	t.current = "distinct ruin crates, refill/duplicate immunity"
	var day_crates := 21001
	var ruins: Dictionary = Daily.empty_state()
	Daily.refresh(ruins, day_crates)
	t.check(not Daily.record_kill(ruins, day_crates), "infected kills do not substitute scavenging")
	t.check(not Daily.record_crate(ruins, day_crates, -1), "invalid crate IDs rejected")
	t.check(Daily.record_crate(ruins, day_crates, 12345), "first unique confirmed crate")
	t.check(not Daily.record_crate(ruins, day_crates, 12345), "same cache cannot count twice")
	t.check(Daily.record_crate(ruins, day_crates, 12346), "second distinct cache completes mission")
	t.eq(int(ruins["progress"]), 2, "two cache IDs make maximum progress")
	t.check(not Daily.record_crate(ruins, day_crates, 12347), "third cache cannot overflow goal")
	var bounty: Dictionary = Daily.claim(carrying, ruins, day_crates)
	t.check(bool(bounty.get("ok", false)), "distinct caches enable once-only reward")
	t.eq(carrying.count("water_bottle"), 1, "ruin mission grants survival water")

	t.current = "resource delivery transactions are atomic"
	var day_delivery := 21002
	var delivery: Dictionary = Daily.empty_state()
	Daily.refresh(delivery, day_delivery)
	t.eq(Daily.claim(carrying, delivery, day_delivery)["reason"], "missing_items",
		"unfunded resource delivery is not payable")
	var full := Inventory.new(2)
	full.add("wood_1", 6)
	full.add("fiber_1", 5)
	var before: Dictionary = full.to_dict()
	t.eq(Daily.claim(full, delivery, day_delivery)["reason"], "no_space",
		"full inventory rejects delivery and does not consume input materials")
	t.eq(full.to_dict(), before, "failed delivery restores exact starting backpack")
	t.eq(delivery["claimed"], false, "failed delivery does not consume the day's one claim")
	var backed := Inventory.new(4)
	backed.add("wood_1", 5)
	backed.add("fiber_1", 4)
	t.check(bool(Daily.claim(backed, delivery, day_delivery).get("ok", false)),
		"properly supplied camp pays delivery bounty")
	t.eq(backed.count("wood_1"), 0, "exact resource wood removed")
	t.eq(backed.count("fiber_1"), 0, "exact resource fiber removed")
	t.eq(backed.count("silver"), 28, "delivery pays exactly advertised silver")
	t.eq(Daily.claim(backed, delivery, day_delivery)["reason"], "already_claimed",
		"repeating delivery with more materials cannot double the payout")

	t.current = "strict Nakama record validation and legacy compatibility"
	for invalid in [
		{"day": -1, "progress": 0, "crate_ids": [], "claimed": false},
		{"day": 21000.5, "progress": 0, "crate_ids": [], "claimed": false},
		{"day": 21000, "progress": "3", "crate_ids": [], "claimed": false},
		{"day": 21000, "progress": 5, "crate_ids": [], "claimed": false},
		{"day": 21000, "progress": 1, "crate_ids": [], "claimed": true},
		{"day": 21001, "progress": 2, "crate_ids": ["123", "123"], "claimed": false},
		{"day": 21001, "progress": 1, "crate_ids": ["bad-id"], "claimed": false},
		{"day": 21002, "progress": 1, "crate_ids": [], "claimed": false},
		{"day": NAN, "progress": 0, "crate_ids": [], "claimed": false},
		{"day": INF, "progress": 0, "crate_ids": [], "claimed": false},
		{"day": Daily.MAX_DAY + 1, "progress": 0, "crate_ids": [], "claimed": false},
		{"day": 21000, "progress": 0, "crate_ids": [], "claimed": 1},
	]:
		t.check(not Daily.valid_state(invalid), "malformed daily record rejected atomically")

	t.current = "live server hub gating, UTC rotation, persistence and replay protection"
	var server := GameServer.new(WorldGen.new(78), 78)
	var survivor = server.add_player(7051, "Daily Survivor", "account-daily")
	_at_hub(server, survivor)
	var today: int = Daily.utc_day()
	var view: Dictionary = server.snapshot_for(survivor.id)["you"]
	t.eq(int(view["daily_utc_day"]), today, "client observes true server day")
	t.eq(int(view["daily_bounty"]["day"]), today, "private snapshot carries today's own progress")
	t.check(str(view["daily_description"]).begins_with("Daily:"), "HUD has current quest description")
	t.eq(server.cmd_contract(survivor.id, "daily_claim").get("reason", ""),
		"missing_items" if Daily.assignment(today)["kind"] == "deliver" else "incomplete",
		"claim without today's real requirements is denied")
	survivor.position = Vector3(123.0, server.world.height_at(123, 123), 123.0)
	t.eq(server.cmd_contract(survivor.id, "daily_claim")["reason"], "no_station",
		"remote or forged daily turn-in without real hub is denied")
	_at_hub(server, survivor)
	_fulfill_real_server_day(server, survivor, today, t)
	_at_hub(server, survivor)
	var before_silver: int = survivor.inventory.count("silver")
	var prior_renown: int = survivor.renown
	var result: Dictionary = server.cmd_contract(survivor.id, "daily_claim")
	t.check(bool(result.get("ok", false)), "real server-approved daily quest pays out")
	var rule: Dictionary = Daily.assignment(today)
	t.eq(survivor.inventory.count("silver") - before_silver,
		int(rule["reward"]["silver"]), "daily payout is exactly server-chosen quantity")
	t.eq(survivor.renown - prior_renown, int(rule["renown"]),
		"earned daily renown passes through existing persistent progression")
	t.eq(server.cmd_contract(survivor.id, "daily_claim").get("reason", ""), "already_claimed",
		"RPC replay cannot mint silver or renown again today")
	var saved: Dictionary = server.character_data(survivor)
	t.check(server.valid_character_data(saved), "Nakama validator accepts completed daily bounty")
	server.remove_player(survivor.id)
	var reconnect = server.add_player(7052, "Returning Survivor", "account-daily", saved)
	_at_hub(server, reconnect)
	t.eq(reconnect.daily_bounty, survivor.daily_bounty, "new session restores completed daily state")
	t.eq(server.cmd_contract(reconnect.id, "daily_claim").get("reason", ""), "already_claimed",
		"reconnect with same persisted journal cannot claim twice")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("daily_bounty")
	t.check(server.apply_character(reconnect, legacy),
		"old Nakama character without daily bounty loads with safe defaults")
	t.check(not server.valid_character_data(saved.merged(
		{"daily_bounty": {"day": today, "progress": -3,
			"crate_ids": [], "claimed": false}}, true)),
		"corrupt daily snapshot is never accepted by login validator")
