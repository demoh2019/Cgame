# Native Godot PBF velocity-divergence correction integration.
# Three identical manually stepped particle fluids (baseline, enabled,
# enabled replica), plus independent brute-force SPH compression estimate.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_fluid(velocity_iterations: int) -> PBFParticleFluid3D:
	var fluid := PBFParticleFluid3D.new()
	fluid.name = "FluidDivergence%d" % velocity_iterations
	fluid.gravity = Vector3.ZERO
	fluid.xsph_viscosity = 0.0
	fluid.vorticity_confinement = 0.0
	fluid.smoothing_radius = 0.42
	fluid.solver_iterations = 4
	fluid.divergence_iterations = velocity_iterations
	fluid.divergence_tolerance = 0.0
	fluid.divergence_relaxation = 0.9
	fluid.divergence_max_velocity_change = 0.12
	root.add_child(fluid)
	assert(fluid.create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19))
	assert(fluid.add_velocity_pulse(Vector3(-0.6, 1.38, 0), 1.0, Vector3(5, 0, 0)) > 0)
	assert(fluid.add_velocity_pulse(Vector3(0.6, 1.38, 0), 1.0, Vector3(-5, 0, 0)) > 0)
	return fluid


# Deliberately compute an independent all-pairs SPH continuity residual
# rather than trusting the native fluid's own metric/cell lookup.
func _positive_rate_reference(fluid: PBFParticleFluid3D) -> float:
	var p := fluid.get_particle_positions()
	var v := fluid.get_particle_velocities()
	var h: float = fluid.smoothing_radius
	var h2: float = h * h
	var gradient_factor: float = -945.0 / (32.0 * PI * pow(h, 5.0))
	var density: float = fluid.rest_density
	var mass: float = fluid.particle_mass
	var mean := 0.0
	for i in range(p.size()):
		var rate := 0.0
		for j in range(p.size()):
			if i == j:
				continue
			var d: Vector3 = p[i] - p[j]
			var d2: float = d.length_squared()
			if d2 <= 0.0 or d2 >= h2:
				continue
			var g: Vector3 = d * gradient_factor * pow(1.0 - d2 / h2, 2.0)
			rate += mass * (v[i] - v[j]).dot(g)
		mean += maxf(rate / density, 0.0)
	return mean / float(p.size())


func _run() -> void:
	var baseline := _make_fluid(0)
	var active := _make_fluid(8)
	var replica := _make_fluid(8)

	var stepped := baseline.step(1.0 / 120.0)
	stepped = active.step(1.0 / 120.0) and stepped
	stepped = replica.step(1.0 / 120.0) and stepped

	var reference_before: float = _positive_rate_reference(baseline)
	var reference_after: float = _positive_rate_reference(active)
	var reference_replica: float = _positive_rate_reference(replica)
	var reduced := reference_before > 0.01
	reduced = reduced and reference_after < reference_before * 0.98
	var metrics := active.get_average_positive_density_rate() >= 0.0
	metrics = metrics and active.get_last_divergence_iterations() > 0
	metrics = metrics and active.get_last_divergence_iterations() <= 8
	metrics = metrics and active.get_last_divergence_neighbor_evaluations() > 0
	metrics = metrics and active.get_last_divergence_neighbor_evaluations() <= 17 * 125 * 128
	var baseline_disabled := baseline.get_last_divergence_neighbor_evaluations() == 0
	baseline_disabled = baseline_disabled and baseline.get_average_positive_density_rate() == 0.0
	var deterministic := active.get_particle_velocities() == replica.get_particle_velocities()
	deterministic = deterministic and active.get_particle_positions() == replica.get_particle_positions()
	var finite := stepped and is_finite(reference_before) and is_finite(reference_after)
	finite = finite and is_finite(reference_replica)
	for v in active.get_particle_velocities():
		finite = finite and v.is_finite()
	for p in active.get_particle_positions():
		finite = finite and p.is_finite()
		finite = finite and p.x >= -2.001 and p.x <= 2.001
		finite = finite and p.y >= 0.0 and p.y <= 4.001
		finite = finite and p.z >= -2.001 and p.z <= 2.001

	active.clear_particles()
	var cleared := active.get_average_positive_density_rate() == 0.0
	cleared = cleared and active.get_last_divergence_iterations() == 0
	cleared = cleared and active.get_last_divergence_neighbor_evaluations() == 0
	baseline.queue_free()
	active.queue_free()
	replica.queue_free()

	if not (finite and reduced and metrics and baseline_disabled and deterministic and cleared):
		printerr("Native PBF divergence FAILED: finite=", finite,
				" before=", reference_before, " after=", reference_after,
				" metrics=", metrics, " opt_out=", baseline_disabled,
				" deterministic=", deterministic, " cleared=", cleared)
		quit(1)
		return
	print("Native PBF divergence passed: 125 particles, before=", reference_before,
			" after=", reference_after, " independent SPH continuity residual")
	quit(0)
