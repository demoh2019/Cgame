extends RefCounted
## Particle fluids: 3D position-based fluids (SPH) and 2D FLIP/PIC with solid cells and obstacles.

const SphFluid = preload("res://scripts/shared/sph_fluid.gd")
const FlipFluid = preload("res://scripts/shared/flip_fluid.gd")

const SPH_DT := 1.0 / 60.0


func run(t) -> void:
	_test_sph_pool(t)
	_test_sph_dam_break(t)
	_test_sph_obstacle(t)
	_test_flip_projection(t)
	_test_flip_settle(t)
	_test_flip_dam_wall(t)
	_test_flip_obstacle(t)
	_test_flip_determinism(t)


func _all_finite_in_box(fluid, lo: Vector3, hi: Vector3) -> bool:
	for p in fluid.positions():
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			return false
	return true


func _test_sph_pool(t) -> void:
	t.current = "sph pool"
	var lo := Vector3.ZERO
	var hi := Vector3(0.6, 1.0, 0.6)
	var fluid := SphFluid.new(0.1, lo, hi)
	var added := fluid.add_block(Vector3(0.05, 0.35, 0.05), Vector3(0.55, 0.65, 0.55))
	t.eq(fluid.particle_count(), added, "particles registered")
	t.check(fluid.rest_density > 100.0, "rest density calibrated from the lattice")
	var bounded := true
	for _i in 120:
		fluid.step(SPH_DT, 3)
		if not _all_finite_in_box(fluid, lo, hi):
			bounded = false
			break
	t.check(bounded, "particles stay finite and inside the box")
	var ratio := fluid.average_density() / fluid.rest_density
	t.check(ratio > 0.55 and ratio < 1.25, "settled density near rest (ratio %.2f)" % ratio)
	var top := 0.0
	for p in fluid.positions():
		top = maxf(top, p.y)
	t.check(top < 0.5, "pool slumps instead of floating (top %.2f)" % top)
	t.check(fluid.kinetic_energy() < 5.0 * fluid.particle_mass * float(added), "pool is calm after settling")


func _test_sph_dam_break(t) -> void:
	t.current = "sph dam break"
	var lo := Vector3.ZERO
	var hi := Vector3(1.6, 0.8, 0.4)
	var fluid := SphFluid.new(0.1, lo, hi)
	fluid.add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.35, 0.65, 0.35))
	var start_max_x := 0.0
	for p in fluid.positions():
		start_max_x = maxf(start_max_x, p.x)
	for _i in 90:
		fluid.step(SPH_DT, 3)
	var end_max_x := 0.0
	var top := 0.0
	for p in fluid.positions():
		end_max_x = maxf(end_max_x, p.x)
		top = maxf(top, p.y)
	t.check(_all_finite_in_box(fluid, lo, hi), "dam break stays finite and bounded")
	t.check(end_max_x > start_max_x + 0.5, "column spreads sideways (%.2f -> %.2f)" % [start_max_x, end_max_x])
	t.check(top < 0.6, "column collapses (top %.2f)" % top)


func _test_sph_obstacle(t) -> void:
	t.current = "sph obstacle coupling"
	var lo := Vector3.ZERO
	var hi := Vector3(0.8, 0.6, 0.4)
	var fluid := SphFluid.new(0.1, lo, hi)
	fluid.vorticity_epsilon = 0.05
	fluid.add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.75, 0.35, 0.35))
	for _i in 25:
		fluid.step(SPH_DT, 3)
	var index := fluid.add_sphere_obstacle(Vector3(0.15, 0.13, 0.2), 0.1, Vector3(1.5, 0.0, 0.0), 2.0)
	var momentum_before := fluid.total_momentum().x
	for _i in 8:
		fluid.step(SPH_DT, 3)
	t.check(_all_finite_in_box(fluid, lo, hi), "fluid with obstacle stays finite")
	t.check(fluid.total_momentum().x > momentum_before + 0.5, "moving obstacle pushes fluid forward")
	t.check(fluid.obstacle_velocity(index).x < 1.5 - 0.05, "obstacle loses momentum to the fluid")
	t.check(fluid.obstacle_position(index).x > 0.25, "obstacle advanced")
	var inside := 0
	var centre := fluid.obstacle_position(index)
	for p in fluid.positions():
		if p.distance_to(centre) < 0.1 - 0.02:
			inside += 1
	t.eq(inside, 0, "no particle inside the sphere")


func _flip_pool(compensate: bool) -> FlipFluid:
	var sim := FlipFluid.new(22, 22, 0.1)
	sim.compensate_drift = compensate
	sim.add_water_block(Vector2(0.2, 0.2), Vector2(1.2, 1.0))
	return sim


func _test_flip_projection(t) -> void:
	t.current = "flip projection"
	var sim := _flip_pool(false)
	t.check(sim.particle_count() > 100, "water block created (%d)" % sim.particle_count())
	for _i in 4:
		sim.step(1.0 / 60.0)
	var before := sim.last_divergence_before
	var after := sim.divergence_max()
	t.check(before > 0.0, "raw transfer leaves divergence (%.4f)" % before)
	t.check(after < before * 0.5, "projection reduces divergence (%.4f -> %.4f)" % [before, after])
	t.check(is_finite(after), "divergence finite")


func _test_flip_settle(t) -> void:
	t.current = "flip settle"
	var sim := _flip_pool(true)
	var start_height := sim.average_height()
	for _i in 150:
		sim.step(1.0 / 60.0)
	var end_height := sim.average_height()
	t.check(end_height < start_height - 0.15, "water falls (%.2f -> %.2f)" % [start_height, end_height])
	var highest := 0.0
	var lowest := 100.0
	var finite := true
	var inside_wall := 0
	for p in sim.particle_positions():
		highest = maxf(highest, p.y)
		lowest = minf(lowest, p.y)
		if not (is_finite(p.x) and is_finite(p.y)):
			finite = false
		if sim.is_wall(sim.cell_of(p)):
			inside_wall += 1
	t.check(finite, "particles finite")
	t.check(lowest < 0.25, "water reaches the floor (lowest %.2f)" % lowest)
	t.check(highest < 1.0, "water settled into a pool (top %.2f)" % highest)
	t.eq(inside_wall, 0, "no particle inside the border walls")
	t.check(sim.kinetic_energy() / float(sim.particle_count()) < 0.5, "pool is calm")
	t.eq(sim.cell_type_at(Vector2i(0, 0)), FlipFluid.SOLID, "border is solid")
	t.eq(sim.cell_type_at(Vector2i(5, 1)), FlipFluid.FLUID, "pool cell is fluid")
	t.eq(sim.cell_type_at(Vector2i(5, 19)), FlipFluid.AIR, "empty cell is air")


func _test_flip_dam_wall(t) -> void:
	t.current = "flip destructible wall"
	var sim := FlipFluid.new(30, 12, 0.1)
	var wall_x := 15
	for j in range(1, 11):
		sim.set_solid(Vector2i(wall_x, j), true)
	t.eq(sim.cell_type_at(Vector2i(wall_x, 5)), FlipFluid.SOLID, "wall cell is solid")
	sim.add_water_block(Vector2(0.2, 0.2), Vector2(1.3, 0.9))
	var wall_left := float(wall_x) * 0.1
	var wall_right := float(wall_x + 1) * 0.1
	var leaked := 0
	var in_wall := 0
	for _i in 120:
		sim.step(1.0 / 60.0)
		for p in sim.particle_positions():
			if sim.is_wall(sim.cell_of(p)):
				in_wall += 1
			if p.x > wall_right:
				leaked += 1
	t.eq(in_wall, 0, "particles never inside solids")
	t.eq(leaked, 0, "intact wall holds the water back")
	for j in range(1, 11):
		sim.set_solid(Vector2i(wall_x, j), false)
	t.eq(sim.cell_type_at(Vector2i(wall_x, 5)) == FlipFluid.SOLID, false, "removed wall cell is open")
	for _i in 180:
		sim.step(1.0 / 60.0)
		for p in sim.particle_positions():
			if sim.is_wall(sim.cell_of(p)):
				in_wall += 1
	var beyond := 0
	for p in sim.particle_positions():
		if p.x > wall_right + 0.3:
			beyond += 1
	t.check(beyond * 6 > sim.particle_count(), "water flows through the breach (%d of %d)" % [beyond, sim.particle_count()])
	t.eq(in_wall, 0, "no particle inside solids after the breach")
	t.check(wall_left < wall_right, "wall geometry sane")


func _test_flip_obstacle(t) -> void:
	t.current = "flip obstacle"
	var sim := FlipFluid.new(24, 20, 0.1)
	sim.add_water_block(Vector2(0.2, 0.2), Vector2(2.1, 0.7))
	for _i in 60:
		sim.step(1.0 / 60.0)
	sim.set_obstacle(Vector2(1.2, 1.4), 0.25, Vector2(0.0, -1.5))
	var min_gap := 100.0
	for _i in 28:
		sim.step(1.0 / 60.0)
		for p in sim.particle_positions():
			min_gap = minf(min_gap, p.distance_to(sim.obstacle_center))
	t.check(min_gap >= 0.25 - 0.001, "particles are held outside the circle (gap %.3f)" % min_gap)
	t.check(sim.obstacle_center.y < 1.4, "obstacle moved with its velocity")
	var fastest := 0.0
	for v in sim.pvel:
		fastest = maxf(fastest, v.length())
	t.check(fastest > 0.3, "plunging obstacle stirs the water (%.2f)" % fastest)
	sim.clear_obstacle()
	sim.step(1.0 / 60.0)
	t.check(not sim.obstacle_active, "obstacle removed")


func _test_flip_determinism(t) -> void:
	t.current = "flip determinism"
	var a := _flip_pool(true)
	var b := _flip_pool(true)
	for _i in 40:
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
	var same := a.particle_count() == b.particle_count()
	if same:
		for i in a.particle_count():
			if a.ppos[i] != b.ppos[i]:
				same = false
				break
	t.check(same, "identical runs give identical particles")
	var sa := SphFluid.new(0.1, Vector3.ZERO, Vector3(0.6, 0.6, 0.4))
	var sb := SphFluid.new(0.1, Vector3.ZERO, Vector3(0.6, 0.6, 0.4))
	sa.add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.25, 0.35, 0.25))
	sb.add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.25, 0.35, 0.25))
	for _i in 15:
		sa.step(SPH_DT, 3)
		sb.step(SPH_DT, 3)
	var sph_same := true
	for i in sa.particle_count():
		if sa.pos[i] != sb.pos[i]:
			sph_same = false
			break
	t.check(sph_same, "sph runs are deterministic")
