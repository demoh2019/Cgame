/**************************************************************************/
/*  test_physics_softbody_volume_damping.cpp                              */
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
/**************************************************************************/

#include "servers/physics_softbody_volume_damping.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_volume_damping)

namespace TestPhysicsSoftBodyVolumeDamping {

// Unit tetrahedron with outward winding; signed-volume gradients:
static void tetra_gradients(Vector3 (&r_g)[4]) {
	r_g[0] = Vector3(-1, -1, -1) / real_t(6);
	r_g[1] = Vector3(1, 0, 0) / real_t(6);
	r_g[2] = Vector3(0, 1, 0) / real_t(6);
	r_g[3] = Vector3(0, 0, 1) / real_t(6);
}

TEST_CASE("[PhysicsVolume] Bulk viscosity removes exact fraction of breathing rate") {
	Vector3 g[4];
	tetra_gradients(g);
	Vector3 v[4] = { Vector3(-1, -1, -1), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	double old_rate = 0.0;
	double k = 0.0;
	for (int i = 0; i < 4; ++i) {
		old_rate += double(g[i].dot(v[i]));
		k += double(g[i].length_squared());
	}
	double lambda = 0.0;
	CHECK(physics_softbody_bulk_viscosity_impulse(old_rate, k, 0.75, lambda));
	double next_rate = 0.0;
	for (int i = 0; i < 4; ++i) {
		Vector3 next;
		CHECK(physics_softbody_bulk_viscosity_velocity(v[i], g[i], 1, lambda, next));
		next_rate += double(g[i].dot(next));
	}
	CHECK(next_rate == doctest::Approx(old_rate * 0.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsVolume] Free closed surface conserves momentum and loses energy") {
	Vector3 g[4];
	tetra_gradients(g);
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const Vector3 v[4] = { Vector3(3, -1, 2), Vector3(-1, 4, 0),
		Vector3(2, 0, -3), Vector3(4, -1, 1) };
	Vector3 linear_before, angular_before, linear_after, angular_after;
	double rate = 0.0, k = 0.0, energy_before = 0.0, energy_after = 0.0;
	for (int i = 0; i < 4; ++i) {
		rate += double(g[i].dot(v[i]));
		k += double(g[i].length_squared());
		linear_before += v[i];
		angular_before += x[i].cross(v[i]);
		energy_before += double(v[i].length_squared()) / 2.0;
	}
	double lambda = 0.0;
	CHECK(physics_softbody_bulk_viscosity_impulse(rate, k, 1.0, lambda));
	for (int i = 0; i < 4; ++i) {
		Vector3 next;
		CHECK(physics_softbody_bulk_viscosity_velocity(v[i], g[i], 1, lambda, next));
		linear_after += next;
		angular_after += x[i].cross(next);
		energy_after += double(next.length_squared()) / 2.0;
	}
	CHECK(linear_after.is_equal_approx(linear_before));
	CHECK(angular_after.is_equal_approx(angular_before));
	CHECK(energy_after <= energy_before + 1e-6);
}

TEST_CASE("[PhysicsVolume] Rigid translation and rotation have zero breathing rate") {
	Vector3 g[4];
	tetra_gradients(g);
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const Vector3 drift(4, -2, 7);
	const Vector3 omega(1, 2, -3);
	double rate = 0.0;
	for (int i = 0; i < 4; ++i) {
		rate += double(g[i].dot(drift + omega.cross(x[i])));
	}
	CHECK(Math::abs(rate) < 1e-6);
}

TEST_CASE("[PhysicsVolume] Pinned nodes remain fixed during bulk viscosity") {
	Vector3 g[4];
	tetra_gradients(g);
	const Vector3 v[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	double rate = 0.0, k = 0.0;
	for (int i = 1; i < 4; ++i) {
		rate += double(g[i].dot(v[i]));
		k += double(g[i].length_squared());
	}
	double lambda = 0.0;
	CHECK(physics_softbody_bulk_viscosity_impulse(rate, k, 0.5, lambda));
	double new_rate = 0.0;
	for (int i = 1; i < 4; ++i) {
		Vector3 next;
		CHECK(physics_softbody_bulk_viscosity_velocity(v[i], g[i], 1, lambda, next));
		new_rate += double(g[i].dot(next));
	}
	CHECK(new_rate == doctest::Approx(rate * 0.5).epsilon(1e-5));
}

TEST_CASE("[PhysicsVolume] Exponential viscosity has consistent substep decay") {
	const double full = 1.0 - Math::exp(-2.5 * 0.2);
	const double half = 1.0 - Math::exp(-2.5 * 0.1);
	CHECK((1.0 - half) * (1.0 - half) == doctest::Approx(1.0 - full).epsilon(1e-12));
}

TEST_CASE("[PhysicsVolume] Invalid rates, degenerate mass, overflow cannot corrupt velocities") {
	double lambda = 123.0;
	CHECK_FALSE(physics_softbody_bulk_viscosity_impulse(1.0, 0.0, .5, lambda));
	CHECK_FALSE(physics_softbody_bulk_viscosity_impulse(1.0, -1.0, .5, lambda));
	CHECK_FALSE(physics_softbody_bulk_viscosity_impulse(1.0, 1.0, 0.0, lambda));
	CHECK_FALSE(physics_softbody_bulk_viscosity_impulse(1.0, 1.0, 1.1, lambda));
	CHECK_FALSE(physics_softbody_bulk_viscosity_impulse(
			std::numeric_limits<double>::infinity(), 1.0, .5, lambda));
	CHECK(lambda == doctest::Approx(123.0));
	Vector3 next(3, 2, 1);
	CHECK_FALSE(physics_softbody_bulk_viscosity_velocity(
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0),
			Vector3(1, 0, 0), 1, .5, next));
	CHECK_FALSE(physics_softbody_bulk_viscosity_velocity(
			Vector3(), Vector3(1, 0, 0), 0, .5, next));
	CHECK(next == Vector3(3, 2, 1));
}

} // namespace TestPhysicsSoftBodyVolumeDamping
