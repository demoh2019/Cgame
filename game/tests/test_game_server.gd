extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _run_ticks(server, seconds: float) -> void:
	var steps := int(seconds * Defs.TICK_RATE)
	for i in steps:
		server.tick(1.0 / Defs.TICK_RATE)


func _teleport(server, peer: int, x: float, z: float) -> void:
	server.players[peer].position = Vector3(x, server.world.height_at(x, z), z)


func _find_node(world, kind: String, tier: int, from: Vector2i = Vector2i(2, 2)) -> Dictionary:
	for cx in range(from.x, from.x + 12):
		for cz in range(from.y, from.y + 12):
			for node in world.chunk(Vector2i(cx, cz))["nodes"]:
				if node["kind"] == kind and node["tier"] == tier and not world.is_water(node["x"], node["z"]):
					return node
	return {}


func run(t) -> void:
	var world := WorldGen.new(42)

	t.current = "join and spawn"
	var server := GameServer.new(world, 1)
	var p = server.add_player(10, "  Alice  ")
	t.eq(p.name, "Alice", "names are trimmed")
	t.check(server.world.is_safe(p.position.x, p.position.z), "players spawn inside the hub")
	t.eq(p.inventory.count("canned_food"), 2, "starter kit: food")
	t.eq(p.inventory.count("bandage"), 2, "starter kit: bandages")
	var named := server.add_player(11, "")
	t.check(named.name != "", "an empty name gets a default")
	var long_name = server.add_player(12, "x".repeat(100))
	t.eq(long_name.name.length(), GameServer.MAX_NAME_LENGTH, "names are capped")
	server.remove_player(11)
	server.remove_player(12)
	t.check(not server.players.has(11), "a player can leave")

	t.current = "movement budget"
	_teleport(server, 10, 20.0, 0.0)
	var before: Vector3 = server.players[10].position
	_run_ticks(server, 1.0)
	var seq := 0
	# A cheating client claims to move for a very long time in one go.
	seq += 1
	server.submit_input(10, seq, 1.0, 0.0, false, 0.0, 10.0)
	var after: Vector3 = server.players[10].position
	t.check(after.x - before.x <= Defs.WALK_SPEED * 0.1 + 0.01, "one input cannot move more than the clamp (%f)" % (after.x - before.x))
	# Sustained cheating: inputs claiming 100 ms every 10 ms of real time.
	_teleport(server, 10, 20.0, 0.0)
	before = server.players[10].position
	for i in 100:
		seq += 1
		server.submit_input(10, seq, 1.0, 0.0, true, 0.0, 0.1)
		server.tick(0.01)
	var moved: float = server.players[10].position.x - before.x
	# Real time allows 1 s of movement plus the 0.25 s of banked time that absorbs network jitter.
	t.check(moved <= Defs.SPRINT_SPEED * 1.25 + 0.2, "speed hacking is limited to real time (moved %f in 1 s)" % moved)
	t.check(moved > 1.0, "but honest movement works")
	var last: int = server.players[10].last_input_seq
	server.submit_input(10, last - 5, 1.0, 0.0, false, 0.0, 0.05)
	t.eq(server.players[10].last_input_seq, last, "old inputs are ignored")
	server.submit_input(10, last + 1, NAN, 0.0, false, 0.0, 0.05)
	t.eq(server.players[10].last_input_seq, last, "NaN inputs are ignored")

	t.current = "gathering"
	var tree := _find_node(world, "tree", 1)
	t.check(not tree.is_empty(), "found a tier 1 tree")
	_teleport(server, 10, tree["x"] - 1.5, tree["z"])
	var far := server.cmd_gather(10, tree["id"])
	t.check(far["ok"], "gathering a tier 1 tree with bare hands works: %s" % str(far))
	_run_ticks(server, 12.0)
	t.check(server.players[10].inventory.count("wood_1") >= 4, "wood was gathered (%d)" % server.players[10].inventory.count("wood_1"))
	t.check(server.depleted.has(tree["id"]), "the tree is depleted")
	t.eq(server.cmd_gather(10, tree["id"])["reason"], "depleted", "a depleted tree cannot be gathered")
	server.time += 1000.0
	server.tick(0.05)
	t.check(not server.depleted.has(tree["id"]), "the tree grows back")
	_teleport(server, 10, tree["x"] + 40.0, tree["z"])
	t.eq(server.cmd_gather(10, tree["id"])["reason"], "too_far", "cannot gather from far away")
	t.eq(server.cmd_gather(10, 12345)["reason"], "no_such_node", "unknown node")

	t.current = "tools gate higher tiers"
	var tier2 := _find_node(world, "tree", 2, Vector2i(6, 6))
	if tier2.is_empty():
		tier2 = _find_node(world, "tree", 2, Vector2i(-14, -14))
	t.check(not tier2.is_empty(), "found a tier 2 tree")
	if not tier2.is_empty():
		_teleport(server, 10, tier2["x"] - 1.5, tier2["z"])
		t.eq(server.cmd_gather(10, tier2["id"])["reason"], "need_tool", "a tier 2 tree needs a tool")
		server.players[10].inventory.add("axe_2", 1)
		t.eq(server.cmd_gather(10, tier2["id"])["reason"], "need_skill", "tool alone does not bypass profession levels")
		server.players[10].progression.award_gather("wood", 1, 13)
		var good := server.cmd_gather(10, tier2["id"])
		t.check(good["ok"], "an axe of the right tier works")
		var hands := server.cmd_gather(10, tier2["id"])
		t.check(good["seconds"] < 3.0, "a tool is faster than hands (%f s)" % good["seconds"])
		server.players[10].action = {}
		server.players[10].inventory.remove("axe_2", 1)
		server.players[10].inventory.add("axe_1", 1)
		t.eq(server.cmd_gather(10, tier2["id"])["reason"], "need_tool", "a tier 1 axe cannot cut a tier 2 tree")

	t.current = "walking away cancels"
	var tree2 := _find_node(world, "tree", 1, Vector2i(3, 3))
	_teleport(server, 10, tree2["x"] - 1.5, tree2["z"])
	server.cmd_gather(10, tree2["id"])
	t.check(not server.players[10].action.is_empty(), "gathering started")
	_run_ticks(server, 0.3)
	_teleport(server, 10, tree2["x"] - 3.3, tree2["z"])
	_run_ticks(server, 0.2)
	seq += 1
	server.submit_input(10, seq + 1000, -1.0, 0.0, false, 0.0, 0.05)
	t.check(server.players[10].action.is_empty(), "moving away stops gathering")

	t.current = "crafting"
	var crafter := server.add_player(20, "Crafter")
	crafter.inventory.add("wood_1", 20)
	crafter.inventory.add("stone_1", 4)
	_teleport(server, 20, 100.0, 100.0)
	t.eq(server.cmd_craft(20, "plank_1", 2)["reason"], "no_station", "crafting needs the workbench")
	_teleport(server, 20, GameServer.WORKBENCH_POSITION.x + 2.0, GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(20, "plank_1", 4)["ok"], "planks at the workbench")
	t.check(server.cmd_craft(20, "axe_1")["ok"], "an axe")
	t.eq(crafter.inventory.count("axe_1"), 1, "the axe exists")
	t.eq(server.cmd_craft(20, "nonsense")["reason"], "unknown_recipe", "unknown recipe")
	t.eq(server.cmd_craft(20, "club_1", 9999)["reason"], "missing_inputs", "huge counts are clamped and refused")

	t.current = "using items"
	crafter.survival.hurt(50.0)
	crafter.survival.hunger = 30.0
	crafter.survival.thirst = 30.0
	t.check(server.cmd_use(20, "bandage")["ok"], "use a bandage")
	t.check(crafter.survival.health > 50.0, "it healed")
	t.check(server.cmd_use(20, "canned_food")["ok"], "eat")
	t.check(crafter.survival.hunger > 60.0, "it fed")
	t.check(server.cmd_use(20, "water_bottle")["ok"], "drink")
	t.eq(server.cmd_use(20, "pistol")["reason"], "not_carried", "cannot use what is not carried")
	t.eq(server.cmd_use(20, "plank_1")["reason"], "not_usable", "planks are not usable")
	crafter.inventory.add("club_1", 1)
	t.check(server.cmd_use(20, "club_1")["ok"], "equip a club")
	t.eq(crafter.inventory.weapon, "club_1", "weapon is equipped")

	t.current = "combat against zombies"
	var fighter := server.add_player(30, "Fighter")
	fighter.inventory.add("club_2", 1)
	fighter.inventory.equip("club_2")
	_teleport(server, 30, 200.0, 200.0)
	var zombie := preload("res://scripts/shared/zombie.gd").new(server.new_id(), "walker", Vector3(201.5, world.height_at(201.5, 200.0), 200.0))
	server.zombies[zombie.id] = zombie
	var miss := server.cmd_attack(30, -1.0, 0.0)
	t.check(miss["ok"] and not miss["hit"], "swinging away from the zombie misses")
	_run_ticks(server, 1.0)
	var swing := server.cmd_attack(30, 1.0, 0.0)
	t.check(swing["ok"] and swing["hit"], "swinging at it hits")
	t.check(zombie.health < 45.0, "it took damage")
	t.eq(server.cmd_attack(30, 1.0, 0.0)["reason"], "cooldown", "attacks have a cooldown")
	var kills_before: int = fighter.kills
	for i in 6:
		_run_ticks(server, 1.0)
		zombie.position = Vector3(201.5, world.height_at(201.5, 200.0), 200.0)
		fighter.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
		fighter.survival.health = 100.0
		if not zombie.is_alive():
			break
		server.cmd_attack(30, 1.0, 0.0)
	t.check(not zombie.is_alive(), "the zombie dies")
	t.eq(fighter.kills, kills_before + 1, "the kill is counted")
	t.check(server.bags.size() >= 1, "the zombie dropped a bag")

	t.current = "looting a bag"
	var bag_id: int = server.bags.keys()[0]
	var bag: Dictionary = server.bags[bag_id]
	_teleport(server, 30, bag["x"] + 5.0, bag["z"])
	t.eq(server.cmd_loot(30, bag_id)["reason"], "too_far", "too far to loot")
	_teleport(server, 30, bag["x"] + 1.0, bag["z"])
	var silver_before: int = fighter.inventory.count("silver")
	t.check(server.cmd_loot(30, bag_id)["ok"], "looting")
	t.check(fighter.inventory.count("silver") > silver_before, "silver was looted")
	t.check(not server.bags.has(bag_id), "an empty bag disappears")
	t.eq(server.cmd_loot(30, 99999)["reason"], "nothing_there", "nothing there")

	t.current = "pistol and ammo"
	fighter.inventory.add("pistol", 1)
	fighter.inventory.equip("pistol")
	var target := preload("res://scripts/shared/zombie.gd").new(server.new_id(), "brute", Vector3(215.0, world.height_at(215.0, 200.0), 200.0))
	server.zombies[target.id] = target
	_teleport(server, 30, 200.0, 200.0)
	_run_ticks(server, 1.0)
	var dry := server.cmd_attack(30, 1.0, 0.0)
	t.eq(dry["reason"], "no_ammo", "a pistol without ammo does not fire")
	fighter.inventory.add("ammo_9mm", 10)
	_run_ticks(server, 1.0)
	var shot := server.cmd_attack(30, 1.0, 0.0)
	t.check(shot["ok"] and shot["hit"], "a pistol hits a target 15 m away")
	t.eq(fighter.inventory.count("ammo_9mm"), 9, "a bullet is consumed")
	t.near(target.health, 170.0 - 22.0, 0.0001, "pistol damage")
	_run_ticks(server, 1.0)
	var wide := server.cmd_attack(30, 1.0, 0.4)
	t.check(wide["ok"] and not wide["hit"], "a shot that passes wide misses")

	t.current = "pvp and the safe zone"
	var duelist := server.add_player(40, "Duelist")
	var victim := server.add_player(41, "Victim")
	duelist.inventory.add("club_3", 1)
	duelist.inventory.equip("club_3")
	_teleport(server, 40, 5.0, 5.0)
	_teleport(server, 41, 6.0, 5.0)
	_run_ticks(server, 1.0)
	var safe_swing := server.cmd_attack(40, 1.0, 0.0)
	t.check(safe_swing["ok"] and not safe_swing["hit"], "no PvP inside the hub")
	t.near(victim.survival.health, 100.0, 0.0001, "the victim is unharmed")
	_teleport(server, 40, 300.0, 300.0)
	_teleport(server, 41, 301.0, 300.0)
	victim.inventory.add("silver", 77)
	victim.inventory.add("club_1", 1)
	victim.inventory.equip("club_1")
	for i in 20:
		_run_ticks(server, 1.0)
		if not victim.survival.alive:
			break
		_teleport(server, 40, 300.0, 300.0)
		_teleport(server, 41, 301.0, 300.0)
		server.cmd_attack(40, 1.0, 0.0)
	t.check(not victim.survival.alive, "outside the hub players can be killed")
	t.eq(victim.deaths, 1, "death counted")
	t.eq(duelist.kills, 1, "kill counted")
	t.eq(victim.inventory.count("silver"), 0, "full loot: the victim's inventory is empty")
	t.eq(victim.inventory.weapon, "", "and their equipment is gone")
	var dropped := false
	for b in server.bags.values():
		if b["items"].get("silver", 0) == 77 and b["items"].has("club_1"):
			dropped = true
	t.check(dropped, "everything dropped in a bag where they died")
	_run_ticks(server, Defs.RESPAWN_SECONDS + 0.5)
	t.check(victim.survival.alive, "the victim respawns")
	t.check(world.is_safe(victim.position.x, victim.position.z), "in the hub")
	t.eq(victim.inventory.count("canned_food"), 2, "with a fresh starter kit")

	t.current = "zombie population"
	var pop := GameServer.new(world, 2)
	pop.add_player(50, "Walker")
	# Go where the ruins are and let the world populate.
	var site := Vector2.ZERO
	for cx in range(8, 30):
		for cz in range(8, 30):
			var data := world.chunk(Vector2i(cx, cz))
			if data["ruin"] and site == Vector2.ZERO:
				site = WorldGen.cell_origin(Vector2i(cx, cz)) + Vector2.ONE * 32.0
	t.check(site != Vector2.ZERO, "found a ruin")
	_teleport(pop, 50, site.x - 55.0, site.y)
	_run_ticks(pop, 2.0)
	t.check(pop.zombies.size() > 0, "zombies appear near a ruin (%d)" % pop.zombies.size())
	_teleport(pop, 50, 0.0, 0.0)
	_run_ticks(pop, 4.0)
	t.eq(pop.zombies.size(), 0, "and go to sleep when the player leaves")
	for z in pop.zombies.values():
		t.check(WorldGen.cell_of(z.position.x, z.position.z) != Vector2i.ZERO, "no zombie in the hub")

	t.current = "snapshots"
	var snap_server := GameServer.new(world, 3)
	snap_server.add_player(60, "A")
	snap_server.add_player(61, "B")
	_teleport(snap_server, 60, 20.0, 20.0)
	_teleport(snap_server, 61, 25.0, 20.0)
	snap_server.add_player(62, "Far")
	_teleport(snap_server, 62, 400.0, 400.0)
	_run_ticks(snap_server, 0.2)
	var snap: Dictionary = snap_server.snapshot_for(60)
	t.check(snap.has("inventory"), "the first snapshot carries the inventory")
	t.eq(snap["players"].size(), 1, "only the nearby player is included")
	t.eq(snap["players"][0]["id"], 61, "it is the close one")
	t.check(not snap_server.snapshot_for(60).has("inventory"), "the inventory is only resent when it changes")
	snap_server.players[60].dirty_inventory = true
	t.check(snap_server.snapshot_for(60).has("inventory"), "...and again once it changed")
	t.near(snap["you"]["x"], snap_server.players[60].position.x, 0.0001, "you are in your own snapshot")
	t.eq(snap_server.snapshot_for(999), {}, "an unknown peer gets nothing")

	t.current = "crates"
	var crate := {}
	var crate_zone := 0
	for cx in range(8, 30):
		for cz in range(8, 30):
			var data := world.chunk(Vector2i(cx, cz))
			if crate.is_empty() and data["crates"].size() > 0:
				crate = data["crates"][0]
				crate_zone = data["zone"]
	t.check(not crate.is_empty(), "found a crate")
	var looter := server.add_player(70, "Looter")
	_teleport(server, 70, crate["x"] - 1.0, crate["z"])
	var before_count := 0
	for slot in looter.inventory.slots:
		if not slot.is_empty():
			before_count += int(slot["count"])
	t.check(server.cmd_loot(70, crate["id"])["ok"], "open a crate")
	var after_count := 0
	for slot in looter.inventory.slots:
		if not slot.is_empty():
			after_count += int(slot["count"])
	t.check(after_count > before_count, "it held something")
	t.eq(server.cmd_loot(70, crate["id"])["reason"], "empty", "an opened crate is empty")
	t.check(server.opened_crates.has(crate["id"]), "it is marked as opened for everyone")
