/**************************************************************************/
/*  test_physics_pbf_surface_tension_3d.cpp                               */
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
#include "servers/physics_pbf_surface_tension_3d.h"
#include "tests/test_macros.h"

#include <initializer_list>
#include <limits>

TEST_FORCE_LINK(test_physics_pbf_surface_tension_3d)

namespace TestPhysicsPBFSurfaceTension3D {

TEST_CASE("[PhysicsPBFSurface] Cohesion kernel has compact support and repulsive short range") {
	const real_t h = 0.42;
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(0.0, h) == 0.0);
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(h, h) == 0.0);
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(h * 1.01, h) == 0.0);
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(-0.1, h) == 0.0);
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(h * 0.05, h) < 0.0);
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(h * 0.65, h) > 0.0);
	CHECK(Math::is_finite(PhysicsPBFSurfaceTension3D::cohesion_kernel(h * 0.5, h)));
}

TEST_CASE("[PhysicsPBFSurface] Long-distance cohesion attracts and short-distance repels") {
	const Vector3 far_left(-0.29, 0, 0);
	const Vector3 near_left(-0.015, 0, 0);
	const Vector3 normal;
	const real_t h = 0.42;
	const Vector3 attract = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			far_left, normal, normal, 1000.0, 1000.0, 1000.0,
			6.0, h, 0.12, 0.0, real_t(1.0 / 60.0), 0.02);
	const Vector3 repel = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			near_left, normal, normal, 1000.0, 1000.0, 1000.0,
			6.0, h, 0.12, 0.0, real_t(1.0 / 60.0), 0.02);
	CHECK(attract.x > 0.0);
	CHECK(repel.x < 0.0);
	CHECK(attract.y == 0.0);
	CHECK(repel.y == 0.0);
}

TEST_CASE("[PhysicsPBFSurface] Pairwise Newton action-reaction and density weights are symmetric") {
	const Vector3 disp(-0.26, 0.05, 0);
	const Vector3 n1(1, 2, 0);
	const Vector3 n2(-2, 1, 0);
	const real_t w1 = PhysicsPBFSurfaceTension3D::symmetric_density_weight(
			850.0, 1100.0, 1000.0);
	const real_t w2 = PhysicsPBFSurfaceTension3D::symmetric_density_weight(
			1100.0, 850.0, 1000.0);
	CHECK(w1 == doctest::Approx(w2).epsilon(1e-5));
	const Vector3 dv1 = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			disp, n1, n2, 850.0, 1100.0, 1000.0, 6.0, 0.42,
			0.08, 0.035, real_t(1.0 / 60.0), 0.015);
	const Vector3 dv2 = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			-disp, n2, n1, 1100.0, 850.0, 1000.0, 6.0, 0.42,
			0.08, 0.035, real_t(1.0 / 60.0), 0.015);
	CHECK((dv1 + dv2).length() < real_t(1e-6));
	CHECK(dv1.length() > 0.0);
}

TEST_CASE("[PhysicsPBFSurface] Curvature acts against color-normal discontinuity") {
	const Vector3 radial(0.2, 0, 0);
	const Vector3 ni(0, 1, 0);
	const Vector3 nj(0, -1, 0);
	const Vector3 dv = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			radial, ni, nj, 1000.0, 1000.0, 1000.0, 6.0, 0.42,
			0.0, 0.5, real_t(1.0 / 60.0), 0.05);
	CHECK(dv.x == 0.0);
	CHECK(dv.y < 0.0);
	CHECK(dv.z == 0.0);
	const Vector3 grad(1, -2, 3);
	CHECK(PhysicsPBFSurfaceTension3D::color_normal_pair(
			grad, 0.01, 0.4).is_equal_approx(Vector3(0.004, -0.008, 0.012)));
}

TEST_CASE("[PhysicsPBFSurface] Pairwise safety cap controls extreme cohesion impulses") {
	const Vector3 dv = PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			Vector3(-0.28, 0, 0), Vector3(), Vector3(),
			50.0, 50.0, 1000.0, 100.0, 0.42,
			2.0, 2.0, 0.1, 0.005);
	CHECK(dv.is_finite());
	CHECK(Math::abs(dv.length() - real_t(0.005)) < real_t(0.00001));
	CHECK(dv.x > 0.0);
	CHECK(PhysicsPBFSurfaceTension3D::symmetric_density_weight(1, 1, 1000) <= 4.0);
}

TEST_CASE("[PhysicsPBFSurface] Zero and nonfinite parameters produce no impulse") {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	const Vector3 a(0.25, 0, 0);
	const Vector3 zero;
	CHECK(PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			a, zero, zero, 1000., 1000., 1000., 6., 0.42,
			0., 0., 0.016, 0.01) == Vector3());
	CHECK(PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			zero, zero, zero, 1000., 1000., 1000., 6., 0.42,
			0.05, 0., 0.016, 0.01) == Vector3());
	CHECK(PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			a, zero, zero, 1000., 1000., 1000., 6., 0.42,
			0.05, 0., -1.0, 0.01) == Vector3());
	CHECK(PhysicsPBFSurfaceTension3D::pair_velocity_increment(
			a, zero, zero, inf, 1000., 1000., 6., 0.42,
			0.05, 0., 0.016, 0.01) == Vector3());
	CHECK(PhysicsPBFSurfaceTension3D::color_normal_pair(
			Vector3(inf, 0, 0), 0.006, 0.42) == Vector3());
	CHECK(PhysicsPBFSurfaceTension3D::cohesion_kernel(0.2, inf) == 0.0);
}

TEST_CASE("[PhysicsPBFSurface] Native fluid is off by default and changes velocity only when enabled") {
	PBFParticleFluid3D active;
	PBFParticleFluid3D baseline;
	for (PBFParticleFluid3D *fluid : { &active, &baseline }) {
		fluid->set_gravity(Vector3());
		fluid->set_xsph_viscosity(0.0);
		fluid->set_vorticity_confinement(0.0);
		fluid->set_divergence_iterations(0);
		fluid->set_density_pressure_iterations(0);
		fluid->set_smoothing_radius(0.42);
		REQUIRE(fluid->create_block(Vector3(-0.38, 1.0, -0.38), Vector3i(5, 5, 5), 0.19));
	}
	CHECK(baseline.get_surface_cohesion() == 0.0);
	CHECK(baseline.get_surface_curvature() == 0.0);
	active.set_surface_cohesion(0.06);
	active.set_surface_curvature(0.025);
	REQUIRE(active.step(real_t(1.0 / 60.0)));
	REQUIRE(baseline.step(real_t(1.0 / 60.0)));
	CHECK(active.get_last_surface_tension_pairs() > 0);
	CHECK(active.get_last_surface_tension_neighbor_evaluations() <= 3 * 125 * 128);
	CHECK(active.get_mean_surface_normal_magnitude() > 0.0);
	CHECK(baseline.get_last_surface_tension_pairs() == 0);
	CHECK(baseline.get_last_surface_tension_neighbor_evaluations() == 0);
	CHECK(active.get_particle_positions() == baseline.get_particle_positions());
	const PackedVector3Array a = active.get_particle_velocities();
	const PackedVector3Array b = baseline.get_particle_velocities();
	Vector3 delta_momentum;
	int changed = 0;
	for (int i = 0; i < a.size(); ++i) {
		CHECK(a[i].is_finite());
		CHECK(b[i].is_finite());
		delta_momentum += a[i] - b[i];
		if ((a[i] - b[i]).length() > real_t(1e-6)) {
			++changed;
		}
	}
	CHECK(changed > 10);
	CHECK(delta_momentum.length() < real_t(0.002));
}

TEST_CASE("[PhysicsPBFSurface] Seed determinism, safe reset and lazy off/on buffers") {
	PBFParticleFluid3D first, second;
	for (PBFParticleFluid3D *fluid : { &first, &second }) {
		fluid->set_gravity(Vector3());
		fluid->set_smoothing_radius(0.42);
		fluid->set_surface_cohesion(0.08);
		fluid->set_surface_curvature(0.02);
		REQUIRE(fluid->create_block(Vector3(-0.4, 1, -0.4), Vector3i(4, 4, 4), 0.19));
		for (int t = 0; t < 8; ++t) {
			REQUIRE(fluid->step(real_t(1.0 / 120.0)));
		}
	}
	CHECK(first.get_particle_positions() == second.get_particle_positions());
	CHECK(first.get_particle_velocities() == second.get_particle_velocities());
	first.set_surface_cohesion(0.0);
	first.set_surface_curvature(0.0);
	CHECK(first.get_last_surface_tension_pairs() == 0);
	CHECK(first.get_last_surface_tension_neighbor_evaluations() == 0);
	CHECK(first.get_mean_surface_normal_magnitude() == 0.0);
	first.set_surface_cohesion(-1.0);
	first.set_surface_curvature(std::numeric_limits<real_t>::infinity());
	CHECK(first.get_surface_cohesion() == 0.0);
	CHECK(first.get_surface_curvature() == 0.0);
	first.set_surface_cohesion(0.1);
	REQUIRE(first.step(real_t(1.0 / 60.0)));
	CHECK(first.get_last_surface_tension_pairs() > 0);
	first.clear_particles();
	CHECK(first.get_last_surface_tension_pairs() == 0);
	CHECK(first.get_last_surface_tension_neighbor_evaluations() == 0);
	CHECK(first.get_mean_surface_normal_magnitude() == 0.0);
}

} // namespace TestPhysicsPBFSurfaceTension3D
