extends RefCounted
## Blood smell is only emitted by a real death bag, not by client input.
const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "bounded scent and spatial index resist malformed data"
	var sample := {"id": 7, "x": 0.0, "z": 0.0, "expires": 100.0}
	t.check(CorpseScent.mark(sample, 10.0), "legitimate fresh bag can be scented")
	t.near(float(sample["corpse_scent_until"]), 10.0 + CorpseScent.DURATION,
		0.0001, "scent has a bounded lifetime")
	t.check(CorpseScent.active(sample, 10.0), "fresh corpse is active")
	t.check(not CorpseScent.active(sample, 10.0 + CorpseScent.DURATION),
		"exact expiry removes scent before world cleanup")
	t.check(not CorpseScent.mark({"id": 6, "x": NAN, "z": 0, "expires": 50}, 0.0),
		"nonfinite coordinates are rejected")
	t.check(not CorpseScent.mark({"x": 0, "z": 0, "expires": 50}, 0.0),
		"no fabricated bag without a world ID")
	t.check(CorpseScent.buckets({7: sample}, NAN).is_empty(),
		"invalid time cannot index a blood trail")
	t.check(CorpseScent.closest({}, Vector3.INF, 10.0).is_empty(),
		"invalid infected positions cannot find a corpse")
	var a := {"id": 9, "x": 10.0, "z": 0.0, "expires": 100.0}
	var b := {"id": 3, "x": -10.0, "z": 0.0, "expires": 100.0}
	t.check(CorpseScent.mark(a, 5.0) and CorpseScent.mark(b, 5.0),
		"two corpse cues have finite positions")
	var index: Dictionary = CorpseScent.buckets({9: a, 3: b}, 5.0)
	t.eq(CorpseScent.closest(index, Vector3.ZERO, 5.0).get("id", -1), 3,
		"equal-distance scent traces use stable ID order")
	t.check(CorpseScent.closest(index, Vector3(100, 0, 0), 5.0).is_empty(),
		"outside range there is no scent tracking")
	t.check(CorpseScent.closest(index, Vector3.ZERO, 46.0).is_empty(),
		"cached index cannot revive an expired scent")

	t.current = "confirmed zombie kills yield smelling but private loot"
	var world := WorldGen.new(841)
	var sim := GameServer.new(world, 841)
	var site: Vector3 = _at(world, 210, 145)
	var killer = sim.add_player(51, "Hunter")
	killer.position = site
	t.check(not world.is_safe(site.x, site.z), "death is outside the hub")
	var plain_id: int = sim._make_bag(site, {"silver": 1})
	t.check(not CorpseScent.active(sim.bags[plain_id], sim.time),
		"ordinary placed loot does not smell")
	var dead := Zombie.new(sim.new_id(), "walker", site, -1)
	sim.zombies[dead.id] = dead
	dead.take_damage(10000.0)
	sim._on_zombie_death(dead, killer)
	var body_id: int = -1
	for id in sim.bags:
		if int(id) != plain_id:
			body_id = int(id)
	t.check(body_id >= 0, "the kill generated a normal reward bag")
	if body_id < 0:
		return
	t.check(CorpseScent.active(sim.bags[body_id], sim.time),
		"only the confirmed kill added its scent")
	var visible: Dictionary = {}
	for bag in sim.snapshot_for(killer.id)["bags"]:
		if int(bag["id"]) == body_id:
			visible = bag
	t.check(bool(visible.get("corpse_scent", false)),
		"owner receives only the server-derived visible warning")
	t.check(not visible.has("corpse_scent_until") and not visible.has("allowed_tokens"),
		"private account entitlements and exact scent state are hidden")

	t.current = "real idle infected investigate; combat targets take precedence"
	killer.position = _at(world, site.x + 120, site.z)
	var follower := Zombie.new(sim.new_id(), "walker",
		_at(world, site.x + 18, site.z), -1)
	sim.zombies[follower.id] = follower
	sim.tick_count = 5
	sim._tick_zombies(0.05)
	t.eq(follower.state, Zombie.State.INVESTIGATE,
		"a corpse gives idle infected a genuine destination")
	t.eq(follower.target_id, -1, "a corpse cannot fabricate a player target")
	t.check(follower.last_known_target.distance_to(Vector2(site.x, site.z)) < 0.01,
		"the investigated location is the actual death")
	var busy := Zombie.new(sim.new_id(), "walker",
		_at(world, site.x + 15, site.z), -1)
	busy.state = Zombie.State.CHASE
	busy.target_id = killer.id
	sim.zombies[busy.id] = busy
	sim._alert_corpse_scents()
	t.eq(busy.target_id, killer.id, "blood cues cannot override an active chase")
	t.eq(busy.state, Zombie.State.CHASE, "combat state stays active")

	t.current = "loot removal and expiry stop investigation"
	t.eq(str(sim.cmd_loot(killer.id, body_id).get("reason", "")), "too_far",
		"cannot claim a blood bag from beyond reach")
	killer.position = site
	t.check(bool(sim.cmd_loot(killer.id, body_id).get("ok", false)),
		"normal loot permissions still allow the killer to claim items")
	t.check(not sim.bags.has(body_id), "collected corpse bag disappears")
	sim.zombies.clear()
	killer.position = _at(world, site.x + 120, site.z)
	var later := Zombie.new(sim.new_id(), "walker",
		_at(world, site.x + 18, site.z), -1)
	sim.zombies[later.id] = later
	sim.tick_count = 5
	sim._tick_zombies(0.05)
	t.check(later.state != Zombie.State.INVESTIGATE,
		"after looting there is no phantom blood trail")
	t.eq(later.target_id, -1, "after looting no phantom survivor is tracked")

	t.current = "full-loot deaths leave temporary public blood trails"
	var victim = sim.add_player(53, "Fallen Raider")
	var dangerous: Vector3 = _at(world, 830, 0)
	t.check(ZoneRisk.full_loot(world.zone_at(dangerous.x, dangerous.z)),
		"full-loot death takes place outside peaceful regions")
	victim.position = dangerous
	victim.inventory.add("silver", 25)
	var before_ids: Array = sim.bags.keys()
	victim.survival.hurt(10000.0)
	sim._on_player_death(victim, -1)
	var death_id: int = -1
	for id in sim.bags:
		if not before_ids.has(id):
			death_id = int(id)
	t.check(death_id >= 0, "actual full-loot death produces dropped items")
	if death_id >= 0:
		t.check(CorpseScent.active(sim.bags[death_id], sim.time),
			"actual dropped gear has an expiring scent cue")
	t.check(not sim.character_data(victim).has("corpse_scent_until"),
		"blood traces are not persistent character attributes")
