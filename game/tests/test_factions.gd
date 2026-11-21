extends RefCounted
## Faction warfare: enlist, flag, yellow-zone faction PvP, lawful kills and points.

const Factions = preload("res://scripts/shared/factions.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _yellow_spot(world) -> Vector2:
	for x in range(100, 900, 7):
		for z in range(-60, 61, 7):
			if world.zone_at(float(x), float(z)) == 1 and not world.is_safe(float(x), float(z)) and not world.is_water(float(x), float(z)):
				return Vector2(x, z)
	return Vector2.INF


func run(t) -> void:
	t.current = "faction rules"
	t.check(Factions.can_fight("wardens", true, "compact", true, 1, 1, false, false), "flagged rivals fight in yellow")
	t.check(not Factions.can_fight("wardens", true, "wardens", true, 1, 1, false, false), "no fighting your own faction")
	t.check(not Factions.can_fight("wardens", true, "compact", false, 1, 1, false, false), "unflagged players are safe")
	t.check(not Factions.can_fight("wardens", true, "compact", true, 0, 0, false, false), "never in the green zone")
	t.check(not Factions.can_fight("wardens", true, "compact", true, 1, 1, true, false), "never in safe towns")

	t.current = "server enlist, flag and fight"
	var world = WorldGen.new(8642)
	var server := GameServer.new(world, 13)
	var hub := Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	var a = server.add_player(1101, "Warden")
	var b = server.add_player(1102, "Compact")
	for p in [a, b]:
		p.inventory = Inventory.new()
		p.position = hub
	t.eq(server.cmd_faction(1101, "flag").get("reason"), "not_enlisted", "enlist before flagging")
	t.check(bool(server.cmd_faction(1101, "enlist", "wardens").get("ok", false)), "enlist at the hub")
	t.check(bool(server.cmd_faction(1102, "enlist", "compact").get("ok", false)), "rival enlists")
	t.eq(server.cmd_faction(1101, "enlist", "nope").get("reason"), "unknown_faction", "only real factions")
	server.cmd_faction(1101, "flag")
	server.cmd_faction(1102, "flag")
	var spot := _yellow_spot(world)
	t.check(spot != Vector2.INF, "found a yellow-zone spot")
	a.position = Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	b.position = Vector3(spot.x + 1.0, world.height_at(spot.x + 1.0, spot.y), spot.y)
	t.check(server._faction_enemies(a, b), "flagged rivals are enemies in yellow")
	var before: float = b.survival.health
	server._damage_target(a, {"kind": "player", "id": 1102}, 30.0, "melee")
	t.check(b.survival.health < before, "faction PvP damage applies in the yellow zone")
	b.survival.health = 1.0
	server._damage_target(a, {"kind": "player", "id": 1102}, 30.0, "melee")
	t.check(a.faction_points >= Factions.POINTS_PLAYER_KILL, "faction kill earns points")
	t.eq(a.pvp_infamy, 0.0, "faction kills are lawful: no infamy")

	t.current = "unflag delay and redeem"
	server.cmd_faction(1101, "unflag")
	t.check(a.faction_flagged, "the flag stays up during the delay")
	a.position = hub
	a.faction_points = Factions.REDEEM_COST
	t.check(bool(server.cmd_faction(1101, "redeem").get("ok", false)), "points redeem at the hub")
	t.eq(a.inventory.count("rune"), 3, "rewards granted")
	t.eq(a.faction_points, 0, "points spent")
