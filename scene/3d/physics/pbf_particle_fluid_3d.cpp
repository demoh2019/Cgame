/**************************************************************************/
/*  pbf_particle_fluid_3d.cpp                                             */
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
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "pbf_particle_fluid_3d.h"

#include "core/object/class_db.h"
#include "scene/resources/world_3d.h"
#include "servers/physics_3d/physics_direct_space_state_3d.h"
#include "servers/physics_3d/physics_server_3d.h"

namespace {

static _FORCE_INLINE_ PhysicsPBFCell3D _pbf_cell(const Vector3 &p_position, real_t p_h, int p_index) {
	PhysicsPBFCell3D result;
	result.x = int(Math::floor(p_position.x / p_h));
	result.y = int(Math::floor(p_position.y / p_h));
	result.z = int(Math::floor(p_position.z / p_h));
	result.index = p_index;
	return result;
}

template <typename F>
static _FORCE_INLINE_ void _pbf_for_neighbors(
		const PhysicsPBFCell3D *p_cells, const Vector3 *p_positions, int p_count,
		int p_particle, real_t p_h, int p_neighbor_limit, F p_function) {
	const PhysicsPBFCell3D cell = _pbf_cell(p_positions[p_particle], p_h, p_particle);
	const double h2 = double(p_h) * double(p_h);
	int count = 0;
	for (int dx = -1; dx <= 1; ++dx) {
		for (int dy = -1; dy <= 1; ++dy) {
			for (int dz = -1; dz <= 1; ++dz) {
				const int cx = cell.x + dx;
				const int cy = cell.y + dy;
				const int cz = cell.z + dz;
				int first = physics_pbf_find_cell_begin_3d(p_cells, p_count, cx, cy, cz);
				while (first < p_count) {
					const PhysicsPBFCell3D &entry = p_cells[first++];
					if (entry.x != cx || entry.y != cy || entry.z != cz) {
						break;
					}
					if (entry.index == p_particle) {
						continue;
					}
					const Vector3 d = p_positions[p_particle] - p_positions[entry.index];
					const double squared = double(d.x) * double(d.x) +
							double(d.y) * double(d.y) + double(d.z) * double(d.z);
					if (squared >= h2 || !Math::is_finite(squared)) {
						continue;
					}
					p_function(entry.index, d, squared);
					++count;
					if (count == p_neighbor_limit) {
						return;
					}
				}
			}
		}
	}
}

} // namespace

void PBFParticleFluid3D::_resize_buffers(int p_count) {
	positions.resize(p_count);
	velocities.resize(p_count);
	predicted.resize(p_count);
	corrections.resize(p_count);
	smoothed_velocities.resize(p_count);
	lambdas.resize(p_count);
	densities.resize(p_count);
	cells.resize(p_count);
}

void PBFParticleFluid3D::_update_grid() {
	const int count = predicted.size();
	const Vector3 *particle_positions = predicted.ptr();
	PhysicsPBFCell3D *grid = cells.ptrw();
	for (int i = 0; i < count; ++i) {
		grid[i] = _pbf_cell(particle_positions[i], smoothing_radius, i);
	}
	cells.sort();
}

void PBFParticleFluid3D::_solve_density_constraints() {
	const int count = predicted.size();
	const PhysicsPBFCell3D *grid = cells.ptr();
	const Vector3 *points = predicted.ptr();
	real_t *rho = densities.ptrw();
	real_t *lambda = lambdas.ptrw();
	const double h = double(smoothing_radius);
	const double m = double(particle_mass);
	const double mass_over_rho = m / double(rest_density);
	const double self_density = m * double(PhysicsPBFKernel3D::poly6(0.0, h));
	double density_sum = 0.0;
	for (int i = 0; i < count; ++i) {
		double density = self_density;
		Vector3 sum_gradient;
		double sum_squares = 0.0;
		_pbf_for_neighbors(grid, points, count, i, smoothing_radius, MAX_NEIGHBORS,
				[&](int p_j, const Vector3 &p_d, double p_d2) {
					density += m * double(PhysicsPBFKernel3D::poly6(p_d2, h));
					const Vector3 gradient = PhysicsPBFKernel3D::gradient(p_d, h) * real_t(mass_over_rho);
					sum_gradient += gradient;
					sum_squares += double(gradient.length_squared());
					++last_neighbor_evaluations;
				});
		sum_squares += double(sum_gradient.length_squared());
		const double constraint = MAX(density / double(rest_density) - 1.0, 0.0);
		const double multiplier = -constraint / (sum_squares + 1e-6);
		rho[i] = real_t(density);
		lambda[i] = Math::is_finite(multiplier) ? real_t(CLAMP(multiplier, -1e6, 0.0)) : real_t(0.0);
		density_sum += density;
	}
	average_density = count > 0 ? real_t(density_sum / double(count)) : real_t(0.0);
}

void PBFParticleFluid3D::_apply_density_corrections() {
	const int count = predicted.size();
	const PhysicsPBFCell3D *grid = cells.ptr();
	const Vector3 *points = predicted.ptr();
	const real_t *lambda = lambdas.ptr();
	Vector3 *correction = corrections.ptrw();
	const double h = double(smoothing_radius);
	const real_t ratio = particle_mass / rest_density;
	const real_t max_correction = smoothing_radius * real_t(0.22);
	for (int i = 0; i < count; ++i) {
		Vector3 shift;
		_pbf_for_neighbors(grid, points, count, i, smoothing_radius, MAX_NEIGHBORS,
				[&](int p_j, const Vector3 &p_d, double p_d2) {
					const real_t scorr = PhysicsPBFKernel3D::artificial_pressure(p_d2, h, artificial_pressure);
					const Vector3 gradient = PhysicsPBFKernel3D::gradient(p_d, h);
					shift += gradient * (lambda[i] + lambda[p_j] + scorr);
				});
		shift *= ratio;
		if (!shift.is_finite()) {
			shift = Vector3();
		} else if (shift.length_squared() > max_correction * max_correction) {
			shift = shift.normalized() * max_correction;
		}
		correction[i] = shift;
	}

	Vector3 *w = predicted.ptrw();
	for (int i = 0; i < count; ++i) {
		Vector3 proposed = w[i] + correction[i];
		proposed.x = CLAMP(proposed.x, box_min.x + particle_radius, box_max.x - particle_radius);
		proposed.y = CLAMP(proposed.y, box_min.y + particle_radius, box_max.y - particle_radius);
		proposed.z = CLAMP(proposed.z, box_min.z + particle_radius, box_max.z - particle_radius);
		if (proposed.is_finite()) {
			w[i] = proposed;
		}
	}
}

void PBFParticleFluid3D::_apply_xsph_viscosity() {
	if (!(xsph_viscosity > 0.0)) {
		return;
	}
	_update_grid();
	const int count = predicted.size();
	const PhysicsPBFCell3D *grid = cells.ptr();
	const Vector3 *points = predicted.ptr();
	const Vector3 *v = velocities.ptr();
	const real_t *rho = densities.ptr();
	Vector3 *smoothed = smoothed_velocities.ptrw();
	for (int i = 0; i < count; ++i) {
		Vector3 velocity_correction;
		_pbf_for_neighbors(grid, points, count, i, smoothing_radius, MAX_NEIGHBORS,
				[&](int p_j, const Vector3 &p_d, double p_d2) {
					// Symmetric pair weight avoids smoothing on particles
					// with artificially tiny/free-surface density.
					const real_t density = MAX(rho[p_j], rest_density * real_t(0.1));
					const real_t weight = particle_mass * PhysicsPBFKernel3D::poly6(p_d2, smoothing_radius) / density;
					velocity_correction += (v[p_j] - v[i]) * weight;
				});
		const Vector3 result = v[i] + velocity_correction * xsph_viscosity;
		smoothed[i] = result.is_finite() ? result : v[i];
	}
	Vector3 *vel = velocities.ptrw();
	for (int i = 0; i < count; ++i) {
		vel[i] = smoothed[i];
	}
}

void PBFParticleFluid3D::_resolve_world_collisions(const Vector3 &p_old, Vector3 &r_position, Vector3 &r_velocity) {
	if (!collide_with_bodies || !is_inside_tree() || collision_mask == 0) {
		return;
	}
	const Ref<World3D> world = get_world_3d();
	if (world.is_null()) {
		return;
	}
	PhysicsDirectSpaceState3D *state = PhysicsServer3D::get_singleton()->space_get_direct_state(world->get_space());
	if (!state) {
		return;
	}
	const Transform3D world_transform = get_global_transform();
	PS3DT::RayParameters params;
	params.from = world_transform.xform(p_old);
	params.to = world_transform.xform(r_position);
	params.collision_mask = uint32_t(collision_mask);
	params.collide_with_bodies = true;
	params.collide_with_areas = false;
	PS3DT::RayResult hit;
	if (params.from.is_equal_approx(params.to) || !state->intersect_ray(params, hit) ||
			!hit.normal.is_finite() || !(hit.normal.length_squared() > real_t(0.0))) {
		return;
	}

	const Vector3 normal = hit.normal.normalized();
	const Vector3 proposed_world = hit.position + normal * particle_radius;
	const Vector3 proposed_local = world_transform.affine_inverse().xform(proposed_world);
	const Vector3 world_velocity = world_transform.basis.xform(r_velocity);
	const real_t normal_speed = world_velocity.dot(normal);
	Vector3 new_velocity = world_velocity;
	if (normal_speed < 0.0) {
		new_velocity -= normal * ((real_t(1.0) + boundary_restitution) * normal_speed);
	}
	const Vector3 local_velocity = world_transform.basis.inverse().xform(new_velocity);
	if (proposed_local.is_finite() && local_velocity.is_finite()) {
		r_position = proposed_local;
		r_velocity = local_velocity;
	}
}

void PBFParticleFluid3D::_step_once(real_t p_delta) {
	const int count = positions.size();
	const Vector3 *p = positions.ptr();
	const Vector3 *v = velocities.ptr();
	Vector3 *w = predicted.ptrw();
	last_neighbor_evaluations = 0;
	for (int i = 0; i < count; ++i) {
		const Vector3 new_velocity = v[i] + gravity * p_delta;
		Vector3 new_position = p[i] + new_velocity * p_delta;
		if (!new_position.is_finite()) {
			new_position = p[i];
		}
		new_position.x = CLAMP(new_position.x, box_min.x + particle_radius, box_max.x - particle_radius);
		new_position.y = CLAMP(new_position.y, box_min.y + particle_radius, box_max.y - particle_radius);
		new_position.z = CLAMP(new_position.z, box_min.z + particle_radius, box_max.z - particle_radius);
		w[i] = new_position;
	}

	for (int iteration = 0; iteration < solver_iterations; ++iteration) {
		_update_grid();
		_solve_density_constraints();
		_apply_density_corrections();
	}

	Vector3 *current = positions.ptrw();
	Vector3 *velocity = velocities.ptrw();
	w = predicted.ptrw();
	for (int i = 0; i < count; ++i) {
		const Vector3 old = current[i];
		Vector3 next = w[i];
		Vector3 next_velocity = (next - old) / p_delta;
		_resolve_world_collisions(old, next, next_velocity);
		// Keep all particles inside the local box after external sweeps.
		next.x = CLAMP(next.x, box_min.x + particle_radius, box_max.x - particle_radius);
		next.y = CLAMP(next.y, box_min.y + particle_radius, box_max.y - particle_radius);
		next.z = CLAMP(next.z, box_min.z + particle_radius, box_max.z - particle_radius);
		// A position boundary is a contact: only the outward normal
		// component reflects, never the tangential component.
		const real_t boundary_epsilon = real_t(1e-5);
		if ((next.x <= box_min.x + particle_radius + boundary_epsilon && next_velocity.x < 0.0) ||
				(next.x >= box_max.x - particle_radius - boundary_epsilon && next_velocity.x > 0.0)) {
			next_velocity.x *= -boundary_restitution;
		}
		if ((next.y <= box_min.y + particle_radius + boundary_epsilon && next_velocity.y < 0.0) ||
				(next.y >= box_max.y - particle_radius - boundary_epsilon && next_velocity.y > 0.0)) {
			next_velocity.y *= -boundary_restitution;
		}
		if ((next.z <= box_min.z + particle_radius + boundary_epsilon && next_velocity.z < 0.0) ||
				(next.z >= box_max.z - particle_radius - boundary_epsilon && next_velocity.z > 0.0)) {
			next_velocity.z *= -boundary_restitution;
		}
		if (!next.is_finite() || !next_velocity.is_finite()) {
			next = old;
			next_velocity = Vector3();
		}
		current[i] = next;
		velocity[i] = next_velocity;
		w[i] = next;
	}
	_apply_xsph_viscosity();
}

bool PBFParticleFluid3D::step(real_t p_delta) {
	if (!(p_delta > 0.0) || !Math::is_finite(p_delta) ||
			p_delta > real_t(8.0 / 60.0)) {
		return false;
	}
	if (positions.is_empty()) {
		return true;
	}
	const int substeps = CLAMP(int(Math::ceil(p_delta * real_t(60.0))), 1, 8);
	const real_t substep = p_delta / substeps;
	for (int s = 0; s < substeps; ++s) {
		_step_once(substep);
	}
	return true;
}

bool PBFParticleFluid3D::set_particle_positions(const PackedVector3Array &p_positions) {
	if (p_positions.size() > MAX_PARTICLES) {
		return false;
	}
	for (int i = 0; i < p_positions.size(); ++i) {
		const Vector3 p = p_positions[i];
		if (!p.is_finite() || Math::abs(p.x) > 10000.0 ||
				Math::abs(p.y) > 10000.0 || Math::abs(p.z) > 10000.0) {
			return false;
		}
	}
	_resize_buffers(p_positions.size());
	Vector3 *p = positions.ptrw();
	Vector3 *v = velocities.ptrw();
	for (int i = 0; i < p_positions.size(); ++i) {
		Vector3 point = p_positions[i];
		point.x = CLAMP(point.x, box_min.x + particle_radius, box_max.x - particle_radius);
		point.y = CLAMP(point.y, box_min.y + particle_radius, box_max.y - particle_radius);
		point.z = CLAMP(point.z, box_min.z + particle_radius, box_max.z - particle_radius);
		p[i] = point;
		v[i] = Vector3();
	}
	average_density = 0.0;
	last_neighbor_evaluations = 0;
	return true;
}

bool PBFParticleFluid3D::create_block(const Vector3 &p_origin, const Vector3i &p_dimensions, real_t p_spacing) {
	if (!p_origin.is_finite() || p_dimensions.x <= 0 || p_dimensions.y <= 0 ||
			p_dimensions.z <= 0 || p_dimensions.x > 32 || p_dimensions.y > 32 ||
			p_dimensions.z > 32 || !(p_spacing > 0.0) || !Math::is_finite(p_spacing)) {
		return false;
	}
	const int64_t count = int64_t(p_dimensions.x) * p_dimensions.y * p_dimensions.z;
	if (count > MAX_PARTICLES) {
		return false;
	}
	PackedVector3Array block;
	block.resize(int(count));
	Vector3 *points = block.ptrw();
	int index = 0;
	for (int y = 0; y < p_dimensions.y; ++y) {
		for (int z = 0; z < p_dimensions.z; ++z) {
			for (int x = 0; x < p_dimensions.x; ++x) {
				points[index++] = p_origin + Vector3(x, y, z) * p_spacing;
			}
		}
	}
	return set_particle_positions(block);
}

PackedVector3Array PBFParticleFluid3D::get_particle_positions() const {
	PackedVector3Array result;
	result.resize(positions.size());
	Vector3 *w = result.ptrw();
	const Vector3 *p = positions.ptr();
	for (int i = 0; i < positions.size(); ++i) {
		w[i] = p[i];
	}
	return result;
}

PackedVector3Array PBFParticleFluid3D::get_particle_velocities() const {
	PackedVector3Array result;
	result.resize(velocities.size());
	Vector3 *w = result.ptrw();
	const Vector3 *v = velocities.ptr();
	for (int i = 0; i < velocities.size(); ++i) {
		w[i] = v[i];
	}
	return result;
}

int PBFParticleFluid3D::add_velocity_pulse(const Vector3 &p_center, real_t p_radius, const Vector3 &p_delta_velocity) {
	// Script-accessible stirring / splash interaction. Smooth compact
	// falloff; capped total speed so one bad gameplay input cannot make
	// the next density solve overflow or cross the entire tank in one tick.
	if (!p_center.is_finite() || !p_delta_velocity.is_finite() ||
			!(p_radius > 0.0) || !Math::is_finite(p_radius) ||
			p_radius > 1000.0 || p_delta_velocity.length_squared() > real_t(10000.0)) {
		return 0;
	}
	const double radius2 = double(p_radius) * double(p_radius);
	const Vector3 *p = positions.ptr();
	Vector3 *v = velocities.ptrw();
	int affected = 0;
	for (int i = 0; i < positions.size(); ++i) {
		const Vector3 d = p[i] - p_center;
		const double d2 = double(d.x) * double(d.x) +
				double(d.y) * double(d.y) + double(d.z) * double(d.z);
		if (d2 >= radius2 || !Math::is_finite(d2)) {
			continue;
		}
		const double falloff = 1.0 - d2 / radius2;
		Vector3 updated = v[i] + p_delta_velocity * real_t(falloff * falloff);
		if (!updated.is_finite()) {
			continue;
		}
		if (updated.length_squared() > real_t(6400.0)) {
			updated = updated.normalized() * real_t(80.0);
		}
		v[i] = updated;
		++affected;
	}
	return affected;
}

void PBFParticleFluid3D::clear_particles() {
	_resize_buffers(0);
	average_density = 0.0;
	last_neighbor_evaluations = 0;
}

void PBFParticleFluid3D::set_simulation_enabled(bool p_enabled) {
	simulation_enabled = p_enabled;
	if (is_inside_tree()) {
		set_physics_process_internal(p_enabled);
	}
}

void PBFParticleFluid3D::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		set_physics_process_internal(simulation_enabled);
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		set_physics_process_internal(false);
	} else if (p_what == NOTIFICATION_INTERNAL_PHYSICS_PROCESS && simulation_enabled) {
		step(real_t(get_physics_process_delta_time()));
	}
}

void PBFParticleFluid3D::set_solver_iterations(int p_iterations) {
	if (p_iterations >= 1 && p_iterations <= 12) {
		solver_iterations = p_iterations;
	}
}

void PBFParticleFluid3D::set_smoothing_radius(real_t p_radius) {
	if (Math::is_finite(p_radius) && p_radius >= real_t(0.08) && p_radius <= real_t(2.0)) {
		smoothing_radius = p_radius;
	}
}

void PBFParticleFluid3D::set_rest_density(real_t p_density) {
	if (Math::is_finite(p_density) && p_density > 0.0 && p_density <= 100000.0) {
		rest_density = p_density;
	}
}

void PBFParticleFluid3D::set_particle_mass(real_t p_mass) {
	if (Math::is_finite(p_mass) && p_mass > 0.0 && p_mass <= 10000.0) {
		particle_mass = p_mass;
	}
}

void PBFParticleFluid3D::set_particle_radius(real_t p_radius) {
	if (Math::is_finite(p_radius) && p_radius > 0.0 &&
			p_radius < real_t(0.45) * MIN(MIN(box_max.x - box_min.x,
						box_max.y - box_min.y), box_max.z - box_min.z)) {
		particle_radius = p_radius;
	}
}

void PBFParticleFluid3D::set_artificial_pressure(real_t p_strength) {
	if (Math::is_finite(p_strength) && p_strength >= 0.0 && p_strength <= 0.1) {
		artificial_pressure = p_strength;
	}
}

void PBFParticleFluid3D::set_xsph_viscosity(real_t p_viscosity) {
	if (Math::is_finite(p_viscosity) && p_viscosity >= 0.0 && p_viscosity <= 1.0) {
		xsph_viscosity = p_viscosity;
	}
}

void PBFParticleFluid3D::set_boundary_restitution(real_t p_restitution) {
	if (Math::is_finite(p_restitution) && p_restitution >= 0.0 && p_restitution <= 1.0) {
		boundary_restitution = p_restitution;
	}
}

void PBFParticleFluid3D::set_gravity(const Vector3 &p_gravity) {
	if (p_gravity.is_finite()) {
		gravity = p_gravity;
	}
}

void PBFParticleFluid3D::set_box_min(const Vector3 &p_bounds) {
	if (p_bounds.is_finite() && p_bounds.x >= -10000.0 && p_bounds.y >= -10000.0 &&
			p_bounds.z >= -10000.0 &&
			p_bounds.x + 2.0 * particle_radius < box_max.x &&
			p_bounds.y + 2.0 * particle_radius < box_max.y &&
			p_bounds.z + 2.0 * particle_radius < box_max.z) {
		box_min = p_bounds;
	}
}

void PBFParticleFluid3D::set_box_max(const Vector3 &p_bounds) {
	if (p_bounds.is_finite() && p_bounds.x <= 10000.0 && p_bounds.y <= 10000.0 &&
			p_bounds.z <= 10000.0 &&
			p_bounds.x - 2.0 * particle_radius > box_min.x &&
			p_bounds.y - 2.0 * particle_radius > box_min.y &&
			p_bounds.z - 2.0 * particle_radius > box_min.z) {
		box_max = p_bounds;
	}
}

void PBFParticleFluid3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_simulation_enabled", "enabled"), &PBFParticleFluid3D::set_simulation_enabled);
	ClassDB::bind_method(D_METHOD("is_simulation_enabled"), &PBFParticleFluid3D::is_simulation_enabled);
	ClassDB::bind_method(D_METHOD("set_collide_with_bodies", "enabled"), &PBFParticleFluid3D::set_collide_with_bodies);
	ClassDB::bind_method(D_METHOD("is_collide_with_bodies_enabled"), &PBFParticleFluid3D::is_collide_with_bodies_enabled);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "mask"), &PBFParticleFluid3D::set_collision_mask);
	ClassDB::bind_method(D_METHOD("get_collision_mask"), &PBFParticleFluid3D::get_collision_mask);
	ClassDB::bind_method(D_METHOD("set_solver_iterations", "iterations"), &PBFParticleFluid3D::set_solver_iterations);
	ClassDB::bind_method(D_METHOD("get_solver_iterations"), &PBFParticleFluid3D::get_solver_iterations);
	ClassDB::bind_method(D_METHOD("set_smoothing_radius", "radius"), &PBFParticleFluid3D::set_smoothing_radius);
	ClassDB::bind_method(D_METHOD("get_smoothing_radius"), &PBFParticleFluid3D::get_smoothing_radius);
	ClassDB::bind_method(D_METHOD("set_rest_density", "density"), &PBFParticleFluid3D::set_rest_density);
	ClassDB::bind_method(D_METHOD("get_rest_density"), &PBFParticleFluid3D::get_rest_density);
	ClassDB::bind_method(D_METHOD("set_particle_mass", "mass"), &PBFParticleFluid3D::set_particle_mass);
	ClassDB::bind_method(D_METHOD("get_particle_mass"), &PBFParticleFluid3D::get_particle_mass);
	ClassDB::bind_method(D_METHOD("set_particle_radius", "radius"), &PBFParticleFluid3D::set_particle_radius);
	ClassDB::bind_method(D_METHOD("get_particle_radius"), &PBFParticleFluid3D::get_particle_radius);
	ClassDB::bind_method(D_METHOD("set_artificial_pressure", "strength"), &PBFParticleFluid3D::set_artificial_pressure);
	ClassDB::bind_method(D_METHOD("get_artificial_pressure"), &PBFParticleFluid3D::get_artificial_pressure);
	ClassDB::bind_method(D_METHOD("set_xsph_viscosity", "viscosity"), &PBFParticleFluid3D::set_xsph_viscosity);
	ClassDB::bind_method(D_METHOD("get_xsph_viscosity"), &PBFParticleFluid3D::get_xsph_viscosity);
	ClassDB::bind_method(D_METHOD("set_boundary_restitution", "restitution"), &PBFParticleFluid3D::set_boundary_restitution);
	ClassDB::bind_method(D_METHOD("get_boundary_restitution"), &PBFParticleFluid3D::get_boundary_restitution);
	ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &PBFParticleFluid3D::set_gravity);
	ClassDB::bind_method(D_METHOD("get_gravity"), &PBFParticleFluid3D::get_gravity);
	ClassDB::bind_method(D_METHOD("set_box_min", "minimum"), &PBFParticleFluid3D::set_box_min);
	ClassDB::bind_method(D_METHOD("get_box_min"), &PBFParticleFluid3D::get_box_min);
	ClassDB::bind_method(D_METHOD("set_box_max", "maximum"), &PBFParticleFluid3D::set_box_max);
	ClassDB::bind_method(D_METHOD("get_box_max"), &PBFParticleFluid3D::get_box_max);

	ClassDB::bind_method(D_METHOD("set_particle_positions", "positions"), &PBFParticleFluid3D::set_particle_positions);
	ClassDB::bind_method(D_METHOD("create_block", "origin", "dimensions", "spacing"), &PBFParticleFluid3D::create_block);
	ClassDB::bind_method(D_METHOD("get_particle_positions"), &PBFParticleFluid3D::get_particle_positions);
	ClassDB::bind_method(D_METHOD("get_particle_velocities"), &PBFParticleFluid3D::get_particle_velocities);
	ClassDB::bind_method(D_METHOD("clear_particles"), &PBFParticleFluid3D::clear_particles);
	ClassDB::bind_method(D_METHOD("add_velocity_pulse", "local_center", "radius", "delta_velocity"), &PBFParticleFluid3D::add_velocity_pulse);
	ClassDB::bind_method(D_METHOD("get_particle_count"), &PBFParticleFluid3D::get_particle_count);
	ClassDB::bind_method(D_METHOD("get_average_density"), &PBFParticleFluid3D::get_average_density);
	ClassDB::bind_method(D_METHOD("get_last_neighbor_evaluations"), &PBFParticleFluid3D::get_last_neighbor_evaluations);
	ClassDB::bind_method(D_METHOD("step", "delta"), &PBFParticleFluid3D::step);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "simulation_enabled"), "set_simulation_enabled", "is_simulation_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "collide_with_bodies"), "set_collide_with_bodies", "is_collide_with_bodies_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_mask", "get_collision_mask");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "solver_iterations", PROPERTY_HINT_RANGE, "1,12,1"), "set_solver_iterations", "get_solver_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "smoothing_radius", PROPERTY_HINT_RANGE, "0.08,2,0.01,suffix:m"), "set_smoothing_radius", "get_smoothing_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rest_density", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_rest_density", "get_rest_density");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "particle_mass", PROPERTY_HINT_RANGE, "0.01,10000,0.01,or_greater"), "set_particle_mass", "get_particle_mass");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "particle_radius", PROPERTY_HINT_RANGE, "0.001,1,0.001,suffix:m"), "set_particle_radius", "get_particle_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "artificial_pressure", PROPERTY_HINT_RANGE, "0,0.1,0.001"), "set_artificial_pressure", "get_artificial_pressure");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "xsph_viscosity", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_xsph_viscosity", "get_xsph_viscosity");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "boundary_restitution", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_boundary_restitution", "get_boundary_restitution");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "gravity"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "box_min"), "set_box_min", "get_box_min");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "box_max"), "set_box_max", "get_box_max");
}
