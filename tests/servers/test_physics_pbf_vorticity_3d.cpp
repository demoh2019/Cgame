/**************************************************************************/
/*  test_physics_pbf_vorticity_3d.cpp                                     */
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
#include "servers/physics_pbf_vorticity_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_pbf_vorticity_3d)

namespace TestPhysicsPBFVorticity3D {

TEST_CASE("[PhysicsPBFVorticity] Rotating velocity field has correctly signed curl") {
	const Vector3 gradient(1, 0, 0);
	const Vector3 dv(0, 2, 0);
	const Vector3 curl = PhysicsPBFVorticity3D::curl_pair(dv, gradient, 0.5);
	CHECK(curl.is_equal_approx(Vector3(0, 0, 1)));
	CHECK(PhysicsPBFVorticity3D::curl_pair(-dv, gradient, 0.5).is_equal_approx(-curl));
	CHECK(PhysicsPBFVorticity3D::curl_pair(dv, gradient, 0.0) == Vector3());
	CHECK(PhysicsPBFVorticity3D::curl_pair(Vector3(), gradient, 1.0) == Vector3());
}

TEST_CASE("[PhysicsPBFVorticity] Gradient of curl magnitude points towards stronger vortex") {
	const Vector3 gradient(2, -1, 0);
	const Vector3 eta = PhysicsPBFVorticity3D::magnitude_gradient_pair(
			5.0, 3.0, gradient, 0.1);
	CHECK(eta.is_equal_approx(Vector3(0.4, -0.2, 0)));
	CHECK(PhysicsPBFVorticity3D::magnitude_gradient_pair(
			3.0, 3.0, gradient, 0.1) == Vector3());
}

TEST_CASE("[PhysicsPBFVorticity] Confinement acceleration is perpendicular to curl and eta") {
	const Vector3 eta(1, 0, 0);
	const Vector3 omega(0, 0, 4);
	const Vector3 dv = PhysicsPBFVorticity3D::velocity_increment(
			eta, omega, 0.5, real_t(1.0 / 60.0), 1.0);
	CHECK(dv.x == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(dv.y == doctest::Approx(-real_t(2.0 / 60.0)).epsilon(1e-5));
	CHECK(dv.z == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(Math::abs(dv.dot(eta)) < real_t(1e-5));
	CHECK(Math::abs(dv.dot(omega)) < real_t(1e-5));
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			eta, -omega, 0.5, real_t(1.0 / 60.0), 1.0).is_equal_approx(-dv));
}

TEST_CASE("[PhysicsPBFVorticity] Extreme vorticity is clamped in the direction of curl") {
	const Vector3 dv = PhysicsPBFVorticity3D::velocity_increment(
			Vector3(1, 0, 0), Vector3(0, 0, real_t(1e7)),
			5.0, 0.1, 0.12);
	CHECK(dv.is_finite());
	CHECK(dv.y < real_t(0.0));
	CHECK(dv.length() == doctest::Approx(0.12).epsilon(2e-5));
}

TEST_CASE("[PhysicsPBFVorticity] Invalid, degenerate and zero-strength corrections vanish") {
	const Vector3 eta(1, 0, 0);
	const Vector3 omega(0, 0, 3);
	const real_t infinity = std::numeric_limits<real_t>::infinity();
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			eta, omega, 0.0, 0.016, 0.12) == Vector3());
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			Vector3(), omega, 0.5, 0.016, 0.12) == Vector3());
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			eta, Vector3(), 0.5, 0.016, 0.12) == Vector3());
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			eta, omega, 0.5, -0.016, 0.12) == Vector3());
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			eta, omega, 0.5, 0.016, -1.0) == Vector3());
	CHECK(PhysicsPBFVorticity3D::velocity_increment(
			eta, Vector3(infinity, 0, 0), 0.5, 0.016, 0.12) == Vector3());
	CHECK(PhysicsPBFVorticity3D::curl_pair(
			Vector3(infinity, 0, 0), eta, 1.0) == Vector3());
}

TEST_CASE("[PhysicsPBFVorticity] Native liquid vorticity is opt-in and deterministic") {
	PBFParticleFluid3D with_vortex;
	PBFParticleFluid3D baseline;
	with_vortex.set_gravity(Vector3());
	baseline.set_gravity(Vector3());
	with_vortex.set_xsph_viscosity(0.0);
	baseline.set_xsph_viscosity(0.0);
	with_vortex.set_smoothing_radius(0.42);
	baseline.set_smoothing_radius(0.42);
	with_vortex.set_vorticity_confinement(0.9);
	CHECK(baseline.get_vorticity_confinement() == 0.0);
	CHECK(baseline.get_last_vorticity_neighbor_evaluations() == 0);
	CHECK(with_vortex.get_vorticity_confinement() == doctest::Approx(0.9).epsilon(1e-5));
	REQUIRE(with_vortex.create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19));
	REQUIRE(baseline.create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19));
	const Vector3 center_a(-0.25, 1.38, 0);
	const Vector3 center_b(0.25, 1.38, 0);
	for (PBFParticleFluid3D *fluid : { &with_vortex, &baseline }) {
		CHECK(fluid->add_velocity_pulse(center_a, 1.0, Vector3(0, 0, 4)) > 0);
		CHECK(fluid->add_velocity_pulse(center_b, 1.0, Vector3(0, 0, -4)) > 0);
		REQUIRE(fluid->step(real_t(1.0 / 60.0)));
	}
	CHECK(with_vortex.get_average_vorticity() > 0.01);
	CHECK(with_vortex.get_last_vorticity_neighbor_evaluations() > 0);
	CHECK(with_vortex.get_last_vorticity_neighbor_evaluations() <= 3 * 125 * 128);
	CHECK(baseline.get_last_vorticity_neighbor_evaluations() == 0);
	CHECK(baseline.get_average_vorticity() == 0.0);
	const PackedVector3Array active = with_vortex.get_particle_velocities();
	const PackedVector3Array passive = baseline.get_particle_velocities();
	CHECK(active.size() == passive.size());
	bool diverged = false;
	for (int i = 0; i < active.size(); ++i) {
		CHECK(active[i].is_finite());
		CHECK(passive[i].is_finite());
		diverged |= (active[i] - passive[i]).length() > real_t(1e-5);
	}
	CHECK(diverged);
}

TEST_CASE("[PhysicsPBFVorticity] Invalid tuning is ignored and counters reset on clear") {
	PBFParticleFluid3D fluid;
	CHECK(fluid.get_vorticity_confinement() == 0.0);
	CHECK(fluid.get_vorticity_max_velocity_change() == doctest::Approx(0.12).epsilon(1e-5));
	fluid.set_vorticity_confinement(-0.1);
	fluid.set_vorticity_confinement(std::numeric_limits<real_t>::infinity());
	fluid.set_vorticity_max_velocity_change(0.0);
	CHECK(fluid.get_vorticity_confinement() == 0.0);
	CHECK(fluid.get_vorticity_max_velocity_change() == doctest::Approx(0.12).epsilon(1e-5));
	fluid.set_vorticity_confinement(0.5);
	fluid.set_vorticity_max_velocity_change(0.03);
	CHECK(fluid.get_vorticity_confinement() == 0.5);
	CHECK(fluid.get_vorticity_max_velocity_change() == doctest::Approx(0.03).epsilon(1e-5));
	REQUIRE(fluid.create_block(Vector3(), Vector3i(3, 3, 3), 0.17));
	REQUIRE(fluid.step(real_t(1.0 / 60.0)));
	CHECK(fluid.get_last_vorticity_neighbor_evaluations() > 0);
	fluid.clear_particles();
	CHECK(fluid.get_particle_count() == 0);
	CHECK(fluid.get_average_vorticity() == 0.0);
	CHECK(fluid.get_last_vorticity_neighbor_evaluations() == 0);
}

} // namespace TestPhysicsPBFVorticity3D
