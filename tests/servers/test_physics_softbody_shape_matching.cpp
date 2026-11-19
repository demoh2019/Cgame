/**************************************************************************/
/*  test_physics_softbody_shape_matching.cpp                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_softbody_shape_matching)

#include "servers/physics_softbody_shape_matching.h"

#include <array>
#include <limits>

namespace TestPhysicsSoftBodyShapeMatching {

struct ShapeNode {
	Vector3 s;
	Vector3 x;
	real_t im = 1.0;
};

using Nodes = std::array<ShapeNode, 8>;

static Nodes make_box() {
	Nodes nodes;
	for (int i = 0; i < 8; ++i) {
		const Vector3 point(i & 1 ? 1 : -1, i & 2 ? 1 : -1, i & 4 ? 1 : -1);
		nodes[i] = { point, point, 1 };
	}
	return nodes;
}

TEST_CASE("[Physics] Shape matching leaves rigid translations and rotations unchanged") {
	Nodes nodes = make_box();
	const Vector3 offset(10, -7, 4);
	for (ShapeNode &node : nodes) {
		const Vector3 &s = node.s;
		// Proper +90 degree rotation about Z.
		node.x = Vector3(-s.y, s.x, s.z) + offset;
	}
	Nodes before = nodes;
	REQUIRE(physics_softbody_project_shape_matching(nodes, real_t(1.0)));
	for (int i = 0; i < 8; ++i) {
		CHECK(nodes[i].x.distance_to(before[i].x) < real_t(0.0001));
		CHECK(nodes[i].s == before[i].s);
	}
}

TEST_CASE("[Physics] Shape matching restores sheared soft solid without pin movement") {
	Nodes nodes = make_box();
	nodes[0].im = 0.0;
	const Vector3 pinned_position = nodes[0].x;
	// A large local shear disrupts the rest shape but not its topology.
	nodes[7].x += Vector3(0.8, 0.0, 0.0);
	const real_t initial_error = nodes[7].x.distance_to(nodes[7].s);
	REQUIRE(physics_softbody_project_shape_matching(nodes, real_t(0.75)));
	CHECK(nodes[0].x == pinned_position);
	CHECK(nodes[7].x.distance_to(nodes[7].s) < initial_error);
	for (const ShapeNode &node : nodes) {
		CHECK(node.x.is_finite());
	}
}

TEST_CASE("[Physics] Shape matching restores totally collapsed geometry deterministically") {
	Nodes nodes = make_box();
	const Vector3 position(3, 4, 5);
	for (ShapeNode &node : nodes) {
		node.x = position;
	}
	REQUIRE(physics_softbody_project_shape_matching(nodes, real_t(1.0)));
	for (const ShapeNode &node : nodes) {
		CHECK(node.x.distance_to(position + node.s) < real_t(0.0001));
	}
}

TEST_CASE("[Physics] Shape matching preserves proper orientation instead of reflecting shape") {
	Nodes nodes = make_box();
	for (ShapeNode &node : nodes) {
		node.x.x = -node.x.x; // Mirrored source configuration.
	}
	REQUIRE(physics_softbody_project_shape_matching(nodes, real_t(1.0)));
	// Even though an improper reflection would fit perfectly, Horn's
	// quaternion yields only rotations and preserves the orientation
	// of this tetrahedron of distinct cube corners.
	const auto signed_volume = [](const Nodes &p_nodes) {
		return (p_nodes[1].x - p_nodes[0].x).cross(p_nodes[2].x - p_nodes[0].x)
				.dot(p_nodes[4].x - p_nodes[0].x);
	};
	Nodes rest = make_box();
	CHECK(signed_volume(nodes) * signed_volume(rest) > 0.0);
}

TEST_CASE("[Physics] Shape matching respects pins and rejects invalid inputs atomically") {
	Nodes nodes = make_box();
	for (ShapeNode &node : nodes) {
		node.im = 0.0;
	}
	CHECK_FALSE(physics_softbody_project_shape_matching(nodes, real_t(0.5)));
	nodes[0].im = 1.0;
	const Nodes original = nodes;
	CHECK_FALSE(physics_softbody_project_shape_matching(nodes, 0.0));
	CHECK_FALSE(physics_softbody_project_shape_matching(nodes, 2.0));
	CHECK_FALSE(physics_softbody_project_shape_matching(nodes,
			std::numeric_limits<real_t>::infinity()));
	nodes[5].x.x = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(physics_softbody_project_shape_matching(nodes, real_t(0.5)));
	CHECK(nodes[0].x == original[0].x);
	CHECK(nodes[4].x == original[4].x);
	nodes[5] = original[5];
	nodes[2].im = -1;
	CHECK_FALSE(physics_softbody_project_shape_matching(nodes, real_t(0.5)));
	CHECK(nodes[0].x == original[0].x);
}

} // namespace TestPhysicsSoftBodyShapeMatching
