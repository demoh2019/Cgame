# Native PBFParticleFluid3D integration regression. Tests actual registered
# engine class, fixed-timestep SceneTree simulation, density neighborhoods,
# particle bounds, pause/resume and explicit manual stepping.
# Run: --headless --path tests/stress --script res://physics_pbf_particle_fluid_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fluid := PBFParticleFluid3D.new()
	fluid.name = "NativePBFTest"
	fluid.box_min = Vector3(-1.5, 0.0, -1.5)
	fluid.box_max = Vector3(1.5, 3.5, 1.5)
	fluid.smoothing_radius = 0.32
	fluid.particle_mass = 6.0
	fluid.rest_density = 1000.0
	fluid.solver_iterations = 5
	fluid.xsph_viscosity = 0.02
	fluid.gravity = Vector3(0, -9.8, 0)
	root.add_child(fluid)
	var created: bool = fluid.create_block(
			Vector3(-0.48, 1.45, -0.48), Vector3i(5, 4, 5), 0.18)
	if not created or fluid.get_particle_count() != 100:
		printerr("Native PBF block initialization failed")
		fluid.queue_free()
		quit(1)
		return
	var initial := fluid.get_particle_positions()
	fluid.simulation_enabled = true
	var initial_y := 0.0
	for p in initial:
		initial_y += p.y
	initial_y /= float(initial.size())

	var max_checks := 0
	var finite := true
	for frame in range(40):
		await physics_frame
		max_checks = maxi(max_checks, fluid.get_last_neighbor_evaluations())
	await process_frame
	fluid.simulation_enabled = false
	var points := fluid.get_particle_positions()
	var velocities := fluid.get_particle_velocities()
	var total_y := 0.0
	for p in points:
		total_y += p.y
		finite = finite and p.is_finite()
		finite = finite and p.x >= -1.501 and p.x <= 1.501
		finite = finite and p.y >= -0.001 and p.y <= 3.501
		finite = finite and p.z >= -1.501 and p.z <= 1.501
	for v in velocities:
		finite = finite and v.is_finite()
	var final_y := total_y / float(points.size())
	var updated := final_y < initial_y - 0.01
	var collision_budget := max_checks > 0 and max_checks <= 100 * 128 * 5
	var density_ok := is_finite(fluid.get_average_density()) and fluid.get_average_density() > 0.0

	# Pausing halts the native internal physics callback.
	var paused_positions := fluid.get_particle_positions()
	for frame in range(3):
		await physics_frame
	var still_paused := paused_positions == fluid.get_particle_positions()
	var manual_step := fluid.step(1.0 / 60.0)
	var invalid_dt := not fluid.step(-1.0)
	var too_large_block := not fluid.create_block(Vector3.ZERO, Vector3i(32, 32, 32), 0.2)
	var count_preserved := fluid.get_particle_count() == 100

	fluid.queue_free()
	if not (finite and updated and collision_budget and density_ok and
			still_paused and manual_step and invalid_dt and too_large_block and count_preserved):
		printerr("PBF runtime FAILED: finite=", finite, " updated=", updated,
				" collision_budget=", collision_budget, " density=", density_ok,
				" pause=", still_paused, " manual=", manual_step,
				" invalid_dt=", invalid_dt, " count=", count_preserved,
				" initial_y=", initial_y, " final_y=", final_y,
				" checks=", max_checks)
		quit(1)
		return
	print("Native PBF particle fluid passed: count=100 initial_y=", initial_y,
			" final_y=", final_y, " density=", density_ok, " checks=", max_checks)
	quit(0)
