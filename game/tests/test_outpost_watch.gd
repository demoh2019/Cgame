extends RefCounted
## Private alarm visibility, real fortification cost, infiltration,
## valid Nakama guild identity, cooldown and ownership revocation.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const OutpostWatch = preload("res://scripts/shared/outpost_watch.gd")

const GUILD_ID := "12345678-1234-1234-1234-123456789abc"


func _move(server, player, x: float, z: float) -> void:
	player.position = Vector3(x, server.world.height_at(x, z), z)


func _tick(server, seconds: float = 0.25) -> Array:
	server.time += seconds
	return server.territory.tick(seconds, server.time, server.players, server.parties)


func _alerts(changed: Array) -> Array:
	return changed.filter(func(event): return str(event.get("type", "")) == "outpost_watch")


func run(t) -> void:
	t.current = "siege alarm requires a paid fortified, controlled outpost"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(not server.territory.sites.is_empty(), "seeded world has an outpost")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var id: int = int(site["id"])
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	var commander = server.add_player(501, "Defender", "watch-501")
	var soldier = server.add_player(502, "Sentinel", "watch-502")
	var guildmate = server.add_player(503, "Remote Ally", "watch-503")
	var raider = server.add_player(504, "Raider")
	_move(server, commander, x, z)
	_move(server, soldier, x + 1.0, z)
	_move(server, guildmate, x + 150.0, z)
	_move(server, raider, x + 150.0, z)
	t.check(server.cmd_party_invite(501, 502)["ok"], "server validates real group invitation")
	t.check(server.cmd_party_accept(502)["ok"], "defenders form real party")
	var group: int = server.parties.group_of(501)
	site["owner"] = group
	site["until"] = server.time + Territory.HOLD_SECONDS
	_move(server, raider, x + 2.0, z)
	t.eq(_alerts(_tick(server)).size(), 0, "unfortified outposts have no watchtower")
	t.eq(site["watch_ready_at"], 0.0, "no phantom cooldown without a tower")

	_move(server, raider, x + 150.0, z)
	_tick(server) # Clear stale contested status before construction.
	commander.inventory.add("wood_1", 10)
	commander.inventory.add("stone_1", 10)
	var wood_before: int = commander.inventory.count("wood_1")
	var built: Dictionary = server.cmd_outpost_fortify(501, id, 1)
	t.check(bool(built.get("ok", false)), "real resources build tier-one fortification")
	t.eq(site["fortification"], 1, "tier one unlocks the watch signal")
	t.check(commander.inventory.count("wood_1") < wood_before, "watchtower is not free")
	_move(server, raider, x + 2.0, z)
	var alerts: Array = _alerts(_tick(server))
	t.eq(alerts.size(), 1, "one hostile infiltration raises an alarm")
	if alerts.is_empty():
		return
	var alarm: Dictionary = alerts[0]
	t.eq(int(alarm["owner"]), group, "alert is addressed to the owning side")
	t.eq(int(alarm["id"]), id, "the message names only the attacked flag")
	t.check(not alarm.has("peer") and not alarm.has("enemy") and not alarm.has("members"),
		"do not disclose attacker identity or private guild roster")
	t.near(float(site["watch_ready_at"]) - server.time,
		OutpostWatch.ALERT_COOLDOWN, 0.001, "rate-limit timestamp is server-owned")

	t.current = "remote private visibility and verified cross-party guild support"
	var net := Net.new()
	net.role = "server"
	net.sim = server
	_move(server, commander, x + 160.0, z)
	t.check(net._event_visible_to(alarm, 501), "remote owning commander receives alarm")
	t.check(net._event_visible_to(alarm, 502), "remote or nearby defender is notified")
	t.check(not net._event_visible_to(alarm, 503),
		"unverified remote stranger cannot observe private alarm")
	t.check(not net._event_visible_to(alarm, 504),
		"attacker cannot subscribe to defender alarm stream")
	var verified := {"ok": true, "guild_id": GUILD_ID, "guild_name": "Watchkeepers", "rank": 2}
	for id_peer in [501, 502, 503]:
		t.check(server.set_verified_guild(id_peer, verified), "guild must be confirmed by backend")
	t.check(net._event_visible_to(alarm, 503),
		"verified cross-party guildmate receives distress call from far away")
	var invalid: Dictionary = alarm.duplicate()
	invalid["owner"] = 999999
	t.check(not net._event_visible_to(invalid, 503),
		"client-forged owner cannot redirect alarm")
	invalid = alarm.duplicate()
	invalid["id"] = 999999
	t.check(not net._event_visible_to(invalid, 503),
		"unknown outpost ID cannot expose a private message")

	t.current = "cooldown and real noncombat guild presence"
	t.eq(_alerts(_tick(server)).size(), 0,
		"continuously hostile flag does not spam multiple notifications")
	_move(server, raider, x + 150.0, z)
	_tick(server)
	_move(server, guildmate, x + 1.0, z)
	server.time += OutpostWatch.ALERT_COOLDOWN + 0.5
	t.eq(_alerts(_tick(server)).size(), 0,
		"verified guildmates at the flag are not mistaken for enemies")
	_move(server, guildmate, x + 150.0, z)
	_move(server, raider, x + 2.0, z)
	alerts = _alerts(_tick(server))
	t.eq(alerts.size(), 1, "after cooldown a renewed enemy advance triggers another alarm")

	t.current = "no stale signal from destroyed or expired fortifications"
	site["fortification"] = 0
	server.time += OutpostWatch.ALERT_COOLDOWN + 1.0
	t.eq(_alerts(_tick(server)).size(), 0,
		"breached zero-tier tower stops reporting despite ongoing attackers")
	t.check(not net._event_visible_to(alarm, 501),
		"outdated alerts do not survive lost fortification")
	site["fortification"] = 1
	_move(server, raider, x + 150.0, z)
	site["until"] = server.time
	_tick(server)
	t.eq(int(site["owner"]), 0, "expired outpost becomes neutral")
	t.eq(float(site["watch_ready_at"]), 0.0, "expiry clears all signal timers")
	t.check(not net._event_visible_to(alarm, 501),
		"lost ownership instantly revokes delayed private messages")
	net.free()
