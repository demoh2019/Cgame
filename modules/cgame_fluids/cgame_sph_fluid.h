/**************************************************************************/
/*  cgame_sph_fluid.h                                                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#pragma once

// 3D position-based fluids (PBF) particle solver.
//
// Algorithm: Macklin & Müller, "Position Based Fluids", ACM TOG 32(4), 2013
// (density constraint solved with Jacobi iterations, artificial pressure term
// against tensile instability, XSPH viscosity, vorticity confinement), built on
// the SPH kernels of Müller, Charypar & Gross, "Particle-Based Fluid Simulation
// for Interactive Applications", SCA 2003 (poly6 for density, spiky for gradients).
// Written from the published equations; no third-party source code copied.
// Structure informed by Matthias Müller's Ten Minute Physics demos
// (MIT licence, https://github.com/matthias-research/pages).

#include "cgame_fluids_common.h"

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class CgameSPHFluid : public RefCounted {
	GDCLASS(CgameSPHFluid, RefCounted);

public:
	static constexpr real_t BASE_DENSITY = 1000.0;
	static constexpr real_t MAX_SPEED = 20.0;

private:
	real_t spacing = 0.1;
	real_t kernel_radius = 0.2;
	real_t particle_mass = 1.0;
	real_t rest_density = 1.0;
	Vector3 gravity = Vector3(0.0, -9.81, 0.0);
	real_t xsph_c = 0.02;
	real_t vorticity_epsilon = 0.0;
	real_t relaxation = 5.0;
	real_t tensile_k = 0.006;
	real_t attraction = 0.0;
	Vector3 bounds_min;
	Vector3 bounds_max = Vector3(2.0, 2.0, 2.0);
	real_t wall_margin = 0.002;
	bool obstacle_gravity = false;

	Vector<Vector3> pos;
	Vector<Vector3> vel;
	Vector<Vector3> pred;
	Vector<float> dens;
	Vector<float> lam;
	Vector<Vector3> omega;

	Vector<Vector3> ob_center;
	Vector<Vector3> ob_next;
	Vector<float> ob_radius;
	Vector<Vector3> ob_vel;
	Vector<float> ob_mass;
	Vector<Vector3> ob_impulse;

	real_t h2 = 0.0;
	real_t poly6_coef = 0.0;
	real_t spiky_coef = 0.0;
	real_t dq_w = 1.0;
	int gx = 1;
	int gy = 1;
	int gz = 1;
	Vector<int> grid_start;
	Vector<int> grid_items;
	Vector<int> cell_of;
	Vector<int> nb_start;
	Vector<int> nb_idx;

	void _calibrate_rest_density();
	int _cell_index(const Vector3 &p_pos) const;
	void _build_neighbors();
	void _solve_lambdas(int p_count, real_t p_inv_scale);
	Vector3 _position_delta(int p_i, real_t p_inv_scale) const;
	Vector3 _grad_spiky(const Vector3 &p_d, real_t p_r) const;
	void _apply_vorticity_and_viscosity(int p_count, real_t p_dt);
	Vector3 _collide(const Vector3 &p_pos, real_t p_dt);

protected:
	static void _bind_methods();

public:
	void setup(real_t p_spacing, const Vector3 &p_bounds_min, const Vector3 &p_bounds_max);

	void add_particle(const Vector3 &p_pos, const Vector3 &p_vel = Vector3());
	int add_block(const Vector3 &p_lo, const Vector3 &p_hi);
	void clear_particles();
	int particle_count() const { return pos.size(); }
	Vector<Vector3> positions() const { return pos; }
	Vector<Vector3> velocities() const { return vel; }
	real_t average_density() const;

	int add_sphere_obstacle(const Vector3 &p_center, real_t p_radius, const Vector3 &p_velocity = Vector3(), real_t p_mass = 0.0);
	Vector3 obstacle_position(int p_index) const;
	Vector3 obstacle_velocity(int p_index) const;
	int obstacle_count() const { return ob_center.size(); }

	real_t kinetic_energy() const;
	Vector3 total_momentum() const;

	void step(real_t p_dt, int p_iterations = 4);

	CGF_GETTER(real_t, spacing)
	CGF_GETTER(real_t, kernel_radius)
	CGF_GETTER(real_t, particle_mass)
	CGF_GETTER(real_t, rest_density)
	CGF_ACCESSOR(real_t, wall_margin)
	CGF_ACCESSOR_REF(Vector3, gravity)
	CGF_ACCESSOR(real_t, xsph_c)
	CGF_ACCESSOR(real_t, vorticity_epsilon)
	CGF_ACCESSOR(real_t, relaxation)
	CGF_ACCESSOR(real_t, tensile_k)
	CGF_ACCESSOR(real_t, attraction)
	CGF_GETTER(Vector3, bounds_min)
	CGF_GETTER(Vector3, bounds_max)
	CGF_ACCESSOR(bool, obstacle_gravity)

	CgameSPHFluid();
};
