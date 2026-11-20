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
