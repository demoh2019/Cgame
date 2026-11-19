/**************************************************************************/
/*  test_physics_xpbd_tether.cpp                                          */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_xpbd_tether.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_tether)

namespace TestPhysicsXPBDTether {

TEST_CASE("[PhysicsXPBDTether] Multi-source graph retains shortest geodesic to nearest pin") {
	LocalVector<PhysicsXPBDTetherEdge> edges;
	edges.push_back({ 0, 1, real_t(1) });
	edges.push_back({ 1, 2, real_t(1) });
	edges.push_back({ 2, 3, real_t(1) });
	edges.push_back({ 1, 4, real_t(2) });
	LocalVector<uint32_t> pins;
	pins.push_back(0);
	pins.push_back(3);
	LocalVector<PhysicsXPBDTether> tether;
	CHECK(physics_xpbd_build_tethers(6, edges, pins, real_t(0.25), tether));
	CHECK(tether.size() == 6);
	CHECK(tether[0].anchor == 0);
	CHECK(tether[3].anchor == 3);
	CHECK(tether[1].anchor == 0);
	CHECK(tether[2].anchor == 3);
	CHECK(tether[4].anchor == 0);
	CHECK(tether[5].anchor == UINT32_MAX); // Disconnected particle.
	CHECK(Math::is_equal_approx(tether[1].max_length, real_t(1.25)));
	CHECK(Math::is_equal_approx(tether[4].max_length, real_t(3.75)));
}

TEST_CASE("[PhysicsXPBDTether] Folded cloth respects geodesic rather than Euclidean shortcuts") {
	// Four vertices are very close in space, but connected by three
	// structural edges. The tether must not behave like a short rod.
	LocalVector<PhysicsXPBDTetherEdge> edges;
	edges.push_back({ 0, 1, real_t(2) });
	edges.push_back({ 1, 2, real_t(2) });
	edges.push_back({ 2, 3, real_t(2) });
	LocalVector<uint32_t> pins;
	pins.push_back(0);
	LocalVector<PhysicsXPBDTether> tether;
	CHECK(physics_xpbd_build_tethers(4, edges, pins, real_t(0), tether));
	CHECK(tether[3].anchor == 0);
	CHECK(Math::is_equal_approx(tether[3].max_length, real_t(6)));
	Vector3 folded_vertex(real_t(0.1), 0, 0);
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_tether(folded_vertex, Vector3(), real_t(1),
			tether[3].max_length, real_t(0.1), lambda));
	CHECK(folded_vertex == Vector3(real_t(0.1), 0, 0));
}

TEST_CASE("[PhysicsXPBDTether] Equal-length choices prefer the lower pinned index") {
	LocalVector<PhysicsXPBDTetherEdge> edges;
	edges.push_back({ 0, 1, 1 });
	edges.push_back({ 2, 1, 1 });
	LocalVector<uint32_t> pins;
	pins.push_back(2);
	pins.push_back(0);
	pins.push_back(0); // Multiple visual aliases of one physical pin.
	LocalVector<PhysicsXPBDTether> tethers;
	CHECK(physics_xpbd_build_tethers(3, edges, pins, 0, tethers));
	CHECK(tethers[1].anchor == 0);
	CHECK(tethers[1].max_length == real_t(1));
	CHECK(physics_xpbd_build_tethers(3, edges, pins, 0, tethers));
	CHECK(tethers[1].anchor == 0);
}

TEST_CASE("[PhysicsXPBDTether] Changing the pin set recomputes anchors without stale results") {
	LocalVector<PhysicsXPBDTetherEdge> edges;
	edges.push_back({ 0, 1, 1 });
	edges.push_back({ 1, 2, 1 });
	LocalVector<uint32_t> pins;
	pins.push_back(0);
	LocalVector<PhysicsXPBDTether> tethers;
	CHECK(physics_xpbd_build_tethers(3, edges, pins, 0, tethers));
	CHECK(tethers[2].anchor == 0);
	CHECK(tethers[2].max_length == real_t(2));
	pins.clear();
	pins.push_back(2);
	CHECK(physics_xpbd_build_tethers(3, edges, pins, 0, tethers));
	CHECK(tethers[0].anchor == 2);
	CHECK(tethers[0].max_length == real_t(2));
	pins.clear();
	CHECK_FALSE(physics_xpbd_build_tethers(3, edges, pins, 0, tethers));
	CHECK(tethers.size() == 0);
}

TEST_CASE("[PhysicsXPBDTether] Invalid, zero-length, or disconnected edges are ignored") {
	LocalVector<PhysicsXPBDTetherEdge> edges;
	edges.push_back({ 0, 1, 1 });
	edges.push_back({ 1, 2, 0 });
	edges.push_back({ 1, 9, 1 });
	edges.push_back({ 2, 2, 1 });
	edges.push_back({ 0, 2, std::numeric_limits<real_t>::infinity() });
	LocalVector<uint32_t> pins;
	pins.push_back(0);
	pins.push_back(999);
	LocalVector<PhysicsXPBDTether> tethers;
	CHECK(physics_xpbd_build_tethers(4, edges, pins, 0, tethers));
	CHECK(tethers[1].anchor == 0);
	CHECK(tethers[2].anchor == UINT32_MAX);
	CHECK(tethers[3].anchor == UINT32_MAX);
	CHECK_FALSE(physics_xpbd_build_tethers(4, edges, pins, real_t(-1), tethers));
	CHECK(tethers.size() == 0);
}

TEST_CASE("[PhysicsXPBDTether] Large cloth grid scales with structural edges and pinned vertices") {
	constexpr uint32_t side = 32;
	LocalVector<PhysicsXPBDTetherEdge> edges;
	for (uint32_t row = 0; row < side; ++row) {
		for (uint32_t col = 0; col < side; ++col) {
			const uint32_t id = row * side + col;
			if (col + 1 < side) {
				edges.push_back({ id, id + 1, 1 });
			}
			if (row + 1 < side) {
				edges.push_back({ id, id + side, 1 });
			}
		}
	}
	LocalVector<uint32_t> pins;
	pins.push_back(0);
	pins.push_back(side - 1);
	LocalVector<PhysicsXPBDTether> tethers;
	CHECK(physics_xpbd_build_tethers(side * side, edges, pins, 0, tethers));
	CHECK(tethers.size() == side * side);
	for (uint32_t row = 0; row < side; ++row) {
		for (uint32_t col = 0; col < side; ++col) {
			const uint32_t id = row * side + col;
			const uint32_t from_left = row + col;
			const uint32_t from_right = row + (side - 1 - col);
			const uint32_t expected_anchor = from_left <= from_right ? 0 : side - 1;
			CHECK(tethers[id].anchor == expected_anchor);
			CHECK(tethers[id].max_length == real_t(MIN(from_left, from_right)));
		}
	}
}

TEST_CASE("[PhysicsXPBDTether] Hard limit applies only tensile corrections") {
	Vector3 vertex(3, 0, 0);
	const Vector3 anchor;
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_tether(vertex, anchor, 1, 2, 0, lambda));
	CHECK(vertex.is_equal_approx(Vector3(2, 0, 0)));
	CHECK(Math::is_equal_approx(lambda, real_t(-1)));
	lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_tether(vertex, anchor, 1, 2, 0, lambda));
	CHECK(vertex.is_equal_approx(Vector3(2, 0, 0)));
}

TEST_CASE("[PhysicsXPBDTether] Compliant leash preserves softness across iterations") {
	Vector3 vertex(3, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_tether(vertex, Vector3(), 1, 2, 1, lambda));
	CHECK(Math::is_equal_approx(vertex.x, real_t(2.5)));
	CHECK(Math::is_equal_approx(lambda, real_t(-0.5)));
	for (int i = 0; i < 16; ++i) {
		physics_xpbd_solve_tether(vertex, Vector3(), 1, 2, 1, lambda);
	}
	CHECK(Math::is_equal_approx(vertex.x, real_t(2.5)));
	CHECK(Math::is_equal_approx(lambda, real_t(-0.5)));
}

TEST_CASE("[PhysicsXPBDTether] Pin remains fixed while a moving anchor is followed") {
	Vector3 free(5, 0, 0);
	Vector3 anchor(1, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_tether(free, anchor, 2, 2, 0, lambda));
	CHECK(free.is_equal_approx(Vector3(3, 0, 0)));
	CHECK(anchor == Vector3(1, 0, 0));
	anchor = Vector3(2, 0, 0);
	lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_tether(free, anchor, 2, 2, 0, lambda));
	CHECK(free.is_equal_approx(Vector3(3, 0, 0)));
	free = Vector3(8, 0, 0);
	CHECK(physics_xpbd_solve_tether(free, anchor, 2, 2, 0, lambda));
	CHECK(free.is_equal_approx(Vector3(4, 0, 0)));
}

TEST_CASE("[PhysicsXPBDTether] Degenerate and nonfinite inputs cannot move the particle") {
	Vector3 free(3, 0, 0);
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_tether(free, Vector3(), 0, 1, 0, lambda));
	CHECK_FALSE(physics_xpbd_solve_tether(free, Vector3(), 1, -1, 0, lambda));
	CHECK_FALSE(physics_xpbd_solve_tether(free, Vector3(), 1, 1, -1, lambda));
	CHECK_FALSE(physics_xpbd_solve_tether(free, Vector3(), 1, 1,
			std::numeric_limits<real_t>::infinity(), lambda));
	CHECK(free == Vector3(3, 0, 0));
	CHECK(lambda == real_t(0));
}

} // namespace TestPhysicsXPBDTether
