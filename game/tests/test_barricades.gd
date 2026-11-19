extends RefCounted
## No live sockets: these tests run the actual game server and deterministic
## shared collision rules used by the authoritative server and local preview.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _find_place(world) -> Vector2:
	# A reproducible viable point outside the sanctuary, on dry, gentle
	# terrain and far from static chunk obstacles.
	for x in range(90, 300, 7):
		for z in range(90, 300, 7):
			var site := Vector2(float(x), float(z))
			var origin := site + Vector2(-2.8, 0.0)
			if world.is_water(site.x, site.y) or world.is_water(origin.x, origin.y):
				continue
			if world.normal_at(site.x, site.y).y < Structures.MIN_SLOPE_NORMAL_Y:
				continue
			var blocked := false
			for position in [site, origin]:
				for item in world.blockers_near(position.x, position.y, 2.3):
					if position.distance_to(Vector2(float(item["x"]), float(item["z"]))) < float(item["radius"]) + 1.9:
						blocked = true
						break
			if not blocked:
				return site
	return Vector2.ZERO


func run(t) -> void:
	var world := WorldGen.new(214)
	var server = GameServer.new(world, 314)
	var player = server.add_player(101, "Builder")
	var wall_pos := _find_place(world)
	t.current = "construction placement validation"
	t.check(wall_pos != Vector2.ZERO, "found a reproducible dry build position")
	if wall_pos == Vector2.ZERO:
		return
	var player_pos := wall_pos + Vector2(-2.8, 0.0)
	player.position = Vector3(player_pos.x, world.height_at(player_pos.x, player_pos.y), player_pos.y)
	t.eq(server.cmd_build(999, wall_pos.x, wall_pos.y).get("reason"), "dead", "unknown peer cannot build")
	t.eq(server.cmd_build(101, NAN, 100.0).get("reason"), "invalid_position", "nonfinite coordinates are rejected")
	t.eq(server.cmd_build(101, player_pos.x + 8.0, player_pos.y).get("reason"), "out_of_range", "far placement rejected")
	t.eq(server.cmd_build(101, wall_pos.x, wall_pos.y).get("reason"), "missing_materials", "building requires gathered wood and stone")
	player.inventory.add("wood_1", 12)
	player.inventory.add("stone_1", 6)
	var old_wood: int = player.inventory.count("wood_1")
	var old_stone: int = player.inventory.count("stone_1")
	t.check(Movement._is_free(world, wall_pos), "open location is passable before construction")
	var result: Dictionary = server.cmd_build(101, wall_pos.x, wall_pos.y)
	t.check(bool(result.get("ok", false)), "authorized, funded barricade succeeds")
	if not result.get("ok", false):
		return
	var wall_id: int = int(result["id"])
	t.eq(server.barricades.size(), 1, "the world contains one persistent-in-session structure")
	t.eq(player.inventory.count("wood_1"), old_wood - 4, "building costs four wood")
	t.eq(player.inventory.count("stone_1"), old_stone - 2, "building costs two stone")
	t.check(not Movement._is_free(world, wall_pos), "native world movement collision blocks the new wall")
	t.eq(server.cmd_build(101, wall_pos.x, wall_pos.y).get("reason"), "blocked", "overlapping placement is rejected")
	t.eq(player.inventory.count("wood_1"), old_wood - 4, "failed overlap does not charge materials")
	t.eq(server.cmd_build(101, 0.0, 0.0).get("reason"), "out_of_range", "remote build cannot target safe sanctuary")

	t.current = "repair access, durability and inventory atomicity"
	t.eq(server.cmd_repair(101, wall_id).get("reason"), "full_health", "repair at full health refuses to spend")
	t.check(not server.damage_barricade(wall_id, -100.0), "invalid negative damage cannot heal a wall")
	t.check(not server.damage_barricade(wall_id, 65.0), "ordinary attack does not instantly destroy wall")
	t.near(float(server.barricades[wall_id]["hp"]), 55.0, 0.0001, "damage decreases durability")
	var neighbor = server.add_player(102, "Intruder")
	neighbor.position = Vector3(player_pos.x, world.height_at(player_pos.x, player_pos.y), player_pos.y)
	neighbor.inventory.add("wood_1", 2)
	t.eq(server.cmd_repair(102, wall_id).get("reason"), "not_owner", "a stranger cannot repair private structure")
	t.check(bool(server.cmd_repair(101, wall_id).get("ok", false)), "owner repairs structure")
	t.near(float(server.barricades[wall_id]["hp"]), 95.0, 0.0001, "one repair restores 40 health")
	t.check(bool(server.cmd_repair(101, wall_id).get("ok", false)), "second repair completes health")
	t.near(float(server.barricades[wall_id]["hp"]), Structures.MAX_HEALTH, 0.0001, "repair is capped at 120")
	t.eq(player.inventory.count("wood_1"), old_wood - 6, "two repairs cost exactly two units")
	t.eq(server.cmd_repair(101, wall_id).get("reason"), "full_health", "full durability cannot waste wood")
	t.eq(player.inventory.count("wood_1"), old_wood - 6, "rejected repair leaves inventory untouched")
	player.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	t.eq(server.cmd_repair(101, wall_id).get("reason"), "out_of_range", "distant owner cannot remotely repair")
	player.position = Vector3(player_pos.x, world.height_at(player_pos.x, player_pos.y), player_pos.y)

	t.current = "interest filtering and authoritative replication"
	var snapshot: Dictionary = server.snapshot_for(101)
	t.eq(snapshot.get("barricades", []).size(), 1, "nearby owner sees structure in authoritative snapshot")
	t.eq(int(snapshot["barricades"][0]["id"]), wall_id, "entity ID is stable for networking")
	t.check(not snapshot["barricades"][0].has("user_id"), "structure snapshot never reveals backend account")
	neighbor.position = Vector3(600.0, world.height_at(600.0, 0.0), 0.0)
	t.eq(server.snapshot_for(102).get("barricades", []).size(), 0, "distant peer receives no structure data")

	t.current = "zombies attack stuck obstacles, destroy and unblock"
	neighbor.position = Vector3(800.0, world.height_at(800.0, 0.0), 0.0)
	var zombie_position := wall_pos + Vector2(1.35, 0.0)
	var infected = Zombie.new(server.new_id(), "walker", Vector3(zombie_position.x, world.height_at(zombie_position.x, zombie_position.y), zombie_position.y))
	server.zombies[infected.id] = infected
	var before: float = float(server.barricades[wall_id]["hp"])
	for step in range(45):
		server._tick_zombies(0.05)
		if not server.barricades.has(wall_id):
			break
	t.check(not server.barricades.has(wall_id) or float(server.barricades[wall_id]["hp"]) < before, "stuck infected damages barrier while pursuing survivor")
	if server.barricades.has(wall_id):
		t.check(server.damage_barricade(wall_id, 500.0), "excess damage destroys barrier")
	t.check(not world.dynamic_blockers.has(wall_id), "destroyed structure leaves collision broadphase")
	t.check(Movement._is_free(world, wall_pos), "destroyed wall unblocks survivor movement")
	t.eq(server.snapshot_for(101).get("barricades", []).size(), 0, "destroyed structure disappears from world snapshots")
	t.eq(server.cmd_repair(101, wall_id).get("reason"), "no_structure", "destroyed walls cannot be repaired")

	t.current = "hub protections"
	player.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	t.eq(server.cmd_build(101, 2.8, 0.0).get("reason"), "safe_zone", "do not clutter safe spawn with barricades")
