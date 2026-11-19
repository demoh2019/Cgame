/**************************************************************************/
/*  test_physics_pbf_rigid_coupling_3d.cpp                                */
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

#include "servers/physics_pbf_rigid_coupling_3d.h"
#include "tests/test_macros.h"

#include <initializer_list>
#include <limits>

TEST_FORCE_LINK(test_physics_pbf_rigid_coupling_3d)

namespace TestPhysicsPBFRigidCoupling3D {

TEST_CASE("[PhysicsPBFContact] Equal-mass centered elastic impact exchanges velocities") {
	PhysicsPBFRigidContactResult3D contact;
	const Vector3 particle_velocity(0, -3, 0);
	const Vector3 rigid_velocity(0, 0, 0);
	REQUIRE(physics_pbf_rigid_contact_solve_3d(
			particle_velocity, 2.0, rigid_velocity, 0.5,
			Basis(), Vector3(), Vector3(0, 1, 0), 1.0, 100.0, contact));
	CHECK(contact.impulse_magnitude == doctest::Approx(6.0).epsilon(1e-5));
	CHECK(contact.particle_velocity.y == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(contact.body_impulse.y == doctest::Approx(-6.0).epsilon(1e-5));
	const Vector3 body_velocity_after = rigid_velocity + contact.body_impulse * real_t(0.5);
	CHECK(body_velocity_after.y == doctest::Approx(-3.0).epsilon(1e-5));
	// One particle and one rigid body: net linear impulse exactly zero.
	CHECK((contact.particle_velocity - particle_velocity) * real_t(2.0) +
			contact.body_impulse == Vector3());
}

TEST_CASE("[PhysicsPBFContact] Inelastic central impulse preserves linear momentum and loses energy") {
	const real_t particle_mass = 3.0;
	const real_t rigid_mass = 7.0;
	const Vector3 vp(0, -4, 0), vb(0, 1, 0);
	PhysicsPBFRigidContactResult3D impact;
	REQUIRE(physics_pbf_rigid_contact_solve_3d(vp, particle_mass, vb,
			real_t(1.0) / rigid_mass, Basis(), Vector3(),
			Vector3(0, 1, 0), 0.0, 100.0, impact));
	const Vector3 new_body_v = vb + impact.body_impulse / rigid_mass;
	CHECK(impact.particle_velocity.y == doctest::Approx(new_body_v.y).epsilon(1e-5));
	const Vector3 old_momentum = vp * particle_mass + vb * rigid_mass;
	const Vector3 new_momentum = impact.particle_velocity * particle_mass + new_body_v * rigid_mass;
	CHECK((new_momentum - old_momentum).length() < real_t(1e-4));
	const real_t initial_energy = real_t(0.5) * (particle_mass * vp.length_squared() +
			rigid_mass * vb.length_squared());
	const real_t final_energy = real_t(0.5) * (particle_mass * impact.particle_velocity.length_squared() +
			rigid_mass * new_body_v.length_squared());
	CHECK(final_energy < initial_energy);
}

TEST_CASE("[PhysicsPBFContact] Offset impacts produce angular reaction and conserve angular impulse") {
	const Vector3 r(1, 0, 0);
	const Vector3 n(0, 1, 0);
	const Basis inv_inertia = Basis::from_scale(Vector3(1, 1, 0.25));
	PhysicsPBFRigidContactResult3D impact;
	REQUIRE(physics_pbf_rigid_contact_solve_3d(
			Vector3(0, -4, 0), 2.0, Vector3(), 0.25,
			inv_inertia, r, n, 0.0, 100.0, impact));
	// Rotational mass along n: (r x n)=(0,0,1); inverse inertia gives 0.25.
	const real_t inverse_effective_mass = real_t(0.5 + 0.25 + 0.25);
	CHECK(impact.impulse_magnitude ==
			doctest::Approx(4.0 / inverse_effective_mass).epsilon(1e-5));
	CHECK(r.cross(impact.body_impulse).z < 0.0);
	const Vector3 delta_particle_momentum = (impact.particle_velocity - Vector3(0, -4, 0)) * real_t(2.0);
	CHECK((delta_particle_momentum + impact.body_impulse).length() < real_t(1e-4));
	CHECK((r.cross(delta_particle_momentum) + r.cross(impact.body_impulse)).length() < real_t(1e-4));
}

TEST_CASE("[PhysicsPBFContact] Moving and spinning body uses relative contact velocity") {
	const Vector3 lever(1, 0, 0);
	const Vector3 body_linear(0, -1, 0);
	const Vector3 body_spin(0, 0, 2);
	const Vector3 body_contact_velocity = body_linear + body_spin.cross(lever); // +Y.
	PhysicsPBFRigidContactResult3D impact;
	REQUIRE(physics_pbf_rigid_contact_solve_3d(
			Vector3(0, 0, 0), 1.0, body_contact_velocity, 0.5,
			Basis::from_scale(Vector3(1, 1, 0.5)), lever,
			Vector3(0, 1, 0), 0.5, 100.0, impact));
	CHECK(impact.particle_velocity.y > 0.0);
	CHECK(impact.body_impulse.y < 0.0);
	CHECK(impact.body_impulse.length() < real_t(2.0));
}

TEST_CASE("[PhysicsPBFContact] Capped impulses retain action reaction exactly") {
	PhysicsPBFRigidContactResult3D impact;
	REQUIRE(physics_pbf_rigid_contact_solve_3d(
			Vector3(0, -100, 0), 5.0, Vector3(), 0.01,
			Basis(), Vector3(), Vector3(0, 1, 0), 1.0, 7.0, impact));
	CHECK(impact.impulse_magnitude == doctest::Approx(7.0).epsilon(1e-5));
	CHECK(((impact.particle_velocity - Vector3(0, -100, 0)) * real_t(5.0) +
			impact.body_impulse).length() < real_t(0.0001));
}

TEST_CASE("[PhysicsPBFContact] No impulse for separating, static or degenerate contacts") {
	PhysicsPBFRigidContactResult3D impact;
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			Vector3(0, 1, 0), 1.0, Vector3(), 1.0, Basis(),
			Vector3(), Vector3(0, 1, 0), 0.1, 20.0, impact));
	CHECK(impact.impulse_magnitude == 0.0);
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			Vector3(0, -1, 0), 1.0, Vector3(), 0.0, Basis(),
			Vector3(), Vector3(0, 1, 0), 0.1, 20.0, impact));
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			Vector3(0, -1, 0), 1.0, Vector3(), 1.0, Basis(),
			Vector3(), Vector3(), 0.1, 20.0, impact));
	CHECK(impact.impulse_magnitude == 0.0);
}

TEST_CASE("[PhysicsPBFContact] Invalid nonfinite restitution and mass fail atomically") {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	PhysicsPBFRigidContactResult3D impact;
	const Vector3 down(0, -1, 0), up(0, 1, 0);
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			down, 1.0, Vector3(), 0.5, Basis(), Vector3(), up, 1.01, 10.0, impact));
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			down, inf, Vector3(), 0.5, Basis(), Vector3(), up, 0.0, 10.0, impact));
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			down, 1.0, Vector3(), 0.5, Basis(), Vector3(inf, 0, 0), up, 0.0, 10.0, impact));
	CHECK_FALSE(physics_pbf_rigid_contact_solve_3d(
			down, 1.0, Vector3(), 0.5, Basis(), Vector3(), up, 0.0, inf, impact));
	CHECK(impact.body_impulse == Vector3());
	CHECK(impact.impulse_magnitude == 0.0);
}

TEST_CASE("[PhysicsPBFContact] Restitution series has correct normal relative response") {
	const Vector3 normal(0, 1, 0);
	for (real_t restitution : { real_t(0.0), real_t(0.2), real_t(0.8), real_t(1.0) }) {
		PhysicsPBFRigidContactResult3D impact;
		REQUIRE(physics_pbf_rigid_contact_solve_3d(
				Vector3(0, -4, 0), 3.0, Vector3(), 0.5,
				Basis(), Vector3(), normal, restitution, 1000.0, impact));
		const Vector3 new_body_v = impact.body_impulse * real_t(0.5);
		const real_t relative_out = (impact.particle_velocity - new_body_v).dot(normal);
		CHECK(Math::abs(relative_out - real_t(4.0) * restitution) < real_t(0.0001));
	}
}

} // namespace TestPhysicsPBFRigidCoupling3D
