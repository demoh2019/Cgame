/**************************************************************************/
/*  pbf_particle_fluid_3d.h                                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3i.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"
#include "scene/3d/node_3d.h"
#include "servers/physics_pbf_3d.h"
#include "servers/physics_pbf_rigid_coupling_3d.h"
#include "servers/physics_pbf_vorticity_3d.h"
#include "servers/physics_pbf_divergence_3d.h"
#include "servers/physics_pbf_density_pressure_3d.h"

// Experimental CPU PBF fluid: a scene node (not a PhysicsServer3D backend
// replacement) using density constraints, finite-support SPH kernels and
// sorted cell-neighbor search. Only allocates persistent particle buffers
// when users explicitly initialize particles. Disabled by default.
//
// Positions and velocities are in this Node3D's LOCAL space; the optional
// rigid-body collision sweep transforms them through get_global_transform().
class PBFParticleFluid3D : public Node3D {
	GDCLASS(PBFParticleFluid3D, Node3D);

	static constexpr int MAX_PARTICLES = 2048;
	static constexpr int MAX_NEIGHBORS = 128;

	Vector<Vector3> positions;
	Vector<Vector3> velocities;
	Vector<Vector3> predicted;
	Vector<Vector3> corrections;
	Vector<Vector3> smoothed_velocities;
	Vector<Vector3> vorticities;
	Vector<Vector3> confinement_updates;
	Vector<Vector3> divergence_velocity_changes;
	Vector<real_t> divergence_multipliers;
	Vector<Vector3> density_pressure_velocities;
	Vector<Vector3> density_pressure_corrections;
	Vector<real_t> density_pressure_multipliers;
	Vector<real_t> density_pressure_denominators;
	Vector<real_t> lambdas;
	Vector<real_t> densities;
	Vector<PhysicsPBFCell3D> cells;

	bool simulation_enabled = false;
	bool collide_with_bodies = false;
	bool two_way_rigid_coupling = false;
	real_t max_rigid_impulse = 20.0;
	uint64_t last_rigid_impulses = 0;
	int collision_mask = 1;
	int solver_iterations = 4;
	real_t smoothing_radius = 0.32;
	real_t rest_density = 1000.0;
	real_t particle_mass = 6.0;
	real_t particle_radius = 0.055;
	real_t artificial_pressure = 0.002;
	real_t xsph_viscosity = 0.015;
	real_t vorticity_confinement = 0.0;
	real_t vorticity_max_velocity_change = 0.12;
	real_t average_vorticity = 0.0;
	int density_pressure_iterations = 0;
	real_t density_pressure_tolerance = 0.002;
	real_t density_pressure_relaxation = 0.8;
	real_t density_pressure_max_velocity_change = 0.15;
	real_t average_predicted_density_error = 0.0;
	int last_density_pressure_iterations = 0;
	uint64_t last_density_pressure_neighbor_evaluations = 0;
	int divergence_iterations = 0;
	real_t divergence_tolerance = 0.01;
	real_t divergence_relaxation = 0.8;
	real_t divergence_max_velocity_change = 0.12;
	real_t average_positive_density_rate = 0.0;
	int last_divergence_iterations = 0;
	uint64_t last_divergence_neighbor_evaluations = 0;
	uint64_t last_vorticity_neighbor_evaluations = 0;
	real_t boundary_restitution = 0.1;
	Vector3 gravity = Vector3(0, -9.8, 0);
	Vector3 box_min = Vector3(-2, 0, -2);
	Vector3 box_max = Vector3(2, 4, 2);

	real_t average_density = 0.0;
	uint64_t last_neighbor_evaluations = 0;

	void _resize_buffers(int p_count);
	void _update_grid();
	void _solve_density_constraints();
	void _apply_density_corrections();
	void _apply_xsph_viscosity();
	void _apply_vorticity_confinement(real_t p_delta);
	void _project_predictive_density_pressure(real_t p_delta);
	real_t _measure_predicted_density_error(real_t p_delta);
	void _project_velocity_divergence();
	real_t _measure_positive_density_rate();
	void _resolve_world_collisions(const Vector3 &p_old, Vector3 &r_predicted, Vector3 &r_velocity);
	void _step_once(real_t p_delta);
protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void set_simulation_enabled(bool p_enabled);
	bool is_simulation_enabled() const { return simulation_enabled; }

	void set_collide_with_bodies(bool p_enabled) { collide_with_bodies = p_enabled; }
	bool is_collide_with_bodies_enabled() const { return collide_with_bodies; }
	void set_two_way_rigid_coupling(bool p_enabled) { two_way_rigid_coupling = p_enabled; }
	bool is_two_way_rigid_coupling_enabled() const { return two_way_rigid_coupling; }
	void set_max_rigid_impulse(real_t p_maximum);
	real_t get_max_rigid_impulse() const { return max_rigid_impulse; }
	int get_last_rigid_impulses() const { return int(MIN(last_rigid_impulses, uint64_t(2147483647))); }
	void set_collision_mask(int p_mask) { collision_mask = p_mask; }
	int get_collision_mask() const { return collision_mask; }

	void set_solver_iterations(int p_iterations);
	int get_solver_iterations() const { return solver_iterations; }
	void set_smoothing_radius(real_t p_radius);
	real_t get_smoothing_radius() const { return smoothing_radius; }
	void set_rest_density(real_t p_density);
	real_t get_rest_density() const { return rest_density; }
	void set_particle_mass(real_t p_mass);
	real_t get_particle_mass() const { return particle_mass; }
	void set_particle_radius(real_t p_radius);
	real_t get_particle_radius() const { return particle_radius; }
	void set_artificial_pressure(real_t p_strength);
	real_t get_artificial_pressure() const { return artificial_pressure; }
	void set_xsph_viscosity(real_t p_viscosity);
	real_t get_xsph_viscosity() const { return xsph_viscosity; }
	void set_density_pressure_iterations(int p_iterations);
	int get_density_pressure_iterations() const { return density_pressure_iterations; }
	void set_density_pressure_tolerance(real_t p_tolerance);
	real_t get_density_pressure_tolerance() const { return density_pressure_tolerance; }
	void set_density_pressure_relaxation(real_t p_relaxation);
	real_t get_density_pressure_relaxation() const { return density_pressure_relaxation; }
	void set_density_pressure_max_velocity_change(real_t p_maximum);
	real_t get_density_pressure_max_velocity_change() const { return density_pressure_max_velocity_change; }
	real_t get_average_predicted_density_error() const { return average_predicted_density_error; }
	int get_last_density_pressure_iterations() const { return last_density_pressure_iterations; }
	int get_last_density_pressure_neighbor_evaluations() const { return int(MIN(last_density_pressure_neighbor_evaluations, uint64_t(2147483647))); }
	void set_divergence_iterations(int p_iterations);
	int get_divergence_iterations() const { return divergence_iterations; }
	void set_divergence_tolerance(real_t p_tolerance);
	real_t get_divergence_tolerance() const { return divergence_tolerance; }
	void set_divergence_relaxation(real_t p_relaxation);
	real_t get_divergence_relaxation() const { return divergence_relaxation; }
	void set_divergence_max_velocity_change(real_t p_maximum);
	real_t get_divergence_max_velocity_change() const { return divergence_max_velocity_change; }
	real_t get_average_positive_density_rate() const { return average_positive_density_rate; }
	int get_last_divergence_iterations() const { return last_divergence_iterations; }
	int get_last_divergence_neighbor_evaluations() const { return int(MIN(last_divergence_neighbor_evaluations, uint64_t(2147483647))); }
	void set_vorticity_confinement(real_t p_strength);
	real_t get_vorticity_confinement() const { return vorticity_confinement; }
	void set_vorticity_max_velocity_change(real_t p_maximum);
	real_t get_vorticity_max_velocity_change() const { return vorticity_max_velocity_change; }
	void set_boundary_restitution(real_t p_restitution);
	real_t get_boundary_restitution() const { return boundary_restitution; }
	void set_gravity(const Vector3 &p_gravity);
	Vector3 get_gravity() const { return gravity; }
	void set_box_min(const Vector3 &p_bounds);
	Vector3 get_box_min() const { return box_min; }
	void set_box_max(const Vector3 &p_bounds);
	Vector3 get_box_max() const { return box_max; }

	bool set_particle_positions(const PackedVector3Array &p_positions);
	bool create_block(const Vector3 &p_origin, const Vector3i &p_dimensions, real_t p_spacing);
	PackedVector3Array get_particle_positions() const;
	PackedVector3Array get_particle_velocities() const;
	void clear_particles();
	int add_velocity_pulse(const Vector3 &p_center, real_t p_radius, const Vector3 &p_delta_velocity);
	int get_particle_count() const { return positions.size(); }
	real_t get_average_density() const { return average_density; }
	real_t get_average_vorticity() const { return average_vorticity; }
	int get_last_vorticity_neighbor_evaluations() const { return int(MIN(last_vorticity_neighbor_evaluations, uint64_t(2147483647))); }
	int get_last_neighbor_evaluations() const { return int(MIN(last_neighbor_evaluations, uint64_t(2147483647))); }

	bool step(real_t p_delta);

	PBFParticleFluid3D() = default;
};
