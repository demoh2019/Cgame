/**************************************************************************/
/*  test_physics_pbf_3d.cpp                                               */
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

#include "scene/3d/physics/pbf_particle_fluid_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_pbf_3d)

namespace TestPhysicsPBF3D {

TEST_CASE("[PhysicsPBF3D] Poly6 kernel is compact finite and normalized") {
	const real_t h = 0.4;
	CHECK(PhysicsPBFKernel3D::poly6(0, h) > 0.0);
	CHECK(PhysicsPBFKernel3D::poly6(h * h, h) == 0.0);
	CHECK(PhysicsPBFKernel3D::poly6(h * h * 2.0, h) == 0.0);
	CHECK(PhysicsPBFKernel3D::poly6(-1.0, h) == 0.0);
	CHECK(PhysicsPBFKernel3D::poly6(0, -1.0) == 0.0);
	// Integrate 4*pi*r^2*W(r) dr with Simpson's rule.
	const int slices = 1024;
	double integral = 0.0;
	for (int i = 0; i <= slices; ++i) {
		const double radius = double(h) * double(i) / double(slices);
		const double v = 4.0 * Math::PI * radius * radius *
				double(PhysicsPBFKernel3D::poly6(radius * radius, h));
		integral += (i == 0 || i == slices ? 1.0 : (i & 1 ? 4.0 : 2.0)) * v;
	}
	integral *= double(h) / (3.0 * slices);
	CHECK(integral == doctest::Approx(1.0).epsilon(2e-5));
}

TEST_CASE("[PhysicsPBF3D] Density gradient equals central finite difference") {
	const double h = 0.5;
	const Vector3 dx(0.12, 0.07, -0.10);
	const Vector3 grad = PhysicsPBFKernel3D::gradient(dx, h);
	const double eps = 0.0001;
	const Vector3 plus = dx + Vector3(eps, 0, 0);
	const Vector3 minus = dx - Vector3(eps, 0, 0);
	const double finite_difference = (
			double(PhysicsPBFKernel3D::poly6(plus.length_squared(), h)) -
			double(PhysicsPBFKernel3D::poly6(minus.length_squared(), h))) / (2.0 * eps);
	CHECK(grad.x == doctest::Approx(finite_difference).epsilon(5e-4));
	CHECK(grad.x < 0.0);
	CHECK(PhysicsPBFKernel3D::gradient(-dx, h).is_equal_approx(-grad));
	CHECK(PhysicsPBFKernel3D::gradient(Vector3(), h) == Vector3());
	CHECK(PhysicsPBFKernel3D::gradient(Vector3(2, 0, 0), h) == Vector3());
}

TEST_CASE("[PhysicsPBF3D] Artificial pressure opposes clustering and is bounded") {
	CHECK(PhysicsPBFKernel3D::artificial_pressure(0.0, 0.5, 0.002) < 0.0);
	CHECK(PhysicsPBFKernel3D::artificial_pressure(0.25, 0.5, 0.002) == 0.0);
	CHECK(PhysicsPBFKernel3D::artificial_pressure(0.0, 0.5, 0.0) == 0.0);
	CHECK(Math::is_finite(PhysicsPBFKernel3D::artificial_pressure(0.0, 0.5, 0.1)));
}

TEST_CASE("[PhysicsPBF3D] Sorted cell search handles negative coordinates and duplicate keys") {
	PhysicsPBFCell3D cells[6];
	cells[0].x = -3; cells[0].y = 0; cells[0].z = 0; cells[0].index = 1;
	cells[1].x = -1; cells[1].y = -2; cells[1].z = 0; cells[1].index = 2;
	cells[2].x = -1; cells[2].y = -2; cells[2].z = 0; cells[2].index = 4;
	cells[3].x = 0; cells[3].y = 0; cells[3].z = 0; cells[3].index = 0;
	cells[4].x = 0; cells[4].y = 0; cells[4].z = 1; cells[4].index = 3;
	cells[5].x = 4; cells[5].y = 1; cells[5].z = 2; cells[5].index = 5;
	CHECK(physics_pbf_find_cell_begin_3d(cells, 6, -1, -2, 0) == 1);
	CHECK(physics_pbf_find_cell_begin_3d(cells, 6, 0, 0, 0) == 3);
	CHECK(physics_pbf_find_cell_begin_3d(cells, 6, 0, 0, 1) == 4);
	CHECK(physics_pbf_find_cell_begin_3d(cells, 6, 5, 0, 0) == 6);
}

TEST_CASE("[PhysicsPBF3D] Native scene node creates moving liquid within box walls") {
	PBFParticleFluid3D liquid;
	liquid.set_solver_iterations(5);
	liquid.set_gravity(Vector3(0, -9.8, 0));
	REQUIRE(liquid.create_block(Vector3(-0.4, 1.0, -0.4), Vector3i(4, 4, 4), 0.17));
	CHECK(liquid.get_particle_count() == 64);
	CHECK_FALSE(liquid.is_simulation_enabled());
	// Manual step works with automatic physics processing disabled.
	const PackedVector3Array initial = liquid.get_particle_positions();
	for (int i = 0; i < 80; ++i) {
		REQUIRE(liquid.step(real_t(1.0 / 60.0)));
	}
	CHECK(liquid.get_last_neighbor_evaluations() > 0);
	const PackedVector3Array result = liquid.get_particle_positions();
	CHECK(result.size() == initial.size());
	bool moved = false;
	for (int i = 0; i < result.size(); ++i) {
		CHECK(result[i].is_finite());
		CHECK(result[i].x >= -2.0);
		CHECK(result[i].x <= 2.0);
		CHECK(result[i].y >= 0.0);
		CHECK(result[i].y <= 4.0);
		CHECK(result[i].z >= -2.0);
		CHECK(result[i].z <= 2.0);
		moved |= result[i].distance_to(initial[i]) > real_t(0.01);
	}
	CHECK(moved);
	CHECK(Math::is_finite(liquid.get_average_density()));
	CHECK(liquid.get_average_density() > 0.0);
}

TEST_CASE("[PhysicsPBF3D] Same particle seed produces deterministic integration") {
	PBFParticleFluid3D a, b;
	REQUIRE(a.create_block(Vector3(0, 1, 0), Vector3i(3, 3, 3), 0.15));
	REQUIRE(b.create_block(Vector3(0, 1, 0), Vector3i(3, 3, 3), 0.15));
	for (int i = 0; i < 20; ++i) {
		REQUIRE(a.step(real_t(1.0 / 120.0)));
		REQUIRE(b.step(real_t(1.0 / 120.0)));
	}
	const PackedVector3Array first = a.get_particle_positions();
	const PackedVector3Array second = b.get_particle_positions();
	CHECK(first.size() == second.size());
	for (int i = 0; i < first.size(); ++i) {
		CHECK(first[i] == second[i]);
	}
}

TEST_CASE("[PhysicsPBF3D] Local stirring pulse affects particles but caps velocity") {
	PBFParticleFluid3D fluid;
	REQUIRE(fluid.create_block(Vector3(0, 1, 0), Vector3i(3, 3, 3), 0.2));
	CHECK(fluid.add_velocity_pulse(Vector3(0, 1, 0), 2.0, Vector3(101, 0, 0)) == 0);
	const int affected = fluid.add_velocity_pulse(Vector3(0, 1.2, 0), 0.8, Vector3(2, 3, 0));
	CHECK(affected > 0);
	CHECK(affected <= fluid.get_particle_count());
	const PackedVector3Array velocity = fluid.get_particle_velocities();
	int moving = 0;
	for (const Vector3 &v : velocity) {
		CHECK(v.is_finite());
		CHECK(v.length_squared() <= real_t(6400.0));
		if (v.length_squared() > real_t(0.0)) {
			++moving;
		}
	}
	CHECK(moving == affected);
	CHECK(fluid.add_velocity_pulse(Vector3(999, 999, 999), 0.1, Vector3(1, 0, 0)) == 0);
}

TEST_CASE("[PhysicsPBF3D] Invalid time and oversized seed preserve previous state") {
	PBFParticleFluid3D liquid;
	CHECK_FALSE(liquid.step(0.0));
	CHECK_FALSE(liquid.step(-0.1));
	CHECK_FALSE(liquid.step(1.0));
	CHECK_FALSE(liquid.step(std::numeric_limits<real_t>::infinity()));
	REQUIRE(liquid.create_block(Vector3(), Vector3i(2, 2, 2), 0.2));
	const PackedVector3Array original = liquid.get_particle_positions();
	CHECK_FALSE(liquid.create_block(Vector3(), Vector3i(32, 32, 32), 0.2));
	CHECK_FALSE(liquid.create_block(Vector3(), Vector3i(-1, 2, 2), 0.2));
	CHECK_FALSE(liquid.create_block(Vector3(), Vector3i(2, 2, 2), -0.1));
	CHECK(liquid.get_particle_positions() == original);
}

TEST_CASE("[PhysicsPBF3D] Invalid configurations never permit nonfinite particles") {
	PBFParticleFluid3D liquid;
	liquid.set_smoothing_radius(std::numeric_limits<real_t>::infinity());
	CHECK(liquid.get_smoothing_radius() == doctest::Approx(0.32));
	liquid.set_rest_density(-1.0);
	CHECK(liquid.get_rest_density() == 1000.0);
	liquid.set_particle_mass(0.0);
	CHECK(liquid.get_particle_mass() == 6.0);
	liquid.set_solver_iterations(0);
	CHECK(liquid.get_solver_iterations() == 4);
	PackedVector3Array invalid;
	invalid.push_back(Vector3(0, 0, 0));
	invalid.push_back(Vector3(std::numeric_limits<real_t>::infinity(), 0, 0));
	CHECK_FALSE(liquid.set_particle_positions(invalid));
	CHECK(liquid.get_particle_count() == 0);
}

} // namespace TestPhysicsPBF3D
