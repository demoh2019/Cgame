extends RefCounted
## Captured PvP outposts supply bounded cooperative survival resources.
## Run from the canonical res://tests/run_all.gd headless server suite.

const Defs = preload("res://scripts/shared/defs.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const Supplies = preload("res://scripts/shared/outpost_supplies.gd")


func _at(server, site: Dictionary) -> Vector3:
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	return Vector3(x, server.world.height_at(x, z), z)


func _capture(server) -> void:
	for step in int(ceil((Territory.CAPTURE_SECONDS + 1.0) / 0.25)):
		server.time += 0.25
		server.territory.tick(0.25, server.time, server.players, server.parties)


func run(t) -> void:
	t.current = "outpost reward definitions"
	t.eq(Supplies.reward(0), {}, "no green zone reward")
	t.eq(Supplies.reward(1), {}, "no protected yellow zone reward")
	for zone in [2, 3]:
		var items: Dictionary = Supplies.reward(zone)
		t.eq(int(items.get("silver", 0)), 10 * (zone + 1),
			"supplies scale with full-loot region risk")
		t.eq(int(items.get("scrap", 0)), 2 * (zone + 1),
			"salvage reward increases in contested territory")
		for item_id in items:
			t.check(Defs.is_item(str(item_id)), "every cache reward is a registered item")
	t.eq(Supplies.CACHE_STOCK, 5, "one captured cache serves at most five teammates")

	t.current = "only living genuine owners near the captured flag can claim"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(server.territory.sites.size() > 0, "procedural world has at least one PvP outpost")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var owner = server.add_player(1101, "Leader", "stable-owner")
	var ally = server.add_player(1102, "Squadmate", "stable-ally")
	var enemy = server.add_player(1103, "Enemy", "enemy")
	var position := _at(server, site)
	owner.position = position
	ally.position = position + Vector3(1.0, 0.0, 0.0)
	enemy.position = position + Vector3(70.0, 0.0, 0.0)
	t.eq(server.cmd_outpost_supplies(1101, int(site["id"]))["reason"], "not_owner",
		"before capture no supplies are accessible")
	t.eq(server.cmd_outpost_supplies(1101, 99999)["reason"], "no_such_site",
		"cannot forge an unregistered supply cache")
	t.check(server.cmd_party_invite(1101, 1102)["ok"], "leader forms a real party")
	t.check(server.cmd_party_accept(1102)["ok"], "second survivor joins")
	_capture(server)
	var group: int = server.parties.group_of(1101)
	t.eq(site["owner"], group, "party actually captured the PvP outpost")
	t.eq(int(site["supplies_left"]), Supplies.CACHE_STOCK,
		"newly secured outpost starts with five finite parcels")
	t.eq(int(site["supply_epoch"]), 1, "capture increments the private stock epoch")
	t.eq(int(server.territory.public_state(server.time)[0]["supplies_left"]),
		Supplies.CACHE_STOCK, "public map shows bounded stock")
	t.check(not server.territory.public_state(server.time)[0].has("supply_claims"),
		"public world state does not expose claimant account identities")

	t.current = "all actions recheck live position and enemy contest"
	owner.position = position + Vector3(10.0, 0.0, 0.0)
	t.eq(server.cmd_outpost_supplies(1101, int(site["id"]))["reason"], "too_far",
		"claim fails when owner left the supply cache")
	owner.position = position
	t.eq(server.cmd_outpost_supplies(1103, int(site["id"]))["reason"], "too_far",
		"enemy cannot remotely mint supplies")
	enemy.position = position + Vector3(1.0, 0.0, 0.0)
	t.eq(server.cmd_outpost_supplies(1101, int(site["id"]))["reason"], "contested",
		"unaffiliated rival at the flag blocks claim without waiting for a tick")
	enemy.position = position + Vector3(70.0, 0.0, 0.0)
	t.eq(int(site["supplies_left"]), Supplies.CACHE_STOCK,
		"denied claims never deplete shared stock")

	t.current = "failed inventory transfer rolls back both items and stock"
	var original: Dictionary = owner.inventory.to_dict()
	var blocked := Inventory.new(1)
	blocked.add("water_bottle", 10)
	owner.inventory = blocked
	var full_before: Dictionary = owner.inventory.to_dict()
	t.eq(server.cmd_outpost_supplies(1101, int(site["id"]))["reason"], "no_space",
		"full backpack cannot receive any fraction of supply prize")
	t.eq(owner.inventory.to_dict(), full_before, "inventory unchanged after failed claim")
	t.eq(int(site["supplies_left"]), Supplies.CACHE_STOCK,
		"no stock consumed on failed atomic inventory transfer")
	owner.inventory.load_dict(original)

	t.current = "exactly once per account per capture and server-owned stock"
	var reward: Dictionary = Supplies.reward(server.world.zone_at(position.x, position.z))
	var silver_before: int = owner.inventory.count("silver")
	var first: Dictionary = server.cmd_outpost_supplies(1101, int(site["id"]))
	t.check(bool(first.get("ok", false)), "legitimate owner claims once")
	t.eq(owner.inventory.count("silver") - silver_before, int(reward["silver"]),
		"exact advertised silver credited once")
	t.eq(int(site["supplies_left"]), Supplies.CACHE_STOCK - 1,
		"successful claim consumes exactly one finite parcel")
	t.check(owner.dirty_inventory and owner.dirty_character,
		"claim schedules normal inventory and character save")
	t.eq(server.cmd_outpost_supplies(1101, int(site["id"]))["reason"], "already_claimed",
		"repeated authenticated RPC cannot mint duplicate resources")
	t.eq(int(site["supplies_left"]), Supplies.CACHE_STOCK - 1,
		"replayed claim cannot consume multiple parcels")
	# Same Nakama identity, different session-backed Player object: still blocked.
	var reconnect := GameServer.Player.new()
	reconnect.user_id = "stable-owner"
	reconnect.position = position
	reconnect.inventory = Inventory.new()
	reconnect.survival = Survival.new()
	t.eq(Supplies.claim(site, reconnect, group,
		server.world.zone_at(position.x, position.z), server.time, false)["reason"],
		"already_claimed", "new session with same account cannot double collect")

	t.current = "different teammates share one limited captured stock"
	t.check(bool(server.cmd_outpost_supplies(1102, int(site["id"])).get("ok", false)),
		"second party member receives one separate share")
	for peer_id in [1104, 1105, 1106]:
		var recruit = server.add_player(peer_id, "Reinforcement%d" % peer_id)
		recruit.position = position + Vector3(2.0, 0.0, 0.0)
		t.check(server.cmd_party_invite(1101, peer_id)["ok"], "leader can recruit")
		t.check(server.cmd_party_accept(peer_id)["ok"], "recruit joins captured group")
		t.check(bool(server.cmd_outpost_supplies(peer_id, int(site["id"])).get("ok", false)),
			"new teammate claims one of the remaining units")
	t.eq(int(site["supplies_left"]), 0, "five claims exhaust all captured supplies")
	t.eq(server.cmd_outpost_supplies(1102, int(site["id"]))["reason"], "empty",
		"empty cache never mints a sixth parcel")

	t.current = "ownership expires or changes without duplicating stock"
	site["until"] = server.time - 1.0
	t.eq(server.cmd_outpost_supplies(1101, int(site["id"]))["reason"], "not_owner",
		"expired holding grants no extra supplies")
	server.territory.tick(0.25, server.time, server.players, server.parties)
	t.eq(site["owner"], 0, "expired outpost becomes neutral")
	t.eq(int(site["supplies_left"]), 0, "expired cache stock cleared")
	# A successful fresh capture renews exactly five shares and all token
	# rights, never by a client-supplied reset command.
	_capture(server)
	t.eq(site["owner"], group, "same team may capture neutral outpost again")
	t.eq(int(site["supplies_left"]), Supplies.CACHE_STOCK,
		"second capture resets limited stock, not infinite daily claims")
	t.eq(int(site["supply_epoch"]), 2, "capture epoch advances server-side")
	t.check(bool(server.cmd_outpost_supplies(1101, int(site["id"])).get("ok", false)),
		"previous claimant may claim once in the new capture epoch")
