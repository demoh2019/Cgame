# Real registered native PBF scene-node smoke for vorticity restoration.
# Compare two identical 125-particle liquid tanks with the same shear
# pulses: one with vorticity enabled, one with the original disabled path.
# An enabled replica must remain exactly deterministic.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_fluid(vorticity: float) -> PBFParticleFluid3D:
	var fluid := PBFParticleFluid3D.new()
	fluid.gravity = Vector3.ZERO
	fluid.xsph_viscosity = 0.0
	fluid.smoothing_radius = 0.42
	fluid.solver_iterations = 4
	fluid.vorticity_confinement = vorticity
	fluid.vorticity_max_velocity_change = 0.12
	root.add_child(fluid)
	if not fluid.create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19):
		push_error("Cannot initialize native PBF shear tank")
	var center_a := Vector3(-0.25, 1.38, 0.0)
	var center_b := Vector3(0.25, 1.38, 0.0)
	fluid.add_velocity_pulse(center_a, 1.0, Vector3(0, 0, 4))
	fluid.add_velocity_pulse(center_b, 1.0, Vector3(0, 0, -4))
	return fluid


func _run() -> void:
	var disabled := _make_fluid(0.0)
	var enabled := _make_fluid(0.9)
	var replica := _make_fluid(0.9)
	var finite := true
	for frame in range(12):
		finite = finite and disabled.step(1.0 / 60.0)
		finite = finite and enabled.step(1.0 / 60.0)
		finite = finite and replica.step(1.0 / 60.0)
		if not finite:
			break

	var a := disabled.get_particle_velocities()
	var b := enabled.get_particle_velocities()
	var c := replica.get_particle_velocities()
	var original_path := disabled.get_average_vorticity() == 0.0
	original_path = original_path and disabled.get_last_vorticity_neighbor_evaluations() == 0
	var enabled_path := enabled.get_average_vorticity() > 0.001
	enabled_path = enabled_path and enabled.get_last_vorticity_neighbor_evaluations() > 0
	enabled_path = enabled_path and enabled.get_last_vorticity_neighbor_evaluations() <= 3 * 125 * 128
	var deterministic := b == c
	deterministic = deterministic and enabled.get_particle_positions() == replica.get_particle_positions()
	var changed := false
	for i in range(125):
		finite = finite and a[i].is_finite() and b[i].is_finite() and c[i].is_finite()
		if b[i].distance_to(a[i]) > 0.00001:
			changed = true
	for p in enabled.get_particle_positions():
		finite = finite and p.is_finite()
		finite = finite and p.x >= -2.001 and p.x <= 2.001
		finite = finite and p.y >= 0.0 and p.y <= 4.001
		finite = finite and p.z >= -2.001 and p.z <= 2.001

	enabled.clear_particles()
	var counters_reset := enabled.get_average_vorticity() == 0.0
	counters_reset = counters_reset and enabled.get_last_vorticity_neighbor_evaluations() == 0
	disabled.queue_free()
	enabled.queue_free()
	replica.queue_free()

	if not (finite and original_path and enabled_path and deterministic and changed and counters_reset):
		printerr("Native PBF vorticity FAILED: finite=", finite,
				" baseline=", original_path,
				" active=", enabled_path,
				" deterministic=", deterministic,
				" changed=", changed,
				" reset=", counters_reset)
		quit(1)
		return
	print("Native PBF vorticity passed: 125 particles, 12 substeps, bounded curl and deterministic updates")
	quit(0)
