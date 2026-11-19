extends RefCounted
## Authoritative T1-T4 base upgrades. Tests the real server and backward-
## compatible dedicated-world snapshots, never a simulated client trust path.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")
const BarricadeTests = preload("res://tests/test_barricades.gd")


func run(t) -> void:
	var world := WorldGen.new(214)
	var server = GameServer.new(world, 314)
	var pos: Vector2 = BarricadeTests.new()._find_place(world)
	t.current = "tier definitions and existing resource registry"
	t.check(pos != Vector2.ZERO, "valid position outside safe hub exists")
	if pos == Vector2.ZERO:
		return
	t.eq(Structures.max_health(1), 120.0, "existing T1 durability retained")
	t.eq(Structures.max_health(2), 240.0, "T2 reinforcement doubles base durability")
	t.eq(Structures.max_health(3), 400.0, "T3 reinforced metal durability")
	t.eq(Structures.max_health(4), 600.0, "T4 hardened defense durability")
	t.eq(Structures.max_health(5), 0.0, "invalid tier never silently gains durability")
	t.eq(Structures.damage_factor(4), 0.5, "T4 absorbs half of raw damage")
	t.eq(Structures.upgrade_cost(2), {"plank_2": 4, "stone_2": 2}, "T2 costs existing T2 materials")
	t.eq(Structures.upgrade_cost(3), {"plank_3": 4, "bar_3": 3}, "T3 consumes refined T3 bars")
	t.eq(Structures.upgrade_cost(4), {"plank_4": 6, "bar_4": 4}, "T4 consumes refined T4 bars")
	t.eq(Structures.repair_cost(3), {"bar_3": 1}, "T3 repair consumes bar T3")

	var owner = server.add_player(41, "Owner", "account-base-owner")
	var origin: Vector2 = pos + Vector2(-2.8, 0.0)
	owner.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	owner.inventory.add("wood_1", 4)
	owner.inventory.add("stone_1", 2)
	t.current = "build T1, validate all failed upgrade cases"
	var built: Dictionary = server.cmd_build(41, pos.x, pos.y)
	t.check(bool(built.get("ok", false)), "account owner builds a real T1 wall")
	if not built.get("ok", false):
		return
	var id: int = int(built["id"])
	t.eq(Structures.tier_of(server.barricades[id]), 1, "new barrier defaults to T1")
	t.eq(server.cmd_upgrade(999, id).get("reason"), "dead", "unknown client cannot upgrade")
	t.eq(server.cmd_upgrade(41, id + 1000).get("reason"), "no_structure", "invalid structure ID rejected")
	var intruder = server.add_player(42, "Intruder", "account-stranger")
	intruder.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	intruder.inventory.add("plank_2", 4)
	intruder.inventory.add("stone_2", 2)
	t.eq(server.cmd_upgrade(42, id).get("reason"), "not_owner", "other account cannot upgrade owner's walls")
	t.eq(server.cmd_upgrade(41, id).get("reason"), "missing_materials", "insufficient rare materials rejected")
	t.eq(server.barricades[id]["tier"], 1, "failed upgrade preserves T1")
	owner.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	t.eq(server.cmd_upgrade(41, id).get("reason"), "out_of_range", "distance to wall is checked on server")
	owner.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	owner.inventory.add("plank_2", 5)
	owner.inventory.add("stone_2", 2)
	var start_planks: int = owner.inventory.count("plank_2")
	var start_stone: int = owner.inventory.count("stone_2")

	t.current = "upgrade with exact preservation of damage ratio"
	t.check(not server.damage_barricade(id, 20.0), "partial damage does not break T1")
	t.near(float(server.barricades[id]["hp"]), 100.0, 0.001, "T1 damage applied unchanged")
	var result: Dictionary = server.cmd_upgrade(41, id)
	t.check(bool(result.get("ok", false)), "valid upgrade to T2 is accepted")
	t.eq(result.get("tier"), 2, "server returns authoritative new tier")
	t.near(float(server.barricades[id]["hp"]), 200.0, 0.001, "upgrade preserves fraction, no free repair")
	t.eq(owner.inventory.count("plank_2"), start_planks - 4, "T2 upgrade consumes exactly 4 planks")
	t.eq(owner.inventory.count("stone_2"), start_stone - 2, "T2 upgrade consumes exactly 2 stones")
	t.eq(server.cmd_upgrade(41, id).get("reason"), "missing_materials", "cannot skip ahead without T3 materials")
	t.eq(owner.inventory.count("plank_2"), start_planks - 4, "rejected upgrade never charges leftovers")
	t.check(not server.damage_barricade(id, 10.0), "T2 resists incoming attack")
	t.near(float(server.barricades[id]["hp"]), 191.8, 0.001, "T2 0.82 damage multiplier")
	t.eq(server.cmd_repair(41, id).get("reason"), "missing_materials", "T1 repair wood cannot repair T2")
	t.check(not server.barricades[id].is_empty(), "rejected repair does not destroy defense")
	owner.inventory.add("plank_2", 1)
	t.check(bool(server.cmd_repair(41, id).get("ok", false)), "T2 repair with T2 material accepted")
	t.near(float(server.barricades[id]["hp"]), 240.0, 0.001, "T2 repair capped at correct tier max HP")

	t.current = "T3 and T4 tier materials, repair and damage resistance"
	owner.inventory.add("plank_3", 4)
	owner.inventory.add("bar_3", 4)
	t.check(bool(server.cmd_upgrade(41, id).get("ok", false)), "T3 upgrade uses refined steel")
	t.eq(Structures.tier_of(server.barricades[id]), 3, "T3 set in authoritative wall")
	t.near(float(server.barricades[id]["hp"]), 400.0, 0.001, "fully repaired T2 upgrades to full T3")
	t.check(not server.damage_barricade(id, 10.0), "T3 survives 10 raw damage")
	t.near(float(server.barricades[id]["hp"]), 393.4, 0.001, "T3 applies reduced damage")
	t.check(bool(server.cmd_repair(41, id).get("ok", false)), "T3 repair costs one remaining T3 bar")
	t.eq(owner.inventory.count("bar_3"), 0, "T3 upgrade and repair consume exact crafted bars")
	owner.inventory.add("plank_4", 6)
	owner.inventory.add("bar_4", 5)
	t.check(bool(server.cmd_upgrade(41, id).get("ok", false)), "T4 upgrade succeeds")
	t.eq(server.barricades[id]["tier"], 4, "T4 persisted in live server")
	t.near(float(server.barricades[id]["hp"]), 600.0, 0.001, "T4 durability max")
	t.check(not server.damage_barricade(id, 10.0), "T4 survives an attack")
	t.near(float(server.barricades[id]["hp"]), 595.0, 0.001, "T4 halves incoming damage")
	t.check(bool(server.cmd_repair(41, id).get("ok", false)), "T4 repairs with hardened T4 material")
	t.eq(owner.inventory.count("bar_4"), 0, "T4 upgrade + repair consumes all T4 bars")
	t.eq(server.cmd_upgrade(41, id).get("reason"), "max_tier", "T4 cannot be upgraded beyond cap")
	t.eq(owner.inventory.count("plank_4"), 0, "no further rare materials spent at max tier")

	t.current = "network visibility without leaking account credentials"
	var snapshots: Dictionary = server.snapshot_for(41)
	t.eq(snapshots["barricades"].size(), 1, "nearby owner receives upgraded barricade")
	t.eq(snapshots["barricades"][0]["tier"], 4, "snapshot includes exact tier")
	t.eq(snapshots["barricades"][0]["max_hp"], 600.0, "snapshot includes correct durability max")
	t.check(not snapshots["barricades"][0].has("owner_account"), "public snapshot omits private account IDs")
	intruder.position = Vector3(1000.0, world.height_at(1000.0, 0.0), 0.0)
	t.eq(server.snapshot_for(42)["barricades"].size(), 0, "interest filtering still excludes distant wall")

	t.current = "old and new world snapshot compatibility"
	var checkpoint: Dictionary = Persist.capture(server)
	t.eq(checkpoint["barricades"][0]["tier"], 4, "new persistence captures T4 tier")
	t.check(not Persist.validate(checkpoint, GameServer.new(WorldGen.new(214), 315)).is_empty(), "new format passes validation")
	var reboot = GameServer.new(WorldGen.new(214), 315)
	t.check(Persist.restore(reboot, JSON.parse_string(JSON.stringify(checkpoint))), "JSON roundtrip restores upgraded barricade")
	t.eq(reboot.barricades[id]["tier"], 4, "restored structure stays T4")
	t.near(float(reboot.barricades[id]["hp"]), 600.0, 0.001, "restored T4 durability retained")
	var bad: Dictionary = checkpoint.duplicate(true)
	bad["barricades"][0]["tier"] = 5
	t.check(not Persist.restore(GameServer.new(WorldGen.new(214), 315), bad), "save with impossible T5 refused")
	bad = checkpoint.duplicate(true)
	bad["barricades"][0]["tier"] = 1
	t.check(not Persist.restore(GameServer.new(WorldGen.new(214), 315), bad), "T4 HP cannot be forged into T1")
	bad = checkpoint.duplicate(true)
	bad["barricades"][0]["tier"] = 2.5
	t.check(not Persist.restore(GameServer.new(WorldGen.new(214), 315), bad), "fractional tier rejected")
	var old_record: Dictionary = checkpoint.duplicate(true)
	old_record["barricades"][0].erase("tier")
	old_record["barricades"][0]["hp"] = 100.0
	var migrated = GameServer.new(WorldGen.new(214), 315)
	t.check(Persist.restore(migrated, JSON.parse_string(JSON.stringify(old_record))), "legacy T1 checkpoint loads without tier key")
	t.eq(Structures.tier_of(migrated.barricades[id]), 1, "legacy walls are interpreted as T1")
	t.near(float(migrated.barricades[id]["hp"]), 100.0, 0.001, "legacy durability preserved exactly")

	t.current = "dismantling never refunds high-tier materials"
	var dismantled: Dictionary = server.cmd_dismantle(41, id)
	t.check(bool(dismantled.get("ok", false)), "owner dismantles T4")
	t.eq(dismantled.get("salvage", {}), Structures.SALVAGE_GOOD, "only low-tier salvage recovered")
	t.eq(owner.inventory.count("plank_4"), 0, "dismantling cannot mint T4 planks")
	t.eq(owner.inventory.count("bar_4"), 0, "dismantling cannot mint T4 bars")
	t.check(not server.barricades.has(id) and not world.dynamic_blockers.has(id), "dismantled T4 removes physics blocker")
