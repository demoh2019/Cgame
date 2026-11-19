# Native CPU PBF stress: density search and solver throughput versus idle node.
# Run via tests/stress/run.py with physics_pbf_3d_disabled / enabled.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, enabled: bool, with_vorticity: bool = false, with_divergence: bool = false, with_density_pressure: bool = false) -> Dictionary:
	var fluid := PBFParticleFluid3D.new()
	fluid.name = "PBFStress"
	fluid.smoothing_radius = 0.32
	fluid.particle_mass = 6.0
	fluid.rest_density = 1000.0
	fluid.solver_iterations = 4
	fluid.xsph_viscosity = 0.02
	fluid.vorticity_confinement = 0.9 if with_vorticity else 0.0
	fluid.vorticity_max_velocity_change = 0.12
	fluid.divergence_iterations = 8 if with_divergence else 0
	fluid.divergence_tolerance = 0.01
	fluid.divergence_max_velocity_change = 0.12
	fluid.density_pressure_iterations = 8 if with_density_pressure else 0
	fluid.density_pressure_tolerance = 0.002
	fluid.density_pressure_max_velocity_change = 0.15
	fluid.box_min = Vector3(-2.0, 0.0, -2.0)
	fluid.box_max = Vector3(2.0, 4.0, 2.0)
	tree.root.add_child(fluid)

	var nx := mini(4 * scale, 16)
	var nz := mini(4 * scale, 16)
	var ny := mini(4 + scale, 8)
	var create_start := Time.get_ticks_usec()
	var created := fluid.create_block(Vector3(-1.6, 1.4, -1.6),
			Vector3i(nx, ny, nz), 0.195)
	if not created:
		fluid.queue_free()
		return {"error": "Native PBF liquid block could not be initialized"}
	var creation_ms := float(Time.get_ticks_usec() - create_start) / 1000.0
	var count := fluid.get_particle_count()
	fluid.simulation_enabled = enabled

	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	var peak_physics_ms := 0.0
	var neighbor_checks := 0
	var vortex_neighbor_checks := 0
	var peak_average_vorticity := 0.0
	var divergence_neighbors := 0
	var peak_divergence_iterations := 0
	var peak_compressive_rate := 0.0
	var pressure_neighbors := 0
	var peak_pressure_iterations := 0
	var peak_predicted_density_error := 0.0
	var error := ""
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		neighbor_checks = maxi(neighbor_checks, fluid.get_last_neighbor_evaluations())
		vortex_neighbor_checks = maxi(vortex_neighbor_checks, fluid.get_last_vorticity_neighbor_evaluations())
		peak_average_vorticity = maxf(peak_average_vorticity, fluid.get_average_vorticity())
		divergence_neighbors = maxi(divergence_neighbors, fluid.get_last_divergence_neighbor_evaluations())
		peak_divergence_iterations = maxi(peak_divergence_iterations, fluid.get_last_divergence_iterations())
		peak_compressive_rate = maxf(peak_compressive_rate, fluid.get_average_positive_density_rate())
		pressure_neighbors = maxi(pressure_neighbors, fluid.get_last_density_pressure_neighbor_evaluations())
		peak_pressure_iterations = maxi(peak_pressure_iterations, fluid.get_last_density_pressure_iterations())
		peak_predicted_density_error = maxf(peak_predicted_density_error, fluid.get_average_predicted_density_error())
		if frame % 10 == 0:
			var positions := fluid.get_particle_positions()
			for i in [0, int(count / 2), count - 1]:
				var position: Vector3 = positions[i]
				if not position.is_finite() or position.y < -0.01 or position.y > 4.01:
					error = "Nonfinite or escaped native PBF particle"
					break
		if error != "":
			break
	fluid.simulation_enabled = false
	fluid.queue_free()
	if error != "":
		return {"error": error}
	var stats: Dictionary = tree.call("_frame_statistics", intervals)
	return {
		"fluid_enabled": enabled,
		"vorticity_enabled": with_vorticity,
		"divergence_enabled": with_divergence,
		"density_pressure_enabled": with_density_pressure,
		"density_pressure_neighbor_evaluations_per_substep": pressure_neighbors,
		"density_pressure_max_iterations_used": peak_pressure_iterations,
		"peak_predicted_density_error": peak_predicted_density_error,
		"divergence_neighbor_evaluations_per_substep": divergence_neighbors,
		"divergence_max_iterations_used": peak_divergence_iterations,
		"peak_positive_density_rate": peak_compressive_rate,
		"vorticity_neighbors_per_substep": vortex_neighbor_checks,
		"peak_average_vorticity": peak_average_vorticity,
		"particle_count": count,
		"physics_frames": frames,
		"neighbor_evaluations_per_substep": neighbor_checks,
		"creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
	}
