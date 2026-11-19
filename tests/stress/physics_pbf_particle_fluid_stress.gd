# Native CPU PBF stress: density search and solver throughput versus idle node.
# Run via tests/stress/run.py with physics_pbf_3d_disabled / enabled.
extends RefCounted


func run(tree: SceneTree, scale: int, frames: int, enabled: bool) -> Dictionary:
	var fluid := PBFParticleFluid3D.new()
	fluid.name = "PBFStress"
	fluid.smoothing_radius = 0.32
	fluid.particle_mass = 6.0
	fluid.rest_density = 1000.0
	fluid.solver_iterations = 4
	fluid.xsph_viscosity = 0.02
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
	var error := ""
	for frame in range(frames):
		await tree.physics_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		peak_physics_ms = maxf(peak_physics_ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		neighbor_checks = maxi(neighbor_checks, fluid.get_last_neighbor_evaluations())
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
		"particle_count": count,
		"physics_frames": frames,
		"neighbor_evaluations_per_substep": neighbor_checks,
		"creation_ms": creation_ms,
		"peak_physics_ms": peak_physics_ms,
		"frame_interval_ms": stats,
		"frame_p95_ms": stats["p95"],
	}
