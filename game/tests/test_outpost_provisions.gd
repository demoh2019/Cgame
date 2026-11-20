extends RefCounted
## Timed guild logistics, idempotence, contested rights and atomic payment.
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Cargo = preload("res://scripts/shared/outpost_provisions.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")
const CLAN := "12345678-1234-1234-1234-123456789abc"


func _move(server, p, x: float, z: float) -> void:
	p.position = Vector3(x, server.world.height_at(x, z), z)


func _packs(p, count: int) -> void:
	for item in Cargo.COST:
		p.inventory.add(str(item), int(Cargo.COST[item]) * count)


func run(t) -> void:
	t.current = "paid guild logistics and replay safety"
	var server := GameServer.new(WorldGen.new(205), 205)
	if server.territory.sites.is_empty():
		t.check(false, "seed provides at least one outpost")
		return
	var site: Dictionary = server.territory.sites[0]
	var id: int = int(site["id"])
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	var lead = server.add_player(401, "Quartermaster", "qm-401")
	var friend = server.add_player(402, "Escort", "esc-402")
	var wing = server.add_player(403, "Support", "sup-403")
	var rival = server.add_player(404, "Enemy")
	_move(server, lead, x, z)
	_move(server, friend, x + 1.0, z)
	_move(server, wing, x + 70.0, z)
	_move(server, rival, x + 80.0, z)
	_packs(lead, 4)
	_packs(wing, 1)
	t.eq(server.cmd_outpost_provision(401, id, 1).get("reason", ""), "not_owner",
		"neutral outpost cannot accept deliveries")
	t.check(server.cmd_party_invite(401, 402)["ok"], "party leader invites escort")
	t.check(server.cmd_party_accept(402)["ok"], "escort joins a real party")
	site["owner"] = server.parties.group_of(401)
	site["until"] = server.time + Territory.HOLD_SECONDS
	var start: float = float(site["until"])
	var initial_wood: int = lead.inventory.count("wood_1")
	var initial_food: int = lead.inventory.count("canned_food")
	var initial_water: int = lead.inventory.count("water_bottle")
	t.eq(server.cmd_outpost_provision(401, id, 0)["reason"], "invalid_request_id",
		"zero nonce rejected")
	t.eq(server.cmd_outpost_provision(401, id, GameServer.PROVISION_MAX_REQUEST_ID + 1)["reason"],
		"invalid_request_id", "oversized nonce rejected")
	var receipt: Dictionary = server.cmd_outpost_provision(401, id, 2)
	t.check(bool(receipt.get("ok", false)), "owner delivered real survival supplies")
	t.eq(float(site["until"]), start + Cargo.EXTRA_SECONDS, "delivery adds 45s")
	t.eq(lead.inventory.count("wood_1"), initial_wood - 4, "exact wood cost")
	t.eq(lead.inventory.count("canned_food"), initial_food - 2, "exact food cost")
	t.eq(lead.inventory.count("water_bottle"), initial_water - 2, "exact water cost")
	t.eq(server.snapshot_for(401)["outposts"][0]["provisioned_seconds"], 45.0,
		"public outpost state shows cumulative resupply")
	t.eq(server.cmd_outpost_provision(401, id, 2), receipt,
		"replayed request has same receipt without a second charge")
	t.eq(lead.inventory.count("wood_1"), initial_wood - 4,
		"retry cannot pay or extend twice")
	t.eq(server.cmd_outpost_provision(401, id + 1, 2)["reason"], "request_conflict",
		"nonce cannot be reused for a new outpost")
	t.eq(server.cmd_outpost_provision(401, id, 1)["reason"], "stale_request",
		"old request does not spend cargo")
	t.current = "enemy contest denies immediate delivery and inventory is atomic"
	_move(server, rival, x + 2.0, z)
	var before: Dictionary = lead.inventory.to_dict()
	t.eq(server.cmd_outpost_provision(401, id, 3)["reason"], "contested",
		"live enemy blocks delivery without stale tick")
	t.eq(lead.inventory.to_dict(), before, "contest does not consume supplies")
	_move(server, rival, x + 80.0, z)
	_move(server, wing, x, z)
	t.eq(server.cmd_outpost_provision(403, id, 1)["reason"], "not_owner",
		"other player cannot resupply without verified guild")
	var trusted := {"ok": true, "guild_id": CLAN, "guild_name": "Caravan", "rank": 2}
	for member in [401, 402, 403]:
		t.check(server.set_verified_guild(member, trusted),
			"server verifies true Nakama guild membership")
	t.eq(GuildTerritory.owner_banner(site, server.players, server.parties)["id"], CLAN,
		"owner banner is derived from real confirmed guild")
	t.check(server.cmd_outpost_provision(403, id, 2)["ok"],
		"verified cross-party member delivers")
	t.eq(int(site["provisioned_seconds"]), 90,
		"all deliveries share one capped pool")
	_move(server, lead, x + 50.0, z)
	t.eq(server.cmd_outpost_provision(401, id, 4)["reason"], "too_far",
		"distant delivery is impossible")
	_move(server, lead, x, z)
	lead.inventory.remove("water_bottle", lead.inventory.count("water_bottle"))
	before = lead.inventory.to_dict()
	t.eq(server.cmd_outpost_provision(401, id, 5)["reason"], "missing_items",
		"delivery needs water, not just food and timber")
	t.eq(lead.inventory.to_dict(), before, "missing inputs do not charge anything")
	lead.inventory.add("water_bottle", 10)
	t.check(server.cmd_outpost_provision(401, id, 6)["ok"], "third delivery")
	t.check(server.cmd_outpost_provision(401, id, 7)["ok"], "fourth delivery")
	t.eq(float(site["provisioned_seconds"]), Cargo.MAX_EXTRA_SECONDS,
		"maximum extra ownership limited to 180 seconds")
	t.eq(float(site["until"]), start + Cargo.MAX_EXTRA_SECONDS,
		"hold duration is bounded across the whole capture")
	before = lead.inventory.to_dict()
	t.eq(server.cmd_outpost_provision(401, id, 8)["reason"], "fully_supplied",
		"fifth pack cannot extend capture")
	t.eq(lead.inventory.to_dict(), before, "hard cap never wastes supplies")
	t.eq(server.cmd_outpost_provision(401, id + 200, 9)["reason"], "no_such_site",
		"unknown location has no supply economy")
	site["until"] = server.time
	t.eq(server.cmd_outpost_provision(401, id, 10)["reason"], "not_owner",
		"expired capture cannot be supplied")
	server.territory.tick(0.25, server.time + 0.25, server.players, server.parties)
	t.eq(site["owner"], 0, "expired owner resets")
	t.eq(site["provisioned_seconds"], 0.0, "expired capture budget resets")
