extends RefCounted
## Owner rights, reconnect identity, all-or-nothing salvage and collision removal.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")


func run(t) -> void:
	var world := WorldGen.new(214)
	var server := GameServer.new(world, 55)
	var spot: Vector2 = BarricadeTest.new()._find_place(world)
	t.current = "authorized construction"
	t.check(spot != Vector2.ZERO, "found dry ground outside the hub")
	if spot == Vector2.ZERO:
		return
	var pspot := spot + Vector2(-2.8, 0.0)
	var builder = server.add_player(401, "Builder", "account-one")
	builder.position = Vector3(pspot.x, world.height_at(pspot.x, pspot.y), pspot.y)
	builder.inventory.add("wood_1", 12)
	builder.inventory.add("stone_1", 6)
	var built: Dictionary = server.cmd_build(401, spot.x, spot.y)
	t.check(bool(built.get("ok", false)), "account owner can build")
	if not bool(built.get("ok", false)):
		return
	var id: int = int(built["id"])
	t.check(world.dynamic_blockers.has(id), "new wall has collision")
	t.check(not Movement._is_free(world, spot), "wall obstructs movement")
	t.check(not Structures.public_state(server.barricades[id]).has("owner_account"),
		"account identity never leaks to clients")
	t.eq(server.cmd_dismantle(401, 999999).get("reason"), "no_structure",
		"unknown entity cannot mint salvage")

	t.current = "foreign accounts cannot claim identical peer IDs"
	server.remove_player(401)
	var intruder = server.add_player(401, "Intruder", "account-two")
	intruder.position = Vector3(pspot.x, world.height_at(pspot.x, pspot.y), pspot.y)
	t.eq(server.cmd_dismantle(401, id).get("reason"), "not_owner",
		"recycled peer ID cannot steal original account structure")
	t.eq(server.cmd_repair(401, id).get("reason"), "not_owner",
		"repair also checks account ownership")
	t.check(server.barricades.has(id), "attempt did not delete wall")
	server.remove_player(401)
	var rejoined = server.add_player(403, "Builder again", "account-one")
	rejoined.position = Vector3(pspot.x, world.height_at(pspot.x, pspot.y), pspot.y)
	t.check(Structures.can_manage(server.barricades[id], 403, rejoined.user_id),
		"account regains ownership with a new peer ID")

	t.current = "remote attempt and full backpack"
	rejoined.position = Vector3(0, world.height_at(0, 0), 0)
	t.eq(server.cmd_dismantle(403, id).get("reason"), "out_of_range",
		"owner must be near wall")
	rejoined.position = Vector3(pspot.x, world.height_at(pspot.x, pspot.y), pspot.y)
	var full = Inventory.new(1)
	full.add("water_bottle", 10)
	rejoined.inventory = full
	var snapshot: Dictionary = rejoined.inventory.to_dict()
	t.eq(server.cmd_dismantle(403, id).get("reason"), "no_space",
		"full backpack cannot force a partial refund")
	t.eq(rejoined.inventory.to_dict(), snapshot,
		"failed salvage leaves backpack untouched")
	t.check(server.barricades.has(id) and world.dynamic_blockers.has(id),
		"failed refund cannot delete structure or its physical blocker")

	t.current = "partial salvage and no duplication"
	rejoined.inventory = Inventory.new()
	var dismantled: Dictionary = server.cmd_dismantle(403, id)
	t.check(bool(dismantled.get("ok", false)), "rejoined account dismantles its wall")
	t.eq(rejoined.inventory.count("wood_1"), 2, "half of spent wood returned")
	t.eq(rejoined.inventory.count("stone_1"), 1, "half of spent stone returned")
	t.check(not server.barricades.has(id) and not world.dynamic_blockers.has(id),
		"dismantling deletes wall and collision together")
	t.check(Movement._is_free(world, spot), "old building footprint becomes walkable")
	t.eq(server.cmd_dismantle(403, id).get("reason"), "no_structure",
		"repeated dismantle cannot duplicate resources")
	t.eq(rejoined.inventory.count("wood_1"), 2, "no duplicated salvage")
	t.eq(server.snapshot_for(403).get("barricades", []).size(), 0,
		"removed wall is absent from replicated snapshots")

	t.current = "damaged structures yield less"
	rejoined.inventory.add("wood_1", 8)
	rejoined.inventory.add("stone_1", 4)
	var rebuilt: Dictionary = server.cmd_build(403, spot.x, spot.y)
	t.check(bool(rebuilt.get("ok", false)), "can build again on freed footprint")
	if rebuilt.get("ok", false):
		var second_id: int = int(rebuilt["id"])
		t.check(not server.damage_barricade(second_id, 90.0), "wall remains standing")
		var before_wood: int = rejoined.inventory.count("wood_1")
		var before_stone: int = rejoined.inventory.count("stone_1")
		var second: Dictionary = server.cmd_dismantle(403, second_id)
		t.check(bool(second.get("ok", false)), "damaged wall can be dismantled")
		t.eq(rejoined.inventory.count("wood_1"), before_wood + 1,
			"damaged wall returns only one wood")
		t.eq(rejoined.inventory.count("stone_1"), before_stone,
			"damaged wall returns no stone")
	t.eq(Structures.salvage_for_health(-1.0), {}, "destroyed wall yields nothing")
