# Native Godot headless regression for opt-in SPH free-surface tension.
# Identical 125-particle initial states: original PBF, surface model,
# and a second surface-enabled replica for exact same-seed determinism.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_fluid(enabled: bool) -> PBFParticleFluid3D:
	var fluid := PBFParticleFluid3D.new()
	fluid.gravity = Vector3.ZERO
	fluid.xsph_viscosity = 0.0
	fluid.smoothing_radius = 0.42
	fluid.vorticity_confinement = 0.0
	fluid.divergence_iterations = 0
	fluid.density_pressure_iterations = 0
	fluid.surface_cohesion = 0.06 if enabled else 0.0
	fluid.surface_curvature = 0.025 if enabled else 0.0
	fluid.surface_max_pair_velocity_change = 0.005
	root.add_child(fluid)
	assert(fluid.create_block(Vector3(-0.38, 1.0, -0.38),
			Vector3i(5, 5, 5), 0.19))
	return fluid


func _velocity_difference(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var difference := 0.0
	for i in range(a.size()):
		difference += (a[i] - b[i]).length()
	return difference


func _total_velocity(a: PackedVector3Array) -> Vector3:
	var total := Vector3.ZERO
	for v in a:
		total += v
	return total


func _run() -> void:
	var base := _make_fluid(false)
	var surface := _make_fluid(true)
	var replica := _make_fluid(true)

	var dt := 1.0 / 60.0
	var stepped := base.step(dt)
	stepped = surface.step(dt) and stepped
	stepped = replica.step(dt) and stepped

	var active_pairs := surface.get_last_surface_tension_pairs()
	var active_neighbors := surface.get_last_surface_tension_neighbor_evaluations()
	var active_normals := surface.get_mean_surface_normal_magnitude()
	var active := active_pairs > 0 and active_pairs <= 125 * 128
	active = active and active_neighbors > 0
	active = active and active_neighbors <= 3 * 125 * 128
	active = active and active_normals > 0.05
	var disabled := base.get_last_surface_tension_pairs() == 0
	disabled = disabled and base.get_last_surface_tension_neighbor_evaluations() == 0
	disabled = disabled and base.get_mean_surface_normal_magnitude() == 0.0

	# Forces are applied after PBF position correction: the first frame
	# must have identical positions, but different final velocities.
	var unchanged_positions := base.get_particle_positions() == surface.get_particle_positions()
	var velocities_changed := _velocity_difference(
			base.get_particle_velocities(), surface.get_particle_velocities()) > 0.01
	var momentum_delta := _total_velocity(surface.get_particle_velocities()) - 			_total_velocity(base.get_particle_velocities())
	var conserved := momentum_delta.length() < 0.005
	var deterministic := surface.get_particle_velocities() == replica.get_particle_velocities()
	deterministic = deterministic and surface.get_particle_positions() == replica.get_particle_positions()

	var finite := stepped
	for i in range(12):
		finite = base.step(dt) and finite
		finite = surface.step(dt) and finite
		finite = replica.step(dt) and finite
		if not finite:
			break
	for p in surface.get_particle_positions():
		finite = finite and p.is_finite()
		finite = finite and p.x >= -2.001 and p.x <= 2.001
		finite = finite and p.y >= 0.0 and p.y <= 4.001
		finite = finite and p.z >= -2.001 and p.z <= 2.001
	for v in surface.get_particle_velocities():
		finite = finite and v.is_finite()
	deterministic = deterministic and surface.get_particle_positions() == replica.get_particle_positions()
	deterministic = deterministic and surface.get_particle_velocities() == replica.get_particle_velocities()
	var positions_changed := base.get_particle_positions() != surface.get_particle_positions()

	surface.surface_cohesion = 0.0
	surface.surface_curvature = 0.0
	var freed := surface.get_last_surface_tension_pairs() == 0
	freed = freed and surface.get_last_surface_tension_neighbor_evaluations() == 0
	freed = freed and surface.get_mean_surface_normal_magnitude() == 0.0
	freed = freed and surface.step(dt)
	freed = freed and surface.get_last_surface_tension_pairs() == 0
	surface.surface_cohesion = 0.06
	freed = freed and surface.step(dt)
	freed = freed and surface.get_last_surface_tension_pairs() > 0
	surface.clear_particles()
	freed = freed and surface.get_last_surface_tension_pairs() == 0
	freed = freed and surface.get_last_surface_tension_neighbor_evaluations() == 0
	base.queue_free()
	surface.queue_free()
	replica.queue_free()
	if not (finite and active and disabled and unchanged_positions and
			velocities_changed and conserved and deterministic and positions_changed and freed):
		printerr("PBF SURFACE FAILED: finite=",finite," active=",active,
				" disabled=",disabled," first_positions=",unchanged_positions,
				" changed_v=",velocities_changed," impulse_residual=",momentum_delta,
				" deterministic=",deterministic," positions_changed=",positions_changed,
				" toggle=",freed, " pairs=",active_pairs," neighbors=",active_neighbors)
		quit(1)
		return
	print("Native PBF surface tension passed: 125 particles, 12-step soak, paired impulses, ",
			"pairs=",active_pairs," normals=",active_normals)
	quit(0)
