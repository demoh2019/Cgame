/**************************************************************************/
/*  test_physics_pbf_divergence_3d.cpp                                    */
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
#include "servers/physics_pbf_divergence_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_pbf_divergence_3d)

namespace TestPhysicsPBFDivergence3D {

TEST_CASE("[PhysicsPBFDivergence] Approaching particles produce positive density rate") {
	const Vector3 left(-0.1, 0, 0);
	const Vector3 right(0.1, 0, 0);
	const Vector3 grad = PhysicsPBFKernel3D::gradient(left - right, 0.4);
	REQUIRE(grad.x > 0.0);
	const real_t incoming = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(1, 0, 0), Vector3(-1, 0, 0), grad, 6.0);
	const real_t outgoing = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(-1, 0, 0), Vector3(1, 0, 0), grad, 6.0);
	CHECK(incoming > 0.0);
	CHECK(outgoing == doctest::Approx(-incoming).epsilon(1e-5));
	CHECK(PhysicsPBFDivergence3D::compressive_rate_fraction(incoming, 1000.0) > 0.0);
	CHECK(PhysicsPBFDivergence3D::compressive_rate_fraction(outgoing, 1000.0) == 0.0);
	CHECK(PhysicsPBFDivergence3D::compressive_rate_fraction(0.0, 1000.0) == 0.0);
}

TEST_CASE("[PhysicsPBFDivergence] Two-particle velocity projection opposes compression") {
	const Vector3 r(-0.18, 0, 0);
	const Vector3 grad = PhysicsPBFKernel3D::gradient(r, 0.42);
	REQUIRE(grad.x > 0.0);
	const real_t fraction = real_t(6.0 / 1000.0);
	const real_t incoming = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(1, 0, 0), Vector3(-1, 0, 0), grad, 6.0);
	const real_t g2 = (grad * fraction).length_squared();
	const real_t lambda = PhysicsPBFDivergence3D::lagrange_multiplier(
			double(incoming) / 1000.0, double(g2) * 2.0);
	CHECK(lambda < 0.0);
	const Vector3 left_delta = PhysicsPBFDivergence3D::pair_velocity_correction(
			grad, lambda, lambda, fraction);
	const Vector3 right_delta = PhysicsPBFDivergence3D::pair_velocity_correction(
			-grad, lambda, lambda, fraction);
	CHECK(left_delta.x < 0.0);
	CHECK(right_delta.x > 0.0);
	CHECK((left_delta + right_delta).length() < real_t(1e-5));
	const real_t after_rate = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(1, 0, 0) + left_delta, Vector3(-1, 0, 0) + right_delta, grad, 6.0);
	CHECK(after_rate < incoming);
}

TEST_CASE("[PhysicsPBFDivergence] Velocity correction cap and relaxation preserve direction") {
	const Vector3 dv(100, -50, 25);
	const Vector3 limited = PhysicsPBFDivergence3D::bounded_correction(dv, 0.8, 0.12);
	CHECK(limited.is_finite());
	CHECK(Math::abs(limited.length() - real_t(0.12)) < real_t(1e-5));
	CHECK(limited.dot(dv) > 0.0);
	const Vector3 small = PhysicsPBFDivergence3D::bounded_correction(
			Vector3(0.1, 0, 0), 0.5, 0.12);
	CHECK(Math::abs(small.x - real_t(0.05)) < real_t(1e-6));
}

TEST_CASE("[PhysicsPBFDivergence] Reject nonfinite values and degenerate gradients") {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	CHECK(PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(inf, 0, 0), Vector3(), Vector3(1, 0, 0), 1.0) == 0.0);
	CHECK(PhysicsPBFDivergence3D::compressive_rate_fraction(-1000.0, 1000.0) == 0.0);
	CHECK(PhysicsPBFDivergence3D::compressive_rate_fraction(1.0, 0.0) == 0.0);
	CHECK(PhysicsPBFDivergence3D::lagrange_multiplier(0.0, 1.0) == 0.0);
	CHECK(PhysicsPBFDivergence3D::lagrange_multiplier(2.0, -1.0) == 0.0);
	CHECK(PhysicsPBFDivergence3D::lagrange_multiplier(2.0, 0.0) < 0.0);
	CHECK(PhysicsPBFDivergence3D::pair_velocity_correction(
			Vector3(inf, 0, 0), -1.0, -1.0, 0.006) == Vector3());
	CHECK(PhysicsPBFDivergence3D::bounded_correction(
			Vector3(1, 0, 0), 0.0, 0.12) == Vector3());
	CHECK(PhysicsPBFDivergence3D::bounded_correction(
			Vector3(1, 0, 0), 0.8, -1.0) == Vector3());
}

TEST_CASE("[PhysicsPBFDivergence] Scene node leaves baseline path untouched unless enabled") {
	PBFParticleFluid3D fluid;
	CHECK(fluid.get_divergence_iterations() == 0);
	CHECK(fluid.get_average_positive_density_rate() == 0.0);
	CHECK(fluid.get_last_divergence_iterations() == 0);
	CHECK(fluid.get_last_divergence_neighbor_evaluations() == 0);
	REQUIRE(fluid.create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19));
	REQUIRE(fluid.step(real_t(1.0 / 60.0)));
	CHECK(fluid.get_last_divergence_neighbor_evaluations() == 0);
	CHECK(fluid.get_last_divergence_iterations() == 0);
	CHECK(fluid.get_average_positive_density_rate() == 0.0);
}

TEST_CASE("[PhysicsPBFDivergence] Native velocity projection reduces compression") {
	PBFParticleFluid3D active;
	PBFParticleFluid3D baseline;
	for (PBFParticleFluid3D *fluid : { &active, &baseline }) {
		fluid->set_gravity(Vector3());
		fluid->set_xsph_viscosity(0.0);
		fluid->set_vorticity_confinement(0.0);
		fluid->set_smoothing_radius(0.42);
		fluid->set_solver_iterations(4);
		REQUIRE(fluid->create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19));
		CHECK(fluid->add_velocity_pulse(Vector3(-0.6, 1.38, 0), 1.0, Vector3(5, 0, 0)) > 0);
		CHECK(fluid->add_velocity_pulse(Vector3(0.6, 1.38, 0), 1.0, Vector3(-5, 0, 0)) > 0);
	}
	active.set_divergence_iterations(8);
	active.set_divergence_relaxation(0.9);
	active.set_divergence_tolerance(0.0);
	REQUIRE(active.step(real_t(1.0 / 120.0)));
	REQUIRE(baseline.step(real_t(1.0 / 120.0)));
	CHECK(active.get_last_divergence_iterations() == 8);
	CHECK(active.get_last_divergence_neighbor_evaluations() <= 17 * 125 * 128);
	CHECK(active.get_average_positive_density_rate() >= 0.0);
	CHECK(Math::is_finite(active.get_average_positive_density_rate()));
	CHECK(baseline.get_last_divergence_neighbor_evaluations() == 0);
	const PackedVector3Array av = active.get_particle_velocities();
	const PackedVector3Array bv = baseline.get_particle_velocities();
	CHECK(av.size() == bv.size());
	int changed = 0;
	for (int i = 0; i < av.size(); ++i) {
		CHECK(av[i].is_finite());
		CHECK(bv[i].is_finite());
		if ((av[i] - bv[i]).length() > real_t(1e-5)) {
			++changed;
		}
	}
	CHECK(changed > 10);
}

TEST_CASE("[PhysicsPBFDivergence] Identical seeded fluids remain deterministic") {
	PBFParticleFluid3D first;
	PBFParticleFluid3D second;
	for (PBFParticleFluid3D *fluid : { &first, &second }) {
		fluid->set_divergence_iterations(6);
		fluid->set_divergence_relaxation(0.8);
		fluid->set_gravity(Vector3());
		REQUIRE(fluid->create_block(Vector3(-0.3, 1, -0.3), Vector3i(4, 4, 4), 0.18));
		CHECK(fluid->add_velocity_pulse(Vector3(0, 1.3, 0), 0.7, Vector3(3, 0, 0)) > 0);
		for (int step = 0; step < 10; ++step) {
			REQUIRE(fluid->step(real_t(1.0 / 120.0)));
		}
	}
	CHECK(first.get_particle_positions() == second.get_particle_positions());
	CHECK(first.get_particle_velocities() == second.get_particle_velocities());
	CHECK(first.get_average_positive_density_rate() == second.get_average_positive_density_rate());
}

TEST_CASE("[PhysicsPBFDivergence] Invalid tuning leaves configuration unchanged and clear resets stats") {
	PBFParticleFluid3D fluid;
	fluid.set_divergence_iterations(-1);
	fluid.set_divergence_iterations(100);
	fluid.set_divergence_tolerance(-1.0);
	fluid.set_divergence_relaxation(0.0);
	fluid.set_divergence_max_velocity_change(std::numeric_limits<real_t>::infinity());
	CHECK(fluid.get_divergence_iterations() == 0);
	CHECK(fluid.get_divergence_tolerance() == doctest::Approx(0.01).epsilon(1e-5));
	CHECK(fluid.get_divergence_relaxation() == doctest::Approx(0.8).epsilon(1e-5));
	CHECK(fluid.get_divergence_max_velocity_change() == doctest::Approx(0.12).epsilon(1e-5));
	fluid.set_divergence_iterations(6);
	fluid.set_divergence_tolerance(0.0);
	fluid.set_divergence_relaxation(0.9);
	fluid.set_divergence_max_velocity_change(0.06);
	CHECK(fluid.get_divergence_iterations() == 6);
	CHECK(fluid.get_divergence_relaxation() == doctest::Approx(0.9).epsilon(1e-5));
	REQUIRE(fluid.create_block(Vector3(), Vector3i(3, 3, 3), 0.19));
	REQUIRE(fluid.step(real_t(1.0 / 60.0)));
	fluid.clear_particles();
	CHECK(fluid.get_particle_count() == 0);
	CHECK(fluid.get_last_divergence_iterations() == 0);
	CHECK(fluid.get_last_divergence_neighbor_evaluations() == 0);
	CHECK(fluid.get_average_positive_density_rate() == 0.0);
}

} // namespace TestPhysicsPBFDivergence3D
