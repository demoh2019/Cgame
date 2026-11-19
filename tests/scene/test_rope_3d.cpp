/**************************************************************************/
/*  test_rope_3d.cpp                                                      */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_rope_3d)

#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/3d/physics/static_body_3d.h"
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/rope_3d.h"
#include "scene/3d/rope_geometry.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/box_shape_3d.h"
#include "servers/physics_3d/physics_server_3d.h"

namespace TestRope3D {

using namespace RopeGeometry;

TEST_CASE("[Rope] Layout has equal segments and the requested arc length") {
	Vector<Vector3> points;
	// A rope of 12 m between two points 10 m apart sags to take up the slack.
	REQUIRE(layout_points(Vector3(0, 10, 0), Vector3(10, 10, 0), 12.0, 24, Vector3(0, -1, 0), points));
	REQUIRE(points.size() == 25);
	CHECK(points[0].is_equal_approx(Vector3(0, 10, 0)));
	CHECK(points[24].is_equal_approx(Vector3(10, 10, 0)));
	CHECK(polyline_length(points) == doctest::Approx(12.0).epsilon(0.01));
	for (int i = 1; i < points.size(); i++) {
		CHECK(points[i].distance_to(points[i - 1]) == doctest::Approx(0.5).epsilon(0.03));
	}
	// It hangs below the chord, deepest in the middle, symmetric around it.
	CHECK(points[12].y < real_t(10.0) - real_t(1.0));
	for (const Vector3 &point : points) {
		CHECK(point.y <= real_t(10.0) + real_t(1e-4));
	}
	CHECK(points[12].y <= points[6].y);
	CHECK(points[6].y == doctest::Approx(points[18].y).epsilon(0.01));
	CHECK(points[12].x == doctest::Approx(5.0).epsilon(0.01));
}

TEST_CASE("[Rope] Taut, folded and invalid layouts") {
	Vector<Vector3> points;
	// No slack: a straight line, with the length clamped to at least the distance.
	REQUIRE(layout_points(Vector3(), Vector3(6, 0, 8), 5.0, 10, Vector3(0, -1, 0), points));
	CHECK(polyline_length(points) == doctest::Approx(10.0).epsilon(0.001));
	for (int i = 0; i < points.size(); i++) {
		CHECK(points[i].is_equal_approx(Vector3(6, 0, 8) * (real_t(i) / real_t(10))));
	}
	// Same point twice with a length: hangs straight down.
	REQUIRE(layout_points(Vector3(1, 1, 1), Vector3(1, 1, 1), 4.0, 4, Vector3(0, -1, 0), points));
	CHECK(points[4].is_equal_approx(Vector3(1, -3, 1)));
	// A vertical chord with slack gets a sideways bulge instead of failing.
	REQUIRE(layout_points(Vector3(0, 10, 0), Vector3(0, 0, 0), 14.0, 14, Vector3(0, -1, 0), points));
	CHECK(polyline_length(points) == doctest::Approx(14.0).epsilon(0.01));
	for (const Vector3 &point : points) {
		CHECK(point.is_finite());
	}
	// Invalid input.
	CHECK_FALSE(layout_points(Vector3(), Vector3(1, 0, 0), 2.0, 0, Vector3(0, -1, 0), points));
	CHECK_FALSE(layout_points(Vector3(), Vector3(1, 0, 0), -1.0, 4, Vector3(0, -1, 0), points));
	CHECK_FALSE(layout_points(Vector3(Math::NaN, 0, 0), Vector3(1, 0, 0), 2.0, 4, Vector3(0, -1, 0), points));
	CHECK(points.is_empty());
}

TEST_CASE("[Rope] Tube mesh is closed, outward facing and does not twist") {
	Vector<Vector3> points;
	REQUIRE(layout_points(Vector3(0, 5, 0), Vector3(8, 5, 0), 9.0, 16, Vector3(0, -1, 0), points));
	TubeMesh tube;
	REQUIRE(build_tube(points, 0.1, 6, 0.4, tube));
	const int rings = 17;
	CHECK(tube.vertices.size() == rings * 7 + 2);
	CHECK(tube.indices.size() == 16 * 6 * 6 + 2 * 6 * 3);
	CHECK(tube.normals.size() == tube.vertices.size());
	CHECK(tube.uvs.size() == tube.vertices.size());
	for (int index : tube.indices) {
		CHECK(index >= 0);
		CHECK(index < tube.vertices.size());
	}
	// Every ring vertex sits at the radius from the rope's center line, its normal points outward.
	for (int i = 0; i < rings; i++) {
		for (int k = 0; k <= 6; k++) {
			const int v = i * 7 + k;
			CHECK((tube.vertices[v] - points[i]).length() == doctest::Approx(0.1).epsilon(0.001));
			CHECK(tube.normals[v].dot(tube.vertices[v] - points[i]) > 0.0);
			CHECK(tube.normals[v].length() == doctest::Approx(1.0));
		}
	}
	// Godot front faces are clockwise from outside: (p2 - p0) x (p1 - p0) faces away from the axis.
	const int side_triangles = 16 * 6 * 2;
	for (int t = 0; t < tube.indices.size() / 3; t++) {
		const Vector3 p0 = tube.vertices[tube.indices[t * 3]];
		const Vector3 p1 = tube.vertices[tube.indices[t * 3 + 1]];
		const Vector3 p2 = tube.vertices[tube.indices[t * 3 + 2]];
		const Vector3 face = (p2 - p0).cross(p1 - p0);
		const Vector3 middle = (p0 + p1 + p2) / 3.0;
		if (t < side_triangles) {
			// Outward from the nearest center line point.
			real_t best = Math::INF;
			Vector3 away;
			for (const Vector3 &center : points) {
				if (middle.distance_to(center) < best) {
					best = middle.distance_to(center);
					away = middle - center;
				}
			}
			CHECK(face.dot(away) > 0.0);
		} else if (t < side_triangles + 6) {
			CHECK(face.x < 0.0); // Start cap faces back along the rope (-x here).
		} else {
			CHECK(face.x > 0.0); // End cap faces forward.
		}
	}
	// No twisting: rings of consecutive points stay aligned (the first vertex stays near the first).
	for (int i = 1; i < rings; i++) {
		CHECK((tube.vertices[i * 7] - points[i]).normalized().dot((tube.vertices[(i - 1) * 7] - points[i - 1]).normalized()) > 0.9);
	}
	// v runs along the rope.
	CHECK(tube.uvs[0].y == doctest::Approx(0.0));
	CHECK(tube.uvs[(rings - 1) * 7].y > tube.uvs[7].y);

	CHECK_FALSE(build_tube(Vector<Vector3>(), 0.1, 6, 0.4, tube));
	CHECK_FALSE(build_tube(points, 0.0, 6, 0.4, tube));
	CHECK_FALSE(build_tube(points, 0.1, 2, 0.4, tube));
	// Coincident points do not produce NaNs.
	Vector<Vector3> repeated;
	repeated.push_back(Vector3(1, 1, 1));
	repeated.push_back(Vector3(1, 1, 1));
	repeated.push_back(Vector3(1, 2, 1));
	REQUIRE(build_tube(repeated, 0.1, 6, 0.4, tube));
	for (const Vector3 &vertex : tube.vertices) {
		CHECK(vertex.is_finite());
	}
}

// Runs the physics for a while. The rope is made of ordinary rigid bodies, so the server must step
// and flush for their nodes to follow it.
static void simulate(int p_steps) {
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	for (int i = 0; i < p_steps; i++) {
		ps->step(1.0 / 60.0);
		ps->flush_queries();
		SceneTree::get_singleton()->process(1.0 / 60.0);
	}
}

TEST_CASE("[SceneTree][Rope3D] A rope hangs from its pinned start and keeps its length") {
	Rope3D *rope = memnew(Rope3D);
	rope->set_segments(10);
	rope->set_end_point(Vector3(0, -4, 0));
	rope->set_pin_start(true);
	rope->set_mass(2.0);
	SceneTree::get_singleton()->get_root()->add_child(rope);
	rope->set_global_position(Vector3(0, 10, 0));
	rope->rebuild();
	REQUIRE(rope->get_segment_count() == 10);
	CHECK(rope->get_current_length() == doctest::Approx(4.0).epsilon(0.02));

	simulate(180);
	const PackedVector3Array points = rope->get_points();
	REQUIRE(points.size() == 11);
	// The start stays at the pin; the rope hangs straight down under gravity.
	CHECK(points[0].distance_to(Vector3(0, 10, 0)) < real_t(0.15));
	CHECK(points[10].y < real_t(7.0));
	CHECK(points[10].y > real_t(5.2));
	CHECK(Vector2(points[10].x, points[10].z).length() < real_t(1.0));
	// Joints are soft: a hanging rope may stretch, but not wildly.
	CHECK(rope->get_current_length() < real_t(4.0) * real_t(1.35));
	CHECK(rope->get_current_length() > real_t(3.8));
	CHECK_FALSE(rope->is_broken());

	memdelete(rope);
}

TEST_CASE("[SceneTree][Rope3D] A rope with slack sags between two pins and carries a weight") {
	StaticBody3D *anchor = memnew(StaticBody3D);
	SceneTree::get_singleton()->get_root()->add_child(anchor);
	anchor->set_global_position(Vector3(10, 10, 0));

	Rope3D *rope = memnew(Rope3D);
	rope->set_segments(16);
	rope->set_end_point(Vector3(10, 0, 0));
	rope->set_length(11.0);
	rope->set_pin_start(true);
	rope->set_pin_end(true);
	SceneTree::get_singleton()->get_root()->add_child(rope);
	rope->set_global_position(Vector3(0, 10, 0));
	rope->rebuild();

	simulate(240);
	const PackedVector3Array points = rope->get_points();
	// Both ends hold; the middle hangs below them.
	CHECK(points[0].distance_to(Vector3(0, 10, 0)) < real_t(0.3));
	CHECK(points[16].distance_to(Vector3(10, 10, 0)) < real_t(0.3));
	CHECK(points[8].y < real_t(9.0));
	CHECK(points[8].x == doctest::Approx(5.0).epsilon(0.15));
	CHECK(rope->get_current_length() < real_t(11.0) * real_t(1.2));

	memdelete(rope);
	memdelete(anchor);
}

TEST_CASE("[SceneTree][Rope3D] A rope attached to a body holds it") {
	RigidBody3D *weight = memnew(RigidBody3D);
	weight->set_mass(5.0);
	CollisionShape3D *collider = memnew(CollisionShape3D);
	Ref<BoxShape3D> box;
	box.instantiate();
	box->set_size(Vector3(1, 1, 1));
	collider->set_shape(box);
	weight->add_child(collider);
	// Position bodies before they enter the tree, so the physics server creates them there.
	weight->set_position(Vector3(0, 5.5, 0));
	SceneTree::get_singleton()->get_root()->add_child(weight);

	Rope3D *rope = memnew(Rope3D);
	rope->set_segments(8);
	rope->set_end_point(Vector3(0, -4.5, 0));
	rope->set_pin_start(true);
	rope->set_solver_priority(6);
	SceneTree::get_singleton()->get_root()->add_child(rope);
	rope->set_global_position(Vector3(0, 10, 0));
	rope->set_node_b(rope->get_path_to(weight)); // Paths need both nodes in the tree.
	rope->rebuild();

	simulate(240);
	// The weight hangs at the end of the rope instead of falling: its height stays near 5.5, far
	// above where free fall would have put it after four seconds.
	CHECK(weight->get_global_position().y > real_t(4.0));
	CHECK(weight->get_global_position().y < real_t(6.5));
	CHECK(Vector2(weight->get_global_position().x, weight->get_global_position().z).length() < real_t(1.0));

	memdelete(rope);
	memdelete(weight);
}

TEST_CASE("[SceneTree][Rope3D] Rebuilding and invalid settings") {
	Rope3D *rope = memnew(Rope3D);
	CHECK(rope->get_segments() == 12);
	rope->set_segments(5000);
	CHECK(rope->get_segments() == 256);
	rope->set_segments(0);
	CHECK(rope->get_segments() == 1);
	rope->set_radius(-1.0);
	CHECK(rope->get_radius() > 0.0);
	rope->set_segments(6);
	SceneTree::get_singleton()->get_root()->add_child(rope);
	rope->set_global_position(Vector3(0, 20, 0));
	rope->rebuild();
	CHECK(rope->get_segment_count() == 6);
	rope->set_segments(9);
	rope->rebuild();
	CHECK(rope->get_segment_count() == 9); // Old segments are freed, new ones created.
	CHECK(rope->get_points().size() == 10);

	// A rope of zero extent and no length builds nothing, without errors.
	rope->set_end_point(Vector3());
	rope->set_length(0.0);
	rope->rebuild();
	CHECK(rope->get_segment_count() == 0);
	CHECK(rope->get_points().is_empty());
	CHECK(rope->get_current_length() == doctest::Approx(0.0));
	CHECK(rope->get_start_tension() == doctest::Approx(0.0));

	memdelete(rope);
}

} // namespace TestRope3D
