extends RefCounted
## Corrosive spitter terrain threatens fortified player bases. It never
## bypasses tier durability or multiplies damage from overlapping pools.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Acid = preload("res://scripts/shared/acid_spitter.gd")


func _position(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func _find_site(world) -> Vector2:
	# Place a *real* server-validated structure in the dangerous region.
	for x in range(750, 1040, 9):
		for z in range(-155, 156, 9):
			var point := Vector2(float(x), float(z))
			var owner_position := point + Vector2(-2.8, 0.0)
			if world.zone_at(point.x, point.y) < Acid.MIN_ZONE 					or world.is_water(point.x, point.y) 					or world.is_water(owner_position.x, owner_position.y):
				continue
			if world.normal_at(point.x, point.y).y < Structures.MIN_SLOPE_NORMAL_Y:
				continue
			var blocked := false
			for at in [point, owner_position]:
				for obj in world.blockers_near(at.x, at.y, 2.4):
					if at.distance_to(Vector2(float(obj["x"]), float(obj["z"]))) 							< float(obj["radius"]) + 1.95:
						blocked = true
						break
				if blocked:
					break
			if not blocked:
				return point
	return Vector2.INF


func run(t) -> void:
	t.current = "corrosion intersection limits"
	t.check(Acid.corrodes_wall(Vector2.ZERO, Vector2(2.5, 0), Structures.RADIUS),
		"a splash touching a barricade counts as contact")
	t.check(not Acid.corrodes_wall(Vector2.ZERO, Vector2(5, 0), Structures.RADIUS),
		"far-away walls cannot take corrosive damage")
	t.check(not Acid.corrodes_wall(Vector2.INF, Vector2.ZERO, Structures.RADIUS),
		"invalid puddle position is rejected")
	t.check(not Acid.corrodes_wall(Vector2.ZERO, Vector2.ZERO, NAN),
		"invalid wall geometry cannot trigger damage")

	t.current = "real construction, splash and delayed wall damage"
	var world := WorldGen.new(315)
	var spot: Vector2 = _find_site(world)
	t.check(spot.is_finite(), "viable dry red-zone construction site found")
	if not spot.is_finite():
		return
	var sim := Server.new(world, 315)
	var builder = sim.add_player(201, "Engineer", "wall-owner")
	builder.position = _position(world, spot + Vector2(-2.8, 0.0))
	builder.inventory.add("wood_1", 4)
	builder.inventory.add("stone_1", 2)
	var built: Dictionary = sim.cmd_build(201, spot.x, spot.y)
	t.check(bool(built.get("ok", false)), "owner creates authoritative fortified obstacle")
	if not bool(built.get("ok", false)):
		return
	var wall_id: int = int(built["id"])
	var spitter = Zombie.new(sim.new_id(), "spitter", _position(world, spot + Vector2(7, 0)), -1)
	sim.zombies[spitter.id] = spitter
	var hp_before: float = float(sim.barricades[wall_id]["hp"])
	sim._resolve_spit_impact(spitter, spot)
	t.eq(sim.acid_pools.size(), 1, "initial splash creates exactly one hazard")
	t.near(float(sim.barricades[wall_id]["hp"]), hp_before, 0.001,
		"direct splash has not yet applied lingering wall corrosion")
	sim._tick_acid_pools()
	t.near(float(sim.barricades[wall_id]["hp"]), hp_before, 0.001,
		"no early wall corrosion before pool tick")
	sim.time += Acid.POOL_TICK_SECONDS
	var initial_revision: int = sim.world_structure_revision
	sim._tick_acid_pools()
	t.near(float(sim.barricades[wall_id]["hp"]),
		hp_before - Acid.STRUCTURE_CORROSION_DAMAGE, 0.001,
		"first environmental tick damages real T1 defense")
	t.check(sim.world_structure_revision > initial_revision,
		"durability damage marks world checkpoint dirty")
	t.check(world.dynamic_blockers.has(wall_id), "damaged wall still blocks movement")

	t.current = "multiple acid pools cannot multiply structure damage"
	var hp_after: float = float(sim.barricades[wall_id]["hp"])
	var second_pool: Dictionary = Acid.make_pool(sim.new_id(), spot,
		world.height_at(spot.x, spot.y), sim.time - 1.0, spitter.id)
	sim.acid_pools[int(second_pool["id"])] = second_pool
	sim._tick_acid_pools()
	t.near(float(sim.barricades[wall_id]["hp"]), hp_after, 0.001,
		"overlapping puddles cannot add another wall hit at the same moment")
	sim.time += Acid.POOL_TICK_SECONDS
	sim._tick_acid_pools()
	t.near(float(sim.barricades[wall_id]["hp"]),
		hp_after - Acid.STRUCTURE_CORROSION_DAMAGE, 0.001,
		"next second adds one bounded hit, not one per pool")

	t.current = "upgrades resist acid and durability persists"
	var wall: Dictionary = sim.barricades[wall_id]
	wall["tier"] = 4
	wall["hp"] = Structures.max_health(4)
	var fortified_start: float = float(wall["hp"])
	sim.time += Acid.POOL_TICK_SECONDS
	sim._tick_acid_pools()
	t.near(float(sim.barricades[wall_id]["hp"]),
		fortified_start - Acid.STRUCTURE_CORROSION_DAMAGE * Structures.damage_factor(4),
		0.001, "T4 defense applies existing tier resistance to corrosion")
	t.eq(sim.snapshot_for(201)["barricades"].size(), 1,
		"damaged fortified wall remains visible through standard snapshots")
	t.check(not sim.snapshot_for(201)["barricades"][0].has("owner_account"),
		"environmental damage does not expose private owner credentials")

	t.current = "acid destruction frees physics and cannot be replayed"
	var old_wall: Dictionary = sim.barricades[wall_id]
	old_wall["hp"] = 2.0
	sim.time += Acid.POOL_TICK_SECONDS
	sim._tick_acid_pools()
	t.check(not sim.barricades.has(wall_id), "low-health wall destroyed by corrosive terrain")
	t.check(not world.dynamic_blockers.has(wall_id), "broken defense unblocks movement")
	t.check(not sim._acid_wall_last_hit.has(wall_id),
		"destroyed wall removes its temporary corrosion cooldown")
	sim._tick_acid_pools()
	t.check(not sim.barricades.has(wall_id), "same puddle cannot restore a destroyed wall")
	sim.time += Acid.POOL_SECONDS + 0.01
	sim._tick_acid_pools()
	t.eq(sim.acid_pools.size(), 0, "expired corrosive patches are removed")
