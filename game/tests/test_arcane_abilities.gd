extends RefCounted
## Classless Arcane Bolt and Cataclysm ultimate are server-owned, cost energy,
## respect cooldowns, and the ultimate never harms survivors.
const Arcane = preload("res://scripts/shared/arcane_abilities.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")


func _zombie(sim, world, x: float, z: float) -> Zombie:
	var zombie := Zombie.new(sim.new_id(), "walker", Vector3(x, world.height_at(x, z), z))
	sim.zombies[zombie.id] = zombie
	return zombie


func run(t) -> void:
	t.current = "damage formulas"
	t.near(Arcane.bolt_damage(0.0), Arcane.BOLT_BASE_DAMAGE, 0.0001, "bolt base damage")
	t.check(Arcane.bolt_damage(0.5) > Arcane.bolt_damage(0.0), "ranged training strengthens the bolt")
	t.near(Arcane.ultimate_damage(0.0, 0.0), Arcane.ULTIMATE_BASE_DAMAGE, 0.0001, "full damage at the centre")
	t.near(Arcane.ultimate_damage(Arcane.ULTIMATE_RADIUS, 0.0), Arcane.ULTIMATE_BASE_DAMAGE * 0.5, 0.0001, "half at the edge")
	t.eq(Arcane.ultimate_damage(Arcane.ULTIMATE_RADIUS + 0.1, 0.0), 0.0, "nothing outside the blast")

	var world := WorldGen.new(4412)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(world)
	t.check(site.is_finite(), "clear dangerous-zone combat site")
	if not site.is_finite():
		return
	var sim := GameServer.new(world, 4412)
	var caster = sim.add_player(31, "Mage")
	caster.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)

	t.current = "arcane bolt"
	t.eq(sim.cmd_arcane_bolt(999, 1, 0).get("reason", ""), "dead", "unknown peer cannot cast")
	t.eq(sim.cmd_arcane_bolt(31, 0, 0).get("reason", ""), "no_direction", "a bolt needs an aim")
	var target := _zombie(sim, world, site.x + 6.0, site.y)
	var health_before: float = target.health
	var energy_before: float = caster.combat_energy
	var bolt: Dictionary = sim.cmd_arcane_bolt(31, 1, 0)
	t.check(bool(bolt.get("ok", false)), "bolt casts")
	t.check(bool(bolt.get("hit", false)), "bolt hits the infected in its path")
	t.check(target.health < health_before, "bolt damages the infected")
	t.near(caster.combat_energy, energy_before - Arcane.BOLT_ENERGY_COST, 0.0001, "bolt costs energy")
	t.check(sim.events.any(func(e): return str(e.get("type", "")) == "arcane_bolt"), "bolt is broadcast for visuals")
	caster.attack_timer = 0.0
	t.eq(sim.cmd_arcane_bolt(31, 1, 0).get("reason", ""), "cooldown", "bolt has a cooldown")
	caster.arcane_cooldown = 0.0
	caster.combat_energy = Arcane.BOLT_ENERGY_COST - 1.0
	t.eq(sim.cmd_arcane_bolt(31, 1, 0).get("reason", ""), "no_energy", "bolt needs energy")

	t.current = "native bounded nearest-K ranking and exact fallbacks"
	var native_grid: Object = null
	if ClassDB.class_exists("SpatialRelevancyGrid2D"):
		var candidate_grid: Object = ClassDB.instantiate("SpatialRelevancyGrid2D")
		if candidate_grid != null and candidate_grid.has_method("query_nearest_ids"):
			native_grid = candidate_grid
			var points: PackedVector2Array = PackedVector2Array([
				Vector2(0, 0), Vector2(2, 0), Vector2(-2, 0), Vector2(0, 0),
				Vector2(0, -2), Vector2(100, 100), Vector2(1, 0),
				Vector2(10, 10), Vector2(-10, -10), Vector2(999, 0)
			])
			var ids: PackedInt64Array = PackedInt64Array([50, 8, 90, 3, 15, 600, 29, 70, 11, 12])
			t.check(native_grid.rebuild(ids, points), "native nearest-K grid rebuilds")
			t.eq(native_grid.query_nearest_ids(Vector2.ZERO, 2.0, 5),
				PackedInt64Array([3, 50, 29, 8, 15]),
				"distance then ID tie-break returns five nearest actors")
			t.eq(native_grid.query_nearest_ids(Vector2.ZERO, 0.0, 3),
				PackedInt64Array([3, 50]),
				"zero-radius inclusive query keeps coincident actors")
			t.eq(native_grid.query_nearest_ids(Vector2.ZERO, 2.0, 0).size(), 0,
				"no zero-sized top-K result can allocate an unbounded list")
			t.eq(native_grid.query_nearest_ids(Vector2.ZERO, 2.0, 129).size(), 0,
				"top-K request over 128 is rejected")
			t.eq(native_grid.query_nearest_ids(Vector2.ZERO, 1000.0, 3),
				PackedInt64Array([3, 50, 29]),
				"large-radius fallback still returns nearest three")
			var random := RandomNumberGenerator.new()
			random.seed = 44103
			for iteration in 80:
				var point_list := PackedVector2Array()
				var id_list := PackedInt64Array()
				for i in 70:
					point_list.append(Vector2(random.randf_range(-200, 200),
						random.randf_range(-200, 200)))
					id_list.append(10000 + i)
				t.check(native_grid.rebuild(id_list, point_list),
					"random nearest index can rebuild safely")
				var origin := Vector2(random.randf_range(-200, 200),
					random.randf_range(-200, 200))
				var radius: float = [0.0, 7.0, 64.0, 256.0][iteration % 4]
				var brute: Array = []
				for i in id_list.size():
					var distance: float = origin.distance_squared_to(point_list[i])
					if distance <= radius * radius:
						brute.append({"id": id_list[i], "d": distance})
				brute.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]) \
					if float(a["d"]) != float(b["d"]) else int(a["id"]) < int(b["id"]))
				var expected := PackedInt64Array()
				for i in mini(brute.size(), 5):
					expected.append(int(brute[i]["id"]))
				t.eq(native_grid.query_nearest_ids(origin, radius, 5), expected,
					"native top-K agrees with complete script sort at trial %d" % iteration)

	t.current = "cataclysm ultimate"
	caster.combat_energy = 100.0
	caster.attack_timer = 0.0
	var near := _zombie(sim, world, site.x + 1.0, site.y + 1.0)
	var edge := _zombie(sim, world, site.x, site.y + Arcane.ULTIMATE_RADIUS - 0.5)
	var outside := _zombie(sim, world, site.x - Arcane.ULTIMATE_RADIUS - 3.0, site.y)
	var bystander = sim.add_player(32, "Bystander")
	bystander.position = caster.position + Vector3(1.0, 0.0, 0.0)
	var bystander_health: float = bystander.survival.health
	var near_before: float = near.health
	var edge_before: float = edge.health
	var outside_before: float = outside.health
	var ult: Dictionary = sim.cmd_ultimate(31)
	t.check(bool(ult.get("ok", false)), "ultimate casts")
	t.check(int(ult.get("hits", 0)) >= 2, "ultimate hits every infected in range")
	t.check(near.health < near_before or not near.is_alive(), "close infected hurt")
	t.check(edge.health < edge_before or not edge.is_alive(), "edge infected hurt")
	t.eq(outside.health, outside_before, "infected outside the blast untouched")
	t.eq(bystander.survival.health, bystander_health, "ultimate never damages survivors")
	t.near(caster.ultimate_cooldown, Arcane.ULTIMATE_COOLDOWN, 0.0001, "long cooldown starts")
	caster.attack_timer = 0.0
	t.eq(sim.cmd_ultimate(31).get("reason", ""), "cooldown", "ultimate cannot be spammed")
	caster.ultimate_cooldown = 0.0
	caster.combat_energy = Arcane.ULTIMATE_ENERGY_COST - 1.0
	t.eq(sim.cmd_ultimate(31).get("reason", ""), "no_energy", "ultimate needs energy")
	caster.mounted = true
	caster.combat_energy = 100.0
	t.eq(sim.cmd_ultimate(31).get("reason", ""), "mounted", "no ultimate from the saddle")

	t.current = "Cataclysm affects only the nearest capped targets even in a dense horde"
	var crowd_sim := GameServer.new(world, 4412)
	var crowd_mage = crowd_sim.add_player(91, "TopKSurvivor")
	crowd_mage.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	var crowd: Array[Zombie] = []
	var pre_health: Array[float] = []
	for i in 16:
		var range_m: float = 0.5 + float(i) * 0.34
		var mob := _zombie(crowd_sim, world, site.x + range_m, site.y)
		crowd.append(mob)
		pre_health.append(mob.health)
	var crowd_result: Dictionary = crowd_sim.cmd_ultimate(91)
	t.check(bool(crowd_result.get("ok", false)), "densely packed ultimate is authorized")
	t.eq(int(crowd_result.get("hits", 0)), Arcane.ULTIMATE_MAX_TARGETS,
		"ultimate never applies more than 12 authoritative hit actions")
	for i in crowd.size():
		if i < Arcane.ULTIMATE_MAX_TARGETS:
			t.check(crowd[i].health < pre_health[i] or not crowd[i].is_alive(),
				"nearest target %d takes damage" % i)
		else:
			t.eq(crowd[i].health, pre_health[i],
				"farther target %d stays unhurt under maximum target cap" % i)
	var native_selected: bool = native_grid != null
	t.eq(bool(crowd_sim.last_ultimate_spatial_stats["native"]), native_selected,
		"real server uses native nearest-K when available and script otherwise")
	t.eq(int(crowd_sim.last_ultimate_spatial_stats["selected"]), Arcane.ULTIMATE_MAX_TARGETS,
		"server exposes exact selected count for engine integration diagnostics")
	if native_selected:
		t.eq(int(crowd_sim.last_ultimate_spatial_stats["grid"]["nearest_queries"]), 1,
			"Cataclysm performs exactly one indexed nearest query per cast")
		t.eq(crowd_sim._ultimate_spatial_grid.get_stats()["entities"], 0,
			"native cached index is cleared after a cast to avoid stale positions")

