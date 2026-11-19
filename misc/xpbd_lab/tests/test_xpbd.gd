extends SceneTree
## Run with an official Godot 4.6+ binary:
## godot --headless --path misc/xpbd_lab --script res://tests/test_xpbd.gd

const Solver = preload("res://addons/cgame_xpbd/xpbd_solver_3d.gd")

var checks: int = 0
var failures: int = 0


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	_test_stretch()
	_test_compliance()
	_test_pinning()
	_test_tearing()
	_test_collisions()
	_test_topology()
	_test_wind_and_determinism()
	_test_invalid_inputs()
	if failures != 0:
		push_error("XPBD: %d failed of %d assertions" % [failures, checks])
		quit(1)
	else:
		print("XPBD PASS: %d assertions" % checks)
		quit(0)


func _test_stretch() -> void:
	var s: CgameXPBDSolver3D = Solver.new()
	s.solver_iterations = 10
	var a: int = s.add_particle(Vector3.ZERO, 1.0, true)
	var b: int = s.add_particle(Vector3.RIGHT, 1.0)
	_expect(s.add_distance_constraint(a, b) == 0, "valid distance constraint accepted")
	s.positions[b] = Vector3(2.0, 0.0, 0.0)
	s.step(1.0 / 60.0, Vector3.ZERO)
	_expect(_approx(s.positions[a].x, 0.0), "pinned point stationary during solve")
	_expect(_approx(s.positions[b].x, 1.0), "zero compliance restores rod length")
	_expect(s.max_relative_stretch() < 0.0001, "exact distance constraint residual")


func _test_compliance() -> void:
	var stiff: CgameXPBDSolver3D = Solver.new()
	var soft: CgameXPBDSolver3D = Solver.new()
	for s in [stiff, soft]:
		s.substeps = 1
		s.add_particle(Vector3.ZERO, 1.0, true)
		s.add_particle(Vector3.RIGHT, 1.0)
	stiff.add_distance_constraint(0, 1, 0.0)
	soft.add_distance_constraint(0, 1, 0.01)
	stiff.positions[1] = Vector3(1.5, 0.0, 0.0)
	soft.positions[1] = Vector3(1.5, 0.0, 0.0)
	stiff.step(1.0 / 60.0, Vector3.ZERO)
	soft.step(1.0 / 60.0, Vector3.ZERO)
	_expect(stiff.positions[1].x < soft.positions[1].x, "compliance allows greater stretch")
	_expect(_approx(stiff.positions[1].x, 1.0), "rigid and compliant rods differ")
	_expect(soft.positions[1].x < 1.5 and soft.positions[1].x > 1.0, "compliant rod correction bounded")


func _test_pinning() -> void:
	var s: CgameXPBDSolver3D = Solver.new()
	s.create_rope(Vector3(0.0, 3.0, 0.0), Vector3(5.0, 3.0, 0.0), 12, 3.0)
	var pinned: Vector3 = s.positions[0]
	for k in range(150):
		s.step(1.0 / 60.0)
	_expect(s.positions[0] == pinned, "anchored rope remains exactly pinned")
	_expect(s.positions[s.particle_count() - 1].y < 3.0, "rope sags under gravity")
	for p in s.positions:
		_expect(p.is_finite(), "rope particle remains finite")
	s.pin_particle(4, Vector3(1.0, 5.0, 0.0))
	s.step(1.0 / 60.0)
	_expect(s.positions[4] == Vector3(1.0, 5.0, 0.0), "dynamic pin updated")


func _test_tearing() -> void:
	var s: CgameXPBDSolver3D = Solver.new()
	s.substeps = 1
	s.add_particle(Vector3.ZERO, 1.0, true)
	s.add_particle(Vector3.RIGHT)
	s.add_distance_constraint(0, 1, 0.0, 0.2)
	s.positions[1] = Vector3(2.0, 0.0, 0.0)
	s.step(1.0 / 60.0, Vector3.ZERO)
	_expect(s.broken_constraint_count() == 1, "high strain tears constraint")
	_expect(s.active_constraint_count() == 0, "broken constraint no longer active")
	_expect(s.positions[1].x > 1.5, "broken constraint no longer pulls point back")


func _test_collisions() -> void:
	var floor_sim: CgameXPBDSolver3D = Solver.new()
	floor_sim.floor_enabled = true
	floor_sim.floor_height = -0.5
	floor_sim.particle_radius = 0.1
	floor_sim.add_particle(Vector3(0.0, -0.7, 0.0))
	floor_sim.step(1.0 / 60.0)
	_expect(floor_sim.positions[0].y >= -0.40001, "plane collision projects above floor")
	var sphere_sim: CgameXPBDSolver3D = Solver.new()
	sphere_sim.particle_radius = 0.05
	sphere_sim.add_sphere_collider(Vector3.ZERO, 1.0)
	sphere_sim.add_particle(Vector3(0.5, 0.0, 0.0))
	sphere_sim.step(1.0 / 60.0, Vector3.ZERO)
	_expect(sphere_sim.positions[0].length() >= 1.049, "sphere collision enforces separation")
	_expect(sphere_sim.velocities[0].is_finite(), "collision velocity finite")


func _test_topology() -> void:
	var rope: CgameXPBDSolver3D = Solver.new()
	rope.create_rope(Vector3.ZERO, Vector3.RIGHT * 3.0, 6)
	_expect(rope.particle_count() == 7, "rope has segments plus one vertex")
	_expect(rope.constraints.size() == 11, "rope has stretch and bending constraints")
	var cloth: CgameXPBDSolver3D = Solver.new()
	cloth.create_cloth(Vector3(0.0, 5.0, 0.0), 5, 4)
	_expect(cloth.particle_count() == 20, "cloth grid has columns times rows")
	_expect(cloth.inverse_masses[0] == 0.0 and cloth.inverse_masses[4] == 0.0, "cloth upper corners pinned")
	_expect(cloth.constraints.size() > 40, "cloth has stretch, shear and bend constraints")
	cloth.step(1.0 / 60.0)
	for p in cloth.positions:
		_expect(p.is_finite(), "cloth point remains finite")


func _test_wind_and_determinism() -> void:
	var first: CgameXPBDSolver3D = Solver.new()
	var second: CgameXPBDSolver3D = Solver.new()
	for sim in [first, second]:
		sim.create_cloth(Vector3(0.0, 2.0, 0.0), 4, 4)
		sim.wind_drag = 2.0
	for t in range(25):
		first.step(1.0 / 60.0, Vector3.ZERO, Vector3(8.0, 0.0, 0.0))
		second.step(1.0 / 60.0, Vector3.ZERO, Vector3(8.0, 0.0, 0.0))
	_expect(first.positions[5].x > 0.25, "wind accelerates free cloth vertices")
	for i in range(first.particle_count()):
		_expect(first.positions[i] == second.positions[i], "identical inputs produce deterministic results")
	_expect(first.positions[0] == Vector3(0.0, 2.0, 0.0), "corner remains pinned under wind")


func _test_invalid_inputs() -> void:
	var s: CgameXPBDSolver3D = Solver.new()
	_expect(s.add_distance_constraint(0, 1) == -1, "reject nonexistent particles")
	s.add_particle(Vector3.ZERO, 0.0, true)
	_expect(s.inverse_masses[0] == 0.0, "zero-mass particle has zero inverse mass")
	_expect(s.add_distance_constraint(0, 0) == -1, "reject self-links")
	s.step(-1.0)
	_expect(s.positions[0].is_finite(), "negative step ignored safely")
	s.create_rope(Vector3.ZERO, Vector3.ZERO, 2)
	_expect(s.constraints.size() == 0, "degenerate zero-length rods omitted")
