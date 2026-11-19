/**************************************************************************/
/*  test_physics_softbody_volume_safe.cpp                                 */
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

#include "servers/physics_softbody_volume_safe.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_volume_safe)

namespace TestPhysicsSoftBodyVolumeSafe {

TEST_CASE("[PhysicsVolume] Closed volume is scale-invariant at small and large sizes") {
	const double scales[4] = { 1e-6, 1e-3, 1.0, 1e3 };
	for (double scale : scales) {
		const double unit_tetra_volume = (scale * scale * scale) / 6.0;
		CHECK(physics_softbody_volume_is_non_degenerate(unit_tetra_volume, scale));
		CHECK(physics_softbody_volume_is_non_degenerate(-unit_tetra_volume, scale));
	}
}

TEST_CASE("[PhysicsVolume] Nearly flat and invalid volume rest states are rejected") {
	CHECK_FALSE(physics_softbody_volume_is_non_degenerate(0.0, 1.0));
	CHECK_FALSE(physics_softbody_volume_is_non_degenerate(1e-12, 1.0));
	CHECK_FALSE(physics_softbody_volume_is_non_degenerate(1.0, 0.0));
	CHECK_FALSE(physics_softbody_volume_is_non_degenerate(1.0, -1.0));
	CHECK_FALSE(physics_softbody_volume_is_non_degenerate(
			std::numeric_limits<double>::infinity(), 1.0));
	CHECK_FALSE(physics_softbody_volume_is_non_degenerate(
			1.0, std::numeric_limits<double>::infinity()));
}

TEST_CASE("[PhysicsVolume] Triangle gradients match the oriented cross-product") {
	Vector3 grad_a, grad_b, grad_c;
	CHECK(physics_softbody_volume_face_gradients(
			Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(), grad_a, grad_b, grad_c));
	CHECK(grad_a.z == doctest::Approx(1.0 / 6.0).epsilon(1e-5));
	CHECK(grad_b == Vector3());
	CHECK(grad_c == Vector3());
}

TEST_CASE("[PhysicsVolume] Double gradient differences keep extreme finite float coordinates") {
	const real_t large = real_t(1e38);
	const real_t tiny = real_t(1e-10);
	Vector3 grad_a, grad_b, grad_c;
	CHECK(physics_softbody_volume_face_gradients(
			Vector3(-large, 0, 0), Vector3(large, 0, 0), Vector3(large, tiny, 0),
			Vector3(), grad_a, grad_b, grad_c));
	CHECK(grad_a.is_finite());
	CHECK(grad_b.is_finite());
	CHECK(grad_c.is_finite());
	CHECK(grad_a.z > real_t(0.0));
	CHECK(grad_b.z > real_t(0.0));
}

TEST_CASE("[PhysicsVolume] Nonfinite inputs never mutate gradient outputs") {
	const Vector3 previous_a(1, 2, 3), previous_b(4, 5, 6), previous_c(7, 8, 9);
	Vector3 grad_a = previous_a, grad_b = previous_b, grad_c = previous_c;
	CHECK_FALSE(physics_softbody_volume_face_gradients(
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(),
			grad_a, grad_b, grad_c));
	CHECK(grad_a == previous_a);
	CHECK(grad_b == previous_b);
	CHECK(grad_c == previous_c);
}

TEST_CASE("[PhysicsVolume] Unrepresentable gradients are rejected atomically") {
	const real_t large = std::numeric_limits<real_t>::max();
	const Vector3 previous_a(1, 2, 3), previous_b(4, 5, 6), previous_c(7, 8, 9);
	Vector3 grad_a = previous_a, grad_b = previous_b, grad_c = previous_c;
	CHECK_FALSE(physics_softbody_volume_face_gradients(
			Vector3(), Vector3(large, 0, 0), Vector3(0, large, 0),
			Vector3(), grad_a, grad_b, grad_c));
	CHECK(grad_a == previous_a);
	CHECK(grad_b == previous_b);
	CHECK(grad_c == previous_c);
}

} // namespace TestPhysicsSoftBodyVolumeSafe
