/**************************************************************************/
/*  test_physics_softbody_water_drag.cpp                                  */
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

#include "servers/physics_softbody_water_drag.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_water_drag)

namespace TestPhysicsSoftBodyWaterDrag {

static Vector3 total_force(const Vector3 p_forces[3]) {
	return p_forces[0] + p_forces[1] + p_forces[2];
}

TEST_CASE("[PhysicsWaterDrag] Dry triangle receives no water drag") {
	const Vector3 positions[3] = { Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1) };
	const Vector3 velocities[3] = { Vector3(0, -20, 0), Vector3(0, -20, 0), Vector3(0, -20, 0) };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 force[3] = { Vector3(2, 2, 2), Vector3(2, 2, 2), Vector3(2, 2, 2) };
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 1, 1, Vector3(), 0.1, force));
	CHECK(total_force(force) == Vector3());
}

TEST_CASE("[PhysicsWaterDrag] Normal drag opposes downwards velocity without reversing it") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(0, -100, 0), Vector3(0, -100, 0), Vector3(0, -100, 0) };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 force[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 5, 0, Vector3(), 1.0, force));
	const Vector3 combined = total_force(force);
	CHECK(combined.y > 0);
	CHECK(combined.y <= doctest::Approx(300).epsilon(1e-5));
	CHECK(combined.x == doctest::Approx(0));
	CHECK(combined.z == doctest::Approx(0));
	CHECK(real_t(-100) + combined.y / 3.0 <= doctest::Approx(0).epsilon(1e-5));
}

TEST_CASE("[PhysicsWaterDrag] Fluid current accelerates still cloth when skin drag is enabled") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(), Vector3(), Vector3() };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 force[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 1, 1, Vector3(5, 0, 0), 0.1, force));
	CHECK(total_force(force).x > 0);
	CHECK(total_force(force).y == doctest::Approx(0));
	CHECK(total_force(force).z == doctest::Approx(0));
	CHECK(force[0].x == doctest::Approx(force[1].x));
	CHECK(force[0].x == doctest::Approx(force[2].x));
}

TEST_CASE("[PhysicsWaterDrag] Tangential flow is unaffected when skin ratio is zero") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(), Vector3(), Vector3() };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 force[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 1, 0, Vector3(5, 0, 0), 0.1, force));
	CHECK(total_force(force) == Vector3());
}

TEST_CASE("[PhysicsWaterDrag] Partly submerged face uses its clipped area") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, 1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0) };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 full[3], partial[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 2, 1, 1, 0, Vector3(), real_t(1e-5), full));
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1, 1, 0, Vector3(), real_t(1e-5), partial));
	const Vector3 full_sum = total_force(full);
	const Vector3 partial_sum = total_force(partial);
	CHECK(full_sum.x < 0);
	CHECK(partial_sum.x < 0);
	CHECK((partial_sum.x / full_sum.x) == doctest::Approx(0.75).epsilon(0.002));
}

TEST_CASE("[PhysicsWaterDrag] Pinned nodes are fixed and all-pinned faces do no work") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(0, -3, 0), Vector3(0, -3, 0), Vector3(0, -3, 0) };
	const real_t masses[3] = { 0, 0, 1 };
	const real_t pinned[3] = { 0, 0, 0 };
	Vector3 forces[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 1, 1, Vector3(), 0.1, forces));
	CHECK(forces[0] == Vector3());
	CHECK(forces[1] == Vector3());
	CHECK(forces[2].y > 0);
	CHECK(physics_softbody_water_drag_face(positions, velocities, pinned, 0, 1000, 1, 1, Vector3(), 0.1, forces));
	CHECK(total_force(forces) == Vector3());
}

TEST_CASE("[PhysicsWaterDrag] Flipping face winding cannot reverse drag direction") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 reversed[3] = { positions[0], positions[2], positions[1] };
	const Vector3 velocities[3] = { Vector3(0, -3, 0), Vector3(0, -3, 0), Vector3(0, -3, 0) };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 force[3], flipped[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 100, 1, 0, Vector3(), 0.1, force));
	CHECK(physics_softbody_water_drag_face(reversed, velocities, masses, 0, 100, 1, 0, Vector3(), 0.1, flipped));
	CHECK(total_force(force).is_equal_approx(total_force(flipped)));
	CHECK(total_force(force).y > 0);
}

TEST_CASE("[PhysicsWaterDrag] Zero density or coefficient does not change output velocities") {
	const Vector3 positions[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1) };
	const real_t masses[3] = { 1, 1, 1 };
	Vector3 force[3];
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 0, 1, 1, Vector3(), 0.1, force));
	CHECK(total_force(force) == Vector3());
	CHECK(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 0, 1, Vector3(), 0.1, force));
	CHECK(total_force(force) == Vector3());
}

TEST_CASE("[PhysicsWaterDrag] Invalid and degenerate inputs preserve outputs atomically") {
	const Vector3 positions[3] = { Vector3(), Vector3(1, 0, 0), Vector3(2, 0, 0) };
	const Vector3 valid[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
	const Vector3 velocities[3] = { Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1) };
	const real_t masses[3] = { 1, 1, 1 };
	const real_t invalid_masses[3] = { 1, -1, 1 };
	Vector3 out[3] = { Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9) };
	CHECK_FALSE(physics_softbody_water_drag_face(positions, velocities, masses, 0, 1000, 1, 1, Vector3(), 0.1, out));
	CHECK_FALSE(physics_softbody_water_drag_face(valid, velocities, invalid_masses, 0, 1000, 1, 1, Vector3(), 0.1, out));
	CHECK_FALSE(physics_softbody_water_drag_face(valid, velocities, masses, 0, 1000, -1, 1, Vector3(), 0.1, out));
	CHECK_FALSE(physics_softbody_water_drag_face(valid, velocities, masses, 0, 1000, 1, 1, Vector3(), 0.0, out));
	CHECK_FALSE(physics_softbody_water_drag_face(valid, velocities, masses, 0, 1000, 1, 1,
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0), 0.1, out));
	CHECK(out[0] == Vector3(1, 2, 3));
	CHECK(out[1] == Vector3(4, 5, 6));
	CHECK(out[2] == Vector3(7, 8, 9));
}

} // namespace TestPhysicsSoftBodyWaterDrag
