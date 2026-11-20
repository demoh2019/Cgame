extends RefCounted
## Integration tests for raid guard resistance and interest-filtered feedback.
const RaidWard = preload("res://scripts/shared/raid_ward.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "only living server-owned reinforcements guard a raid boss"
	var world := WorldGen.new(67)
	var sim := GameServer.new(world, 67)
	var fighter = sim.add_player(801, "Raider")
	var witness = sim.add_player(802, "Party Witness")
	var distant = sim.add_player(803, "Far Away")
	fighter.position = _at(world, 851.0, 0.0)
	witness.position = _at(world, 850.0, 3.0)
	distant.position = _at(world, 2500.0, 0.0)
	var boss := Zombie.new(sim.new_id(), "brute", _at(world, 853.0, 0.0), -1)
	RaidEncounter.empower(boss)
	sim.zombies[boss.id] = boss
	sim.raid_boss_id = boss.id
	sim.raid_started_at = 100.0
	sim.raid_next_slam_at = 1000.0
	sim.time = 110.0
	var first := Zombie.new(sim.new_id(), "runner", _at(world, 860.0, 0.0), -1)
	var second := Zombie.new(sim.new_id(), "brute", _at(world, 860.0, 3.0), -1)
	sim.zombies[first.id] = first
	sim.zombies[second.id] = second
	sim.raid_minions.append(first.id)
	sim.raid_minions.append(second.id)
	t.eq(RaidWard.living_count(boss, sim.raid_boss_id, sim.raid_minions,
		sim.zombies), 2, "two alive guards provide resistance")
	t.eq(RaidWard.reduction_percent(2), 24, "two guards protect by 24 percent")
	t.eq(RaidWard.reduction_percent(100), 24, "protection is always bounded")
	t.eq(RaidWard.reduction_percent(-5), 0, "negative counts cannot strengthen")
	t.near(RaidWard.absorb(100.0, boss, sim.raid_boss_id, sim.raid_minions,
		sim.zombies), 76.0, 0.001, "two guards absorb 24 damage")
	t.near(RaidWard.absorb(100.0, boss, -1, sim.raid_minions,
		sim.zombies), 100.0, 0.001, "wrong boss never gains a ward")
	t.near(RaidWard.absorb(NAN, boss, sim.raid_boss_id, sim.raid_minions,
		sim.zombies), 0.0, 0.001, "NaN attack does not create damage")
	t.near(RaidWard.absorb(-100.0, boss, sim.raid_boss_id, sim.raid_minions,
		sim.zombies), 0.0, 0.001, "negative attack does not create healing")
	var ordinary := Zombie.new(sim.new_id(), "walker", _at(world, 857.0, 4.0))
	sim.zombies[ordinary.id] = ordinary
	t.near(RaidWard.absorb(100.0, ordinary, sim.raid_boss_id,
		sim.raid_minions, sim.zombies), 100.0, 0.001,
		"normal infected never inherit the boss's ward")
	var duplicate_ids: Array[int] = [first.id, first.id, second.id]
	t.eq(RaidWard.living_count(boss, boss.id, duplicate_ids, sim.zombies), 2,
		"duplicate identity cannot fake extra protection")

	t.current = "actual attacks, snapshots and guaranteed one-time guard events"
	var found_boss: bool = false
	for enemy in sim.snapshot_for(fighter.id).get("zombies", []):
		if int(enemy.get("id", -1)) == boss.id:
			found_boss = true
			t.eq(int(enemy.get("raid_ward_guards", -1)), 2,
				"nearby snapshot includes guard count")
			t.eq(int(enemy.get("raid_ward_reduction", -1)), 24,
				"nearby snapshot includes server-calculated resistance")
	t.check(found_boss, "raid boss is visible to fighter")
	var distant_boss: bool = false
	for enemy in sim.snapshot_for(distant.id).get("zombies", []):
		if int(enemy.get("id", -1)) == boss.id:
			distant_boss = true
	t.check(not distant_boss, "distant survivor has no raid snapshot")
	var before: float = boss.health
	sim._damage_target(fighter, {"kind": "zombie", "id": boss.id}, 100.0)
	t.near(before - boss.health, 76.0, 0.001,
		"real authoritative boss damage is reduced with two guards")
	sim._damage_target(fighter, {"kind": "zombie", "id": first.id}, 100000.0)
	t.eq(RaidWard.living_count(boss, boss.id, sim.raid_minions, sim.zombies), 1,
		"one guard kill immediately weakens the ward")
	before = boss.health
	sim._damage_target(fighter, {"kind": "zombie", "id": boss.id}, 100.0)
	t.near(before - boss.health, 88.0, 0.001,
		"one living guard absorbs only 12 percent")
	sim._damage_target(fighter, {"kind": "zombie", "id": first.id}, 100000.0)
	sim._damage_target(fighter, {"kind": "zombie", "id": second.id}, 100000.0)
	t.eq(RaidWard.living_count(boss, boss.id, sim.raid_minions, sim.zombies), 0,
		"last guard death removes all resistance")
	before = boss.health
	sim._damage_target(fighter, {"kind": "zombie", "id": boss.id}, 100.0)
	t.near(before - boss.health, 100.0, 0.001,
		"unguarded boss takes full damage again")
	var alerts: Array = sim.events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "raid_ward_changed")
	t.eq(alerts.size(), 2, "dead guard replay cannot duplicate ward alerts")
	if alerts.size() == 2:
		t.eq(int(alerts[0].get("guards", -1)), 1, "first alert reports one guard")
		t.eq(int(alerts[1].get("guards", -1)), 0, "last alert reports broken ward")
		var transport := Net.new()
		transport.role = "server"
		transport.sim = sim
		t.check(transport._event_visible_to(alerts[1], fighter.id),
			"nearby fighter receives the ward broken event")
		t.check(transport._event_visible_to(alerts[1], witness.id),
			"nearby ally receives the ward broken event")
		t.check(not transport._event_visible_to(alerts[1], distant.id),
			"distant survivor cannot receive raid location")
		transport.free()
	t.current = "raid cleanup erases all temporary ward state"
	sim._damage_target(fighter, {"kind": "zombie", "id": boss.id}, 2000.0)
	t.eq(sim.raid_boss_id, -1, "boss victory clears the current raid id")
	t.eq(sim.raid_minions.size(), 0, "victory clears the guard IDs")
	t.eq(RaidWard.living_count(boss, sim.raid_boss_id,
		sim.raid_minions, sim.zombies), 0, "expired raid cannot retain resistance")
