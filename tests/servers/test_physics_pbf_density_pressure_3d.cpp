/**************************************************************************/
/*  test_physics_pbf_density_pressure_3d.cpp                              */
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
#include "servers/physics_pbf_density_pressure_3d.h"
#include "tests/test_macros.h"

#include <initializer_list>
#include <limits>

TEST_FORCE_LINK(test_physics_pbf_density_pressure_3d)

namespace TestPhysicsPBFDensityPressure3D {

TEST_CASE("[PhysicsPBFDensityPressure] Predictive continuity density includes timestep") {
	const real_t density = PhysicsPBFDensityPressure3D::predicted_density(
			1020.0, 150.0, 0.02);
	CHECK(density == doctest::Approx(1023.0).epsilon(1e-5));
	CHECK(PhysicsPBFDensityPressure3D::positive_density_error(density, 1000.0) ==
			doctest::Approx(0.023).epsilon(1e-4));
	CHECK(PhysicsPBFDensityPressure3D::pressure_rate_constraint(
			density, 1000.0, 0.02) == doctest::Approx(1.15).epsilon(1e-4));
	CHECK(PhysicsPBFDensityPressure3D::predicted_density(
			1000.0, -500.0, 0.02) == doctest::Approx(990.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsPBFDensityPressure] Existing density excess creates pressure at rest") {
	const real_t error = PhysicsPBFDensityPressure3D::positive_density_error(
			1250.0, 1000.0);
	CHECK(error == doctest::Approx(0.25).epsilon(1e-5));
	const real_t rate = PhysicsPBFDensityPressure3D::pressure_rate_constraint(
			1250.0, 1000.0, real_t(1.0 / 60.0));
	CHECK(rate == doctest::Approx(15.0).epsilon(1e-5));
	const real_t lambda = PhysicsPBFDivergence3D::lagrange_multiplier(rate, 3.0);
	CHECK(lambda < 0.0);
	const Vector3 gradient(2, 0, 0);
	const Vector3 delta = PhysicsPBFDivergence3D::pair_velocity_correction(
			gradient, lambda, lambda, real_t(6.0 / 1000.0));
	CHECK(delta.x < 0.0);
	CHECK(PhysicsPBFDensityPressure3D::positive_density_error(950.0, 1000.0) == 0.0);
	CHECK(PhysicsPBFDensityPressure3D::pressure_rate_constraint(
			950.0, 1000.0, real_t(1.0 / 60.0)) == 0.0);
}

TEST_CASE("[PhysicsPBFDensityPressure] Pressure continuity resists pairwise approach") {
	const Vector3 gradient = PhysicsPBFKernel3D::gradient(Vector3(-0.18, 0, 0), 0.42);
	REQUIRE(gradient.x > 0.0);
	const real_t rho_dot = PhysicsPBFDivergence3D::density_rate_pair(
			Vector3(2, 0, 0), Vector3(-2, 0, 0), gradient, 6.0);
	REQUIRE(rho_dot > 0.0);
	const real_t predicted = PhysicsPBFDensityPressure3D::predicted_density(
			1000.0, rho_dot, real_t(1.0 / 60.0));
	CHECK(predicted > 1000.0);
	const real_t pressure_rate = PhysicsPBFDensityPressure3D::pressure_rate_constraint(
			predicted, 1000.0, real_t(1.0 / 60.0));
	const real_t g2 = (gradient * real_t(0.006)).length_squared();
	const real_t lambda = PhysicsPBFDivergence3D::lagrange_multiplier(
			pressure_rate, 2.0 * g2);
	const Vector3 left = PhysicsPBFDivergence3D::pair_velocity_correction(
			gradient, lambda, lambda, real_t(0.006));
	const Vector3 right = PhysicsPBFDivergence3D::pair_velocity_correction(
			-gradient, lambda, lambda, real_t(0.006));
	CHECK(left.x < 0.0);
	CHECK(right.x > 0.0);
	CHECK((left + right).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsPBFDensityPressure] Invalid, nonfinite and zero timestep are rejected") {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	CHECK(PhysicsPBFDensityPressure3D::predicted_density(
			1000.0, 0.0, 0.0) == 0.0);
	CHECK(PhysicsPBFDensityPressure3D::predicted_density(
			-1000.0, 0.0, 0.016) == 0.0);
	CHECK(PhysicsPBFDensityPressure3D::predicted_density(
			1000.0, inf, 0.016) == 0.0);
	CHECK(PhysicsPBFDensityPressure3D::positive_density_error(
			inf, 1000.0) == 0.0);
	CHECK(PhysicsPBFDensityPressure3D::pressure_rate_constraint(
			1050.0, 1000.0, 0.0) == 0.0);
	CHECK(PhysicsPBFDensityPressure3D::pressure_rate_constraint(
			1050.0, 0.0, 0.016) == 0.0);
}

TEST_CASE("[PhysicsPBFDensityPressure] Default fluid has no predictive pressure cost") {
	PBFParticleFluid3D fluid;
	CHECK(fluid.get_density_pressure_iterations() == 0);
	CHECK(fluid.get_last_density_pressure_iterations() == 0);
	CHECK(fluid.get_last_density_pressure_neighbor_evaluations() == 0);
	CHECK(fluid.get_average_predicted_density_error() == 0.0);
	REQUIRE(fluid.create_block(Vector3(-0.35, 1, -0.35), Vector3i(5, 5, 5), 0.175));
	REQUIRE(fluid.step(real_t(1.0 / 60.0)));
	CHECK(fluid.get_last_density_pressure_iterations() == 0);
	CHECK(fluid.get_last_density_pressure_neighbor_evaluations() == 0);
	CHECK(fluid.get_average_predicted_density_error() == 0.0);
}

TEST_CASE("[PhysicsPBFDensityPressure] Native pressured fluid corrects compressed static block") {
	PBFParticleFluid3D pressured;
	PBFParticleFluid3D baseline;
	for (PBFParticleFluid3D *fluid : { &pressured, &baseline }) {
		fluid->set_gravity(Vector3());
		fluid->set_xsph_viscosity(0.0);
		fluid->set_vorticity_confinement(0.0);
		fluid->set_divergence_iterations(0);
		fluid->set_smoothing_radius(0.42);
		fluid->set_solver_iterations(4);
		REQUIRE(fluid->create_block(Vector3(-0.35, 1.0, -0.35), Vector3i(5, 5, 5), 0.175));
	}
	pressured.set_density_pressure_iterations(8);
	pressured.set_density_pressure_tolerance(0.0);
	pressured.set_density_pressure_relaxation(0.8);
	pressured.set_density_pressure_max_velocity_change(0.15);
	REQUIRE(pressured.step(real_t(1.0 / 60.0)));
	REQUIRE(baseline.step(real_t(1.0 / 60.0)));
	CHECK(pressured.get_last_density_pressure_iterations() > 0);
	CHECK(pressured.get_last_density_pressure_iterations() <= 8);
	CHECK(pressured.get_last_density_pressure_neighbor_evaluations() > 0);
	CHECK(pressured.get_last_density_pressure_neighbor_evaluations() <= 18 * 125 * 128);
	CHECK(pressured.get_average_predicted_density_error() >= 0.0);
	CHECK(pressured.get_average_predicted_density_error() < real_t(0.02));
	CHECK(baseline.get_last_density_pressure_neighbor_evaluations() == 0);
	const PackedVector3Array a = pressured.get_particle_positions();
	const PackedVector3Array b = baseline.get_particle_positions();
	int moved_differently = 0;
	for (int i = 0; i < a.size(); ++i) {
		CHECK(a[i].is_finite());
		CHECK(b[i].is_finite());
		if ((a[i] - b[i]).length() > real_t(1e-5)) {
			++moved_differently;
		}
	}
	CHECK(moved_differently > 10);
}

TEST_CASE("[PhysicsPBFDensityPressure] Repeated seeded pressure solve is deterministic") {
	PBFParticleFluid3D a, b;
	for (PBFParticleFluid3D *fluid : { &a, &b }) {
		fluid->set_gravity(Vector3());
		fluid->set_density_pressure_iterations(6);
		fluid->set_density_pressure_tolerance(0.0);
		fluid->set_smoothing_radius(0.42);
		REQUIRE(fluid->create_block(Vector3(-0.3, 1, -0.3), Vector3i(4, 4, 4), 0.17));
		CHECK(fluid->add_velocity_pulse(Vector3(0, 1.3, 0), 0.7, Vector3(3, 0, 0)) > 0);
		for (int step_index = 0; step_index < 10; ++step_index) {
			REQUIRE(fluid->step(real_t(1.0 / 120.0)));
		}
	}
	CHECK(a.get_particle_positions() == b.get_particle_positions());
	CHECK(a.get_particle_velocities() == b.get_particle_velocities());
	CHECK(a.get_average_predicted_density_error() == b.get_average_predicted_density_error());
}

TEST_CASE("[PhysicsPBFDensityPressure] Invalid tuning and clearing state are safe") {
	PBFParticleFluid3D fluid;
	fluid.set_density_pressure_iterations(-1);
	fluid.set_density_pressure_iterations(25);
	fluid.set_density_pressure_tolerance(-1.0);
	fluid.set_density_pressure_relaxation(0.0);
	fluid.set_density_pressure_max_velocity_change(std::numeric_limits<real_t>::infinity());
	CHECK(fluid.get_density_pressure_iterations() == 0);
	CHECK(fluid.get_density_pressure_tolerance() == doctest::Approx(0.002).epsilon(1e-5));
	CHECK(fluid.get_density_pressure_relaxation() == doctest::Approx(0.8).epsilon(1e-5));
	CHECK(fluid.get_density_pressure_max_velocity_change() == doctest::Approx(0.15).epsilon(1e-5));
	fluid.set_density_pressure_iterations(6);
	fluid.set_density_pressure_tolerance(0.0);
	CHECK(fluid.get_density_pressure_iterations() == 6);
	REQUIRE(fluid.create_block(Vector3(-0.35, 1, -0.35), Vector3i(3, 3, 3), 0.175));
	REQUIRE(fluid.step(real_t(1.0 / 60.0)));
	fluid.clear_particles();
	CHECK(fluid.get_average_predicted_density_error() == 0.0);
	CHECK(fluid.get_last_density_pressure_iterations() == 0);
	CHECK(fluid.get_last_density_pressure_neighbor_evaluations() == 0);
}

} // namespace TestPhysicsPBFDensityPressure3D
