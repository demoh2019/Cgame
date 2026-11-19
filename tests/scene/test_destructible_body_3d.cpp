/**************************************************************************/
/*  test_destructible_body_3d.cpp                                         */
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

TEST_FORCE_LINK(test_destructible_body_3d)

#include "core/object/callable_mp.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/physics/destructible_body_3d.h"
#include "scene/3d/physics/static_body_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/box_shape_3d.h"
#include "scene/resources/3d/convex_polygon_shape_3d.h"
#include "scene/resources/mesh.h"
#include "servers/physics_3d/physics_server_3d.h"

namespace TestDestructibleBody3D {

class Listener : public Object {
public:
	int fractured = 0;
	int debris_count = 0;
	void on_fractured(const Array &p_debris) {
		fractured++;
		debris_count = p_debris.size();
	}
};

static DestructibleBody3D *make_body(const Vector3 &p_size, real_t p_mass) {
	DestructibleBody3D *body = memnew(DestructibleBody3D);
	body->set_mass(p_mass);
	CollisionShape3D *collider = memnew(CollisionShape3D);
	Ref<BoxShape3D> box;
	box.instantiate();
	box->set_size(p_size);
	collider->set_shape(box);
	body->add_child(collider);
	return body;
}

static real_t total_mass(const Array &p_debris) {
	real_t mass = 0.0;
	for (int i = 0; i < p_debris.size(); i++) {
		mass += Object::cast_to<RigidBody3D>(p_debris[i])->get_mass();
	}
	return mass;
}

static Vector3 total_momentum(const Array &p_debris) {
	Vector3 momentum;
	for (int i = 0; i < p_debris.size(); i++) {
		const RigidBody3D *piece = Object::cast_to<RigidBody3D>(p_debris[i]);
		momentum += piece->get_linear_velocity() * piece->get_mass();
	}
	return momentum;
}

TEST_CASE("[SceneTree][DestructibleBody3D] Fracturing keeps mass and momentum") {
	Node3D *parent = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(parent);
	DestructibleBody3D *body = make_body(Vector3(2, 1, 1), 10.0);
	body->set_piece_count(10);
	body->set_random_seed(42);
	body->set_scatter_speed(4.0);
	body->set_linear_velocity(Vector3(3, 0, 1));
	body->set_angular_velocity(Vector3(0, 2, 0));
	body->set_position(Vector3(5, 2, -3));
	parent->add_child(body);
	Listener listener;
	body->connect("fractured", callable_mp(&listener, &Listener::on_fractured));

	const Array debris = body->fracture(Vector3(6, 2, -3));
	CHECK(debris.size() >= 6);
	CHECK(debris.size() <= 10);
	CHECK(body->is_broken());
	CHECK(body->is_queued_for_deletion());
	CHECK(listener.fractured == 1);
	CHECK(listener.debris_count == debris.size());

	// The debris shares the mass of the original and carries its momentum, scatter and spin included.
	CHECK(total_mass(debris) == doctest::Approx(10.0).epsilon(0.001));
	const Vector3 momentum = total_momentum(debris);
	CHECK(momentum.is_equal_approx(Vector3(30, 0, 10)));

	for (int i = 0; i < debris.size(); i++) {
		RigidBody3D *piece = Object::cast_to<RigidBody3D>(debris[i]);
		REQUIRE(piece != nullptr);
		CHECK(piece->get_parent() == parent);
		CHECK(piece->get_mass() > 0.0);
		// Inside the original box: 2 x 1 x 1 around (5, 2, -3).
		const Vector3 position = piece->get_position();
		CHECK(Math::abs(position.x - 5.0) <= real_t(1.0) + real_t(1e-3));
		CHECK(Math::abs(position.y - 2.0) <= real_t(0.5) + real_t(1e-3));
		CHECK(Math::abs(position.z + 3.0) <= real_t(0.5) + real_t(1e-3));
		// A convex collision shape and a visible mesh with an outer and a cut surface.
		const CollisionShape3D *collider = Object::cast_to<CollisionShape3D>(piece->get_child(0));
		REQUIRE(collider != nullptr);
		const ConvexPolygonShape3D *shape = Object::cast_to<ConvexPolygonShape3D>(collider->get_shape().ptr());
		REQUIRE(shape != nullptr);
		CHECK(shape->get_points().size() >= 4);
		const MeshInstance3D *visual = Object::cast_to<MeshInstance3D>(piece->get_child(1));
		REQUIRE(visual != nullptr);
		REQUIRE(visual->get_mesh().is_valid());
		CHECK(visual->get_mesh()->get_surface_count() >= 1);
	}

	// A second break does nothing.
	CHECK(body->fracture(Vector3()).is_empty());
	CHECK(listener.fractured == 1);

	memdelete(parent);
}

TEST_CASE("[SceneTree][DestructibleBody3D] Extra impulse and scatter") {
	Node3D *parent = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(parent);
	DestructibleBody3D *body = make_body(Vector3(1, 1, 1), 4.0);
	body->set_piece_count(6);
	body->set_random_seed(7);
	body->set_scatter_speed(5.0);
	parent->add_child(body);

	// A blast impulse of 20 N*s on a 4 kg body adds 5 m/s to the momentum per kilogram.
	const Array debris = body->fracture(Vector3(0, 0, 0), Vector3(20, 0, 0));
	REQUIRE(debris.size() >= 3);
	CHECK(total_momentum(debris).is_equal_approx(Vector3(20, 0, 0)));

	// Pieces really fly apart: relative speeds exceed zero although the net momentum is the impulse.
	real_t fastest = 0.0;
	for (int i = 0; i < debris.size(); i++) {
		const RigidBody3D *piece = Object::cast_to<RigidBody3D>(debris[i]);
		fastest = MAX(fastest, (piece->get_linear_velocity() - Vector3(5, 0, 0)).length());
	}
	CHECK(fastest > real_t(0.5));

	memdelete(parent);
}

TEST_CASE("[SceneTree][DestructibleBody3D] Health, damage and missing shapes") {
	Node3D *parent = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(parent);
	DestructibleBody3D *body = make_body(Vector3(1, 1, 1), 2.0);
	body->set_health(10.0);
	body->set_piece_count(4);
	parent->add_child(body);

	body->apply_damage(4.0, Vector3());
	CHECK_FALSE(body->is_broken());
	CHECK(body->get_health() == doctest::Approx(6.0));
	body->apply_damage(-5.0, Vector3()); // Negative damage is ignored.
	CHECK(body->get_health() == doctest::Approx(6.0));
	body->apply_damage(7.0, Vector3());
	CHECK(body->is_broken());
	CHECK(body->get_health() == doctest::Approx(0.0));
	body->apply_damage(5.0, Vector3()); // Already broken.

	// Without health the damage does nothing.
	DestructibleBody3D *immortal = make_body(Vector3(1, 1, 1), 2.0);
	parent->add_child(immortal);
	immortal->apply_damage(1000.0, Vector3());
	CHECK_FALSE(immortal->is_broken());

	// A body without a box or convex shape cannot break and says so.
	DestructibleBody3D *shapeless = memnew(DestructibleBody3D);
	parent->add_child(shapeless);
	ERR_PRINT_OFF;
	CHECK(shapeless->fracture(Vector3()).is_empty());
	ERR_PRINT_ON;
	CHECK_FALSE(shapeless->is_broken());

	// Clamped settings.
	body->set_piece_count(1000);
	CHECK(body->get_piece_count() == 64);
	body->set_piece_count(0);
	CHECK(body->get_piece_count() == 2);

	memdelete(parent);
}

TEST_CASE("[SceneTree][DestructibleBody3D] Shards are made of the convex hull of a custom shape") {
	Node3D *parent = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(parent);
	DestructibleBody3D *body = memnew(DestructibleBody3D);
	body->set_mass(3.0);
	body->set_random_seed(9);
	body->set_piece_count(5);
	CollisionShape3D *collider = memnew(CollisionShape3D);
	Ref<ConvexPolygonShape3D> convex;
	convex.instantiate();
	Vector<Vector3> points;
	points.push_back(Vector3(-1, -1, -1));
	points.push_back(Vector3(1, -1, -1));
	points.push_back(Vector3(0, 1, -1));
	points.push_back(Vector3(0, 0, 1));
	convex->set_points(points);
	collider->set_shape(convex);
	body->add_child(collider);
	parent->add_child(body);

	const Array debris = body->fracture(Vector3(0, 0, 0));
	CHECK(debris.size() >= 3);
	CHECK(total_mass(debris) == doctest::Approx(3.0).epsilon(0.001));
	memdelete(parent);
}

static void simulate(int p_steps) {
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	for (int i = 0; i < p_steps; i++) {
		ps->step(1.0 / 60.0);
		ps->flush_queries();
		SceneTree::get_singleton()->physics_process(1.0 / 60.0);
		SceneTree::get_singleton()->process(1.0 / 60.0);
	}
}

TEST_CASE("[SceneTree][DestructibleBody3D] A hard enough impact breaks the body, a soft one does not") {
	Node3D *parent = memnew(Node3D);
	StaticBody3D *floor = memnew(StaticBody3D);
	CollisionShape3D *floor_collider = memnew(CollisionShape3D);
	Ref<BoxShape3D> floor_shape;
	floor_shape.instantiate();
	floor_shape->set_size(Vector3(50, 1, 50));
	floor_collider->set_shape(floor_shape);
	floor->add_child(floor_collider);
	floor->set_position(Vector3(0, -0.5, 0));
	parent->add_child(floor);

	// Dropped from 4 m a 5 kg box hits at about 8.9 m/s: an impulse of roughly 44 N*s.
	DestructibleBody3D *fragile = make_body(Vector3(1, 1, 1), 5.0);
	fragile->set_break_impulse(20.0);
	fragile->set_piece_count(8);
	fragile->set_position(Vector3(-5, 4, 0));
	parent->add_child(fragile);
	DestructibleBody3D *tough = make_body(Vector3(1, 1, 1), 5.0);
	tough->set_break_impulse(1000.0);
	tough->set_position(Vector3(5, 4, 0));
	parent->add_child(tough);
	SceneTree::get_singleton()->get_root()->add_child(parent);

	Listener listener;
	fragile->connect("fractured", callable_mp(&listener, &Listener::on_fractured));
	simulate(120);
	CHECK(listener.fractured == 1);
	CHECK(listener.debris_count >= 4);
	CHECK(fragile->is_broken());
	CHECK_FALSE(tough->is_broken());
	// The tough box lies on the floor, still in one piece.
	CHECK(tough->get_global_position().y < real_t(1.0));

	// Falling or resting alone never counts as an impact: gravity is subtracted.
	DestructibleBody3D *quiet = make_body(Vector3(1, 1, 1), 5.0);
	quiet->set_break_impulse(5.0);
	quiet->set_position(Vector3(0, 30, 0));
	parent->add_child(quiet);
	simulate(30); // Half a second of free fall.
	CHECK_FALSE(quiet->is_broken());

	memdelete(parent);
}

} // namespace TestDestructibleBody3D
