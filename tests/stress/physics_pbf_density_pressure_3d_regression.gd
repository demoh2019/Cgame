# Real native GodotPhysics3D integration for predicted SPH pressure.
# Three identical compressed stationary clouds: original PBF (disabled),
# predictive density pressure (enabled) and deterministic enabled replica.
# An independent O(n^2) SPH continuity reference validates the reported
# density error BEFORE the native positions are advected.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_fluid(pressure_iterations: int) -> PBFParticleFluid3D:
	var fluid := PBFParticleFluid3D.new()
	fluid.name = "Pressure%d" % pressure_iterations
	fluid.gravity = Vector3.ZERO
	fluid.smoothing_radius = 0.42
	fluid.rest_density = 1000.0
	fluid.particle_mass = 6.0
	fluid.xsph_viscosity = 0.0
	fluid.vorticity_confinement = 0.0
	fluid.divergence_iterations = 0
	fluid.density_pressure_iterations = pressure_iterations
	fluid.density_pressure_tolerance = 0.0
	fluid.density_pressure_relaxation = 0.8
	fluid.density_pressure_max_velocity_change = 0.15
	fluid.solver_iterations = 4
	root.add_child(fluid)
	assert(fluid.create_block(Vector3(-0.35, 1.0, -0.35),
			Vector3i(5, 5, 5), 0.175))
	return fluid


func _predicted_density_error(p: PackedVector3Array,
		v: PackedVector3Array, delta: float,
		mass: float, rest_density: float, h: float) -> float:
	var h2: float = h * h
	var kernel_coefficient: float = 315.0 / (64.0 * PI * pow(h, 3.0))
	var gradient_coefficient: float = -945.0 / (32.0 * PI * pow(h, 5.0))
	var sum_error := 0.0
	for i in range(p.size()):
		var density := 0.0
		var rate := 0.0
		for j in range(p.size()):
			var diff: Vector3 = p[i] - p[j]
			var radius2: float = diff.length_squared()
			if radius2 >= h2:
				continue
			var normalized: float = 1.0 - radius2 / h2
			density += mass * kernel_coefficient * pow(normalized, 3.0)
			if i == j or radius2 <= 0.0:
				continue
			var grad: Vector3 = diff * gradient_coefficient * pow(normalized, 2.0)
			rate += mass * (v[i] - v[j]).dot(grad)
		sum_error += maxf((density + delta * rate) / rest_density - 1.0, 0.0)
	return sum_error / float(p.size())


func _run() -> void:
	var baseline := _make_fluid(0)
	var active := _make_fluid(8)
	var replica := _make_fluid(8)

	var dt := 1.0 / 60.0
	var starting_error: float = _predicted_density_error(
			baseline.get_particle_positions(),
			baseline.get_particle_velocities(),
			dt, 6.0, 1000.0, 0.42)
	var stepped := active.step(dt)
	stepped = baseline.step(dt) and stepped
	stepped = replica.step(dt) and stepped

	var final_error: float = active.get_average_predicted_density_error()
	var pressure_reduced := starting_error > 0.01
	pressure_reduced = pressure_reduced and final_error < starting_error * 0.5
	var iterations_ok := active.get_last_density_pressure_iterations() > 0
	iterations_ok = iterations_ok and active.get_last_density_pressure_iterations() <= 8
	var neighbors: int = active.get_last_density_pressure_neighbor_evaluations()
	var neighbor_budget := neighbors > 0 and neighbors <= 18 * 125 * 128
	var baseline_no_work := baseline.get_last_density_pressure_iterations() == 0
	baseline_no_work = baseline_no_work and baseline.get_last_density_pressure_neighbor_evaluations() == 0
	var deterministic := active.get_particle_positions() == replica.get_particle_positions()
	deterministic = deterministic and active.get_particle_velocities() == replica.get_particle_velocities()
	var changed := active.get_particle_positions() != baseline.get_particle_positions()

	var finite := stepped and is_finite(final_error)
	for pos in active.get_particle_positions():
		finite = finite and pos.is_finite()
		finite = finite and pos.x >= -2.001 and pos.x <= 2.001
		finite = finite and pos.y >= 0.0 and pos.y <= 4.001
		finite = finite and pos.z >= -2.001 and pos.z <= 2.001
	for v in active.get_particle_velocities():
		finite = finite and v.is_finite()

	# A multi-step soak ensures the pressure predictor and PBF position
	# projection can run sequentially without NaN, cross-buffer corruption,
	# or leaving their configured local tank.
	for frame in range(15):
		finite = active.step(dt) and finite
		finite = replica.step(dt) and finite
	var deterministic_soak := active.get_particle_positions() == replica.get_particle_positions()

	active.clear_particles()
	var clear_ok := active.get_last_density_pressure_iterations() == 0
	clear_ok = clear_ok and active.get_last_density_pressure_neighbor_evaluations() == 0
	clear_ok = clear_ok and active.get_average_predicted_density_error() == 0.0
	baseline.queue_free()
	active.queue_free()
	replica.queue_free()

	if not (finite and pressure_reduced and iterations_ok and neighbor_budget and
			baseline_no_work and deterministic and deterministic_soak and changed and clear_ok):
		printerr("Native PBF density pressure FAILED: before=", starting_error,
				" final=", final_error, " finite=", finite, " reduced=", pressure_reduced,
				" iter=", iterations_ok, " neighbors=", neighbors,
				" opt_out=", baseline_no_work, " deterministic=", deterministic,
				" soak=", deterministic_soak, " changed=", changed,
				" clear=", clear_ok)
		quit(1)
		return
	print("Native PBF predictive density pressure passed: initial_error=", starting_error,
			" projected_error=", final_error, " particles=125, deterministic=YES")
	quit(0)
