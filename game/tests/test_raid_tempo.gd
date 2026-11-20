extends RefCounted
## Raid tempo rewards come from the server's true boss kill, not an RPC.
const RaidTempo = preload("res://scripts/shared/raid_tempo.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


class FlatWorld:
	extends RefCounted
	var world_seed: int = 721
	func zone_at(x: float, _z: float) -> int:
		return 2 if x > 100.0 else 0
	func is_safe(x: float, _z: float) -> bool:
		return x <= 100.0
	func is_water(_x: float, _z: float) -> bool:
		return false
	func height_at(_x: float, _z: float) -> float:
		return 3.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


func _finish_boss(t, elapsed: float, expected_rank: String) -> void:
	var world := FlatWorld.new()
	var sim := GameServer.new(world, 721)
	var fighter = sim.add_player(301, "Tempo Scout")
	fighter.position = Vector3(200.0, 3.0, 200.0)
	var boss_id: int = sim.new_id()
	var boss := Zombie.new(boss_id, "brute", Vector3(215.0, 3.0, 200.0), -1)
	RaidEncounter.empower(boss)
	sim.zombies[boss_id] = boss
	sim.raid_boss_id = boss_id
	sim.raid_started_at = 100.0
	sim.time = sim.raid_started_at + elapsed
	var natural_rng := RandomNumberGenerator.new()
	natural_rng.seed = WorldGen.mix(boss_id, int(sim.time * 10.0), world.world_seed, 5)
	var natural_loot: Dictionary = Combat.zombie_loot("brute", 2, natural_rng)
	var base_boss_loot: Dictionary = RaidEncounter.treasure(2)
	var extra: Dictionary = RaidTempo.bonus(2, elapsed)
	sim._damage_target(fighter, {"kind": "zombie", "id": boss_id}, 2000.0)
	t.eq(sim.raid_boss_id, -1, "confirmed boss kill clears encounter")
	t.eq(sim.bags.size(), 1, "one real shared boss chest")
	if sim.bags.size() != 1:
		return
	var bag: Dictionary = sim.bags.values()[0]
	var items: Dictionary = bag["items"]
	t.eq(int(items.get("silver", 0)), int(natural_loot.get("silver", 0))
		+ int(base_boss_loot.get("silver", 0)) + int(extra.get("silver", 0)),
		"silver contains exactly the bonus for the confirmed tempo")
	t.eq(int(items.get("infected_core", 0)), int(natural_loot.get("infected_core", 0))
		+ int(base_boss_loot.get("infected_core", 0)) + int(extra.get("infected_core", 0)),
		"rare resource reward belongs to the single public loot bag")
	var defeats: Array = sim.events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == "raid_defeated")
	t.eq(defeats.size(), 1, "one defeat announcement")
	if defeats.size() == 1:
		t.eq(str(defeats[0].get("tempo_rank", "")), expected_rank,
			"public finish tier equals the server clock")
	sim._damage_target(fighter, {"kind": "zombie", "id": boss_id}, 2000.0)
	t.eq(sim.bags.size(), 1, "repeat damage never duplicates rewards")


func run(t) -> void:
	t.current = "raid time bonus eligibility and tier boundaries"
	t.eq(RaidTempo.rank(0.0), "gold", "instant valid completion counts as gold")
	t.eq(RaidTempo.rank(90.0), "gold", "exact gold boundary is included")
	t.eq(RaidTempo.rank(90.001), "silver", "after gold boundary becomes silver")
	t.eq(RaidTempo.rank(150.0), "silver", "exact silver boundary included")
	t.eq(RaidTempo.rank(150.001), "", "slow raid is normal loot")
	t.eq(RaidTempo.rank(-1.0), "", "negative server time is invalid")
	t.eq(RaidTempo.rank(NAN), "", "NaN time cannot award")
	t.eq(RaidTempo.rank(INF), "", "infinite time cannot award")
	t.eq(RaidTempo.bonus(0, 10.0), {}, "hub cannot receive a raid bonus")
	t.eq(RaidTempo.bonus(1, 10.0), {}, "yellow zone is excluded")
	t.eq(RaidTempo.bonus(4, 10.0), {}, "invalid region is excluded")
	t.eq(RaidTempo.bonus(2, -1.0), {}, "invalid elapsed duration excluded")
	t.eq(RaidTempo.bonus(2, 180.0), {}, "slow kill retains regular treasure")
	t.eq(RaidTempo.bonus(2, 80.0).get("silver"), 75, "red gold pays bounded silver")
	t.eq(RaidTempo.bonus(3, 80.0).get("silver"), 100, "black gold scales to risk")
	t.eq(RaidTempo.bonus(2, 120.0).get("infected_core"), 1, "silver tier grants one core")
	t.current = "existing GameServer kill, chest, event and replay integration"
	_finish_boss(t, 50.0, "gold")
	_finish_boss(t, 120.0, "silver")
	_finish_boss(t, 180.0, "")
