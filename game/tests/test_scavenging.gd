extends RefCounted
## Regressions: real ruin exploration, danger bonuses, save safety and anti-farming.

const Defs = preload("res://scripts/shared/defs.gd")
const Scavenging = preload("res://scripts/shared/scavenging.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _find_danger_crate(world) -> Dictionary:
	for cx in range(8, 20):
		for cz in range(0, 16):
			var data: Dictionary = world.chunk(Vector2i(cx, cz))
			if int(data["zone"]) >= 2 and not data["crates"].is_empty():
				var crate: Dictionary = data["crates"][0].duplicate(true)
				crate["zone"] = int(data["zone"])
				return crate
	return {}


func run(t) -> void:
	t.current = "scavenging is a capped risk/reward profession"
	t.eq(Scavenging.xp_for_zone(0), 15, "green crate XP")
	t.eq(Scavenging.xp_for_zone(2), 30, "red crate XP")
	t.eq(Scavenging.xp_for_zone(3), 45, "black crate XP")
	t.eq(Scavenging.xp_for_zone(-1), 0, "negative zone is refused")
	t.eq(Scavenging.xp_for_zone(999), 0, "forged zone is refused")
	t.eq(Scavenging.level_for_xp(75), 2, "rank two at 75 XP")
	t.eq(Scavenging.level_for_xp(1000000), Scavenging.MAX_LEVEL, "mastery rank cap")
	var initial := {"scrap": 4, "antibiotics": 1}
	t.eq(Scavenging.enriched_loot(2, 1, initial)["scrap"], 4, "novice earns no bonus")
	t.eq(Scavenging.enriched_loot(1, 5, initial)["scrap"], 4, "safe zone earns no bonus")
	t.eq(Scavenging.enriched_loot(2, 2, initial)["scrap"], 5, "rank two red loot bonus")
	t.eq(Scavenging.enriched_loot(3, 5, initial)["scrap"], 8, "maximum bonus is four scrap")
	t.eq(Scavenging.enriched_loot(3, 5, initial)["antibiotics"], 1, "medicine cannot be multiplied")
	t.eq(initial["scrap"], 4, "enriched loot does not mutate base dictionary")

	t.current = "scavenging persistence is strict, atomic and backward compatible"
	var profession := Progression.new()
	t.eq(profession.scavenging_level(), 1, "starting rank is one")
	t.eq(profession.award_scavenge(2), 30, "red crate awards thirty XP")
	t.eq(profession.award_scavenge(3), 45, "black crate awards forty-five XP")
	t.eq(profession.award_scavenge(-1), 0, "invalid zone cannot grant XP")
	t.eq(profession.scavenging_level(), 2, "seventy-five XP unlocks level two")
	var good: Dictionary = profession.to_dict()
	var restored := Progression.new()
	t.check(restored.load_dict(good), "valid scavenging XP loads")
	for invalid in [INF, NAN, -1, 75.5, 100000001, "75", true]:
		var corrupt: Dictionary = good.duplicate(true)
		corrupt["scavenging"] = invalid
		t.check(not restored.load_dict(corrupt), "forged XP rejected")
		t.eq(restored.scavenging_xp, 75, "rejected XP does not partially overwrite")
	var legacy: Dictionary = good.duplicate(true)
	legacy.erase("scavenging")
	t.check(restored.load_dict(legacy), "older save without scavenging loads")
	t.eq(restored.scavenging_level(), 1, "legacy player starts novice")
	restored.scavenging_xp = Progression.MAX_XP
	t.eq(restored.award_scavenge(3), 0, "saturated XP cannot overflow")

	t.current = "only live server crate grants XP and extra salvage once"
	var world := WorldGen.new(3141)
	var crate: Dictionary = _find_danger_crate(world)
	t.check(not crate.is_empty(), "a real dangerous ruin crate is generated")
	if crate.is_empty():
		return
	var server := GameServer.new(world, 3141)
	var player = server.add_player(910, "Scavenger")
	var x: float = float(crate["x"])
	var z: float = float(crate["z"])
	player.position = Vector3(x - 1.0, world.height_at(x - 1.0, z), z)
	player.progression.scavenging_xp = 75
	var zone: int = int(crate["zone"])
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(int(crate["id"]), int(server.time), world.world_seed, 3)
	var loot: Dictionary = Combat.crate_loot(zone, rng)
	var previous_scrap: int = player.inventory.count("scrap")
	var result: Dictionary = server.cmd_loot(910, int(crate["id"]))
	t.check(result.get("ok", false), "real nearby ruin crate is searchable")
	t.eq(player.inventory.count("scrap") - previous_scrap,
		int(loot.get("scrap", 0)) + 1, "danger bonus is bounded and server generated")
	var expected_xp: int = 75 + Scavenging.xp_for_zone(zone)
	t.eq(player.progression.scavenging_xp, expected_xp, "crate grants exactly one XP award")
	t.eq(server.cmd_loot(910, int(crate["id"])).get("reason", ""), "empty",
		"repeated opening cannot farm loot or XP")
	t.eq(player.progression.scavenging_xp, expected_xp, "repeat opening awards no XP")
	var bag_id: int = server.new_id()
	server.bags[bag_id] = {"id": bag_id, "x": x, "y": player.position.y,
		"z": z, "items": {"silver": 1}, "expires": server.time + 300.0}
	t.check(server.cmd_loot(910, bag_id).get("ok", false), "ordinary loot bags still work")
	t.eq(player.progression.scavenging_xp, expected_xp, "bags never award crate mastery")
	var snapshot: Dictionary = server.snapshot_for(910)
	t.eq(int(snapshot["you"]["scavenging_xp"]), expected_xp, "owner snapshot includes XP")
	t.eq(int(snapshot["you"]["scavenging_level"]), player.progression.scavenging_level(),
		"owner snapshot includes rank")

	t.current = "character save, corrupt data and death preserve earned mastery"
	var saved: Dictionary = server.character_data(player)
	player.progression.scavenging_xp = 0
	t.check(server.apply_character(player, saved), "saved scavenging is restored")
	t.eq(player.progression.scavenging_xp, expected_xp, "saved XP survives reconnect")
	var tampered: Dictionary = saved.duplicate(true)
	tampered["progression"]["scavenging"] = INF
	var hp_before: float = player.survival.health
	t.check(not server.apply_character(player, tampered), "corrupt character is refused")
	t.eq(player.progression.scavenging_xp, expected_xp, "invalid save cannot rewrite XP")
	t.near(player.survival.health, hp_before, 0.001, "invalid save cannot change health")
	player.position = Vector3(700.0, world.height_at(700.0, 700.0), 700.0)
	player.survival.hurt(1000.0)
	server._on_player_death(player, -1)
	server._spawn_player(player)
	t.eq(player.progression.scavenging_xp, expected_xp, "full-loot death retains XP")

	t.current = "sealed compartments require an actual consumable in dangerous ruin crates"
	t.check(Defs.is_item(Scavenging.LOCKPICK_ITEM), "lockpick exists in the item catalog")
	var recipe: Dictionary = Defs.recipes().get(Scavenging.LOCKPICK_ITEM, {})
	t.check(not recipe.is_empty(), "lockpick has a craftable workbench recipe")
	t.eq(str(recipe.get("station", "")), "workbench", "kit is assembled at a bench")
	t.check(Scavenging.can_unlock(2, 1), "red crate with one kit is eligible")
	t.check(Scavenging.can_unlock(3, 1), "black crate with one kit is eligible")
	t.check(not Scavenging.can_unlock(1, 100), "safe-zone crates cannot consume kits")
	t.check(not Scavenging.can_unlock(2, 0), "without a kit there is no reward")
	t.check(not Scavenging.can_unlock(999, 1), "forged zone cannot unlock")
	var sealed_rng := RandomNumberGenerator.new()
	sealed_rng.seed = 3141
	t.check(Scavenging.sealed_compartment_loot(1, sealed_rng).is_empty(), "safe tier cannot roll loot")
	for dangerous_zone in [2, 3]:
		var prize: Dictionary = Scavenging.sealed_compartment_loot(dangerous_zone, sealed_rng)
		t.check(int(prize.get("scrap", 0)) >= 2 and int(prize.get("scrap", 0)) <= 4,
			"extra scrap has a fixed limit")
		t.check(int(prize.get("bar_%d" % (dangerous_zone + 1), 0)) >= 1 and
			int(prize.get("bar_%d" % (dangerous_zone + 1), 0)) <= 2,
			"only materials matching the zone are created")
		for item_id in prize:
			t.check(Defs.is_item(str(item_id)), "all extra loot IDs exist")
			t.check(int(prize[item_id]) <= Defs.stack_size(str(item_id)), "all extra counts fit one stack")

	var lock_server := GameServer.new(world, 3141)
	var locksmith = lock_server.add_player(911, "Locksmith")
	t.eq(locksmith.inventory.add(Scavenging.LOCKPICK_ITEM, 1), 0, "one kit fits inventory")
	locksmith.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	t.eq(str(lock_server.cmd_loot(911, int(crate["id"])).get("reason", "")),
		"too_far", "the client cannot spend a kit remotely")
	t.eq(locksmith.inventory.count(Scavenging.LOCKPICK_ITEM), 1, "refused search preserves kit")
	locksmith.position = Vector3(x - 1.0, world.height_at(x - 1.0, z), z)
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = WorldGen.mix(int(crate["id"]), int(lock_server.time), world.world_seed, 3)
	var ordinary: Dictionary = Combat.crate_loot(zone, expected_rng)
	var lock_result: Dictionary = lock_server.cmd_loot(911, int(crate["id"]))
	t.check(bool(lock_result.get("ok", false)), "legitimate nearby red/black search works")
	t.eq(locksmith.inventory.count(Scavenging.LOCKPICK_ITEM), 0, "exactly one kit is spent")
	t.check(locksmith.inventory.count("scrap") >= int(ordinary.get("scrap", 0)) + 2,
		"secured cache grants bounded additional salvage")
	t.check(locksmith.inventory.count("bar_%d" % (zone + 1)) >=
		int(ordinary.get("bar_%d" % (zone + 1), 0)) + 1,
		"secured cache grants tier-appropriate metal")
	var once: int = locksmith.inventory.count("scrap")
	t.eq(str(lock_server.cmd_loot(911, int(crate["id"])).get("reason", "")),
		"empty", "opening the same compartment twice is rejected")
	t.eq(locksmith.inventory.count("scrap"), once, "repeat cannot duplicate salvage")
	var unlock_events := 0
	for event in lock_server.drain_events():
		if str(event.get("type", "")) == "lockpick" and int(event.get("peer", -1)) == 911:
			unlock_events += 1
	t.eq(unlock_events, 1, "a single verified lockpick event is published")
