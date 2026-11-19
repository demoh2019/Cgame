extends RefCounted
## Ending a shared campfire early must preserve account ownership and not
## duplicate or refund resources. Only the server may remove active heat.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const BarricadeTests = preload("res://tests/test_barricades.gd")
const Structures = preload("res://scripts/shared/structures.gd")


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func run(t) -> void:
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 65)
	var place: Vector2 = BarricadeTests.new()._find_place(world)
	t.current = "account-owned temporary campfires"
	t.check(place != Vector2.ZERO, "found a dry campsite")
	if place == Vector2.ZERO:
		return
	var start := place + Vector2(-2.8, 0.0)
	var owner = sim.add_player(301, "Builder", "test-account-A")
	owner.position = _at(world, start)
	owner.inventory.add("wood_1", 8)
	owner.inventory.add("stone_1", 3)
	var lit: Dictionary = sim.cmd_light_campfire(301, place.x, place.y)
	t.check(bool(lit.get("ok", false)), "authenticated survivor can light a fire")
	if not bool(lit.get("ok", false)):
		return
	var id: int = int(lit["id"])
	t.check(Structures.can_manage(sim.campfires[id], 301, owner.user_id),
		"account is identified independently of network peer ID")
	t.check(not sim.snapshot_for(301)["campfires"][0].has("owner_account"),
		"account identifier is never replicated to viewers")
	var materials: int = owner.inventory.count("wood_1")

	t.current = "unauthorized extinguish and replay"
	var stranger = sim.add_player(302, "Neighbor", "test-account-B")
	stranger.position = _at(world, place + Vector2(2, 0))
	t.eq(sim.cmd_extinguish_campfire(999, id).get("reason"), "dead",
		"unknown sender cannot extinguish")
	t.eq(sim.cmd_extinguish_campfire(301, -1).get("reason"), "no_fire",
		"unknown fire ID rejected")
	t.eq(sim.cmd_extinguish_campfire(302, id).get("reason"), "not_owner",
		"neighbor cannot extinguish another survivor's fire")
	t.check(sim.campfires.has(id), "unauthorized request leaves active fire")
	t.eq(owner.inventory.count("wood_1"), materials,
		"forged extinguish cannot refund or consume fuel")
	owner.position = _at(world, place + Vector2(30, 0))
	t.eq(sim.cmd_extinguish_campfire(301, id).get("reason"), "out_of_range",
		"owner must be close to the fire")
	t.check(sim.campfires.has(id), "remote attempt leaves heat intact")

	t.current = "reconnect and account ownership"
	sim.remove_player(301)
	var hijacker = sim.add_player(301, "Hijacker", "test-account-B")
	hijacker.position = _at(world, start)
	t.eq(sim.cmd_extinguish_campfire(301, id).get("reason"), "not_owner",
		"recycled peer ID cannot steal authenticated fire")
	sim.remove_player(301)
	var rejoined = sim.add_player(303, "BuilderAgain", "test-account-A")
	rejoined.position = _at(world, place + Vector2(1, 0))
	t.check(bool(sim.cmd_extinguish_campfire(303, id).get("ok", false)),
		"same account on new peer can extinguish its own fire")
	t.check(not sim.campfires.has(id), "server deleted the active heat source")
	t.check(not FieldCampfire.has_warmth(sim.campfires, rejoined.position, sim.time),
		"shared warmth stops immediately when the fire is extinguished")
	t.eq(sim.snapshot_for(303)["campfires"].size(), 0,
		"removed fire no longer appears in network snapshots")
	t.eq(sim.cmd_extinguish_campfire(303, id).get("reason"), "no_fire",
		"extinguish requests cannot replay an already removed entity")
	t.eq(rejoined.inventory.count("wood_1"), 0,
		"no firewood is refunded when the flame is extinguished")
