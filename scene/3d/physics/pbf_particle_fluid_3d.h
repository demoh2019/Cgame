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
	Vector<real_t> lambdas;
	Vector<real_t> densities;
	Vector<PhysicsPBFCell3D> cells;

	bool simulation_enabled = false;
	bool collide_with_bodies = false;
	int collision_mask = 1;
	int solver_iterations = 4;
	real_t smoothing_radius = 0.32;
	real_t rest_density = 1000.0;
	real_t particle_mass = 6.0;
	real_t particle_radius = 0.055;
	real_t artificial_pressure = 0.002;
	real_t xsph_viscosity = 0.015;
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
	int get_particle_count() const { return positions.size(); }
	real_t get_average_density() const { return average_density; }
	int get_last_neighbor_evaluations() const { return int(MIN(last_neighbor_evaluations, uint64_t(2147483647))); }

	bool step(real_t p_delta);

	PBFParticleFluid3D() = default;
};
