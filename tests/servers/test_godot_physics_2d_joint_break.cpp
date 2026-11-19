/**************************************************************************/
/*  test_godot_physics_2d_joint_break.cpp                                 */
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

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_2d_joint_break)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "core/object/callable_mp.h"
#include "servers/physics_2d/physics_server_2d.h"

namespace TestGodotPhysics2DJointBreak {

static int break_callbacks = 0;
static RID last_broken;

static void on_joint_broken(RID p_joint) {
	break_callbacks++;
	last_broken = p_joint;
}

struct Hanging {
	RID space;
	RID anchor;
	RID box;
	RID box_shape;
	RID joint;
};

// A 2 kg box hangs from a pin joint anchored to a static body. Gravity is 980 px/s^2.
static Hanging create_hanging_box(PhysicsServer2D *p_server) {
	Hanging h;
	h.space = p_server->space_create();
	p_server->space_set_active(h.space, true);
	p_server->area_set_param(h.space, PS2DE::AREA_PARAM_GRAVITY, 980.0);
	p_server->area_set_param(h.space, PS2DE::AREA_PARAM_GRAVITY_VECTOR, Vector2(0.0, 1.0));
	p_server->area_set_param(h.space, PS2DE::AREA_PARAM_LINEAR_DAMP, 0.0);
	p_server->area_set_param(h.space, PS2DE::AREA_PARAM_ANGULAR_DAMP, 0.0);
	p_server->space_set_param(h.space, PS2DE::SPACE_PARAM_BODY_TIME_TO_SLEEP, 1000.0);

	h.anchor = p_server->body_create();
	p_server->body_set_mode(h.anchor, PS2DE::BODY_MODE_STATIC);
	p_server->body_set_space(h.anchor, h.space);

	h.box_shape = p_server->rectangle_shape_create();
	p_server->shape_set_data(h.box_shape, Vector2(10.0, 10.0));
	h.box = p_server->body_create();
	p_server->body_set_mode(h.box, PS2DE::BODY_MODE_RIGID);
	p_server->body_add_shape(h.box, h.box_shape);
	p_server->body_set_param(h.box, PS2DE::BODY_PARAM_MASS, 2.0);
	p_server->body_set_state(h.box, PS2DE::BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.0, 50.0)));
	p_server->body_set_space(h.box, h.space);

	h.joint = p_server->joint_create();
	p_server->joint_make_pin(h.joint, Vector2(0.0, 0.0), h.anchor, h.box);
	return h;
}

static void free_hanging(PhysicsServer2D *p_server, const Hanging &p_h) {
	p_server->free_rid(p_h.joint);
	p_server->free_rid(p_h.box);
	p_server->free_rid(p_h.anchor);
	p_server->free_rid(p_h.box_shape);
	p_server->free_rid(p_h.space);
}

TEST_CASE("[SceneTree][GodotPhysics2D] Joint reaction force equals the supported weight") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);
	const Hanging h = create_hanging_box(server);

	// Before the first step there is nothing to report.
	CHECK(server->joint_get_reaction_force(h.joint) == Vector2());
	CHECK_FALSE(server->joint_is_broken(h.joint));

	for (int i = 0; i < 90; i++) {
		server->step(1.0 / 60.0);
	}
	const Vector2 force = server->joint_get_reaction_force(h.joint);
	// Weight is m * g = 2 * 980; the joint pushes the anchor down by that much.
	CHECK(force.x == doctest::Approx(0.0).epsilon(0.01));
	CHECK(Math::abs(force.y) == doctest::Approx(1960.0).epsilon(0.02));
	CHECK_FALSE(server->joint_is_broken(h.joint));

	free_hanging(server, h);
}

TEST_CASE("[SceneTree][GodotPhysics2D] Joint breaks above its force threshold and notifies once") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);
	const Hanging h = create_hanging_box(server);
	server->joint_disable_collisions_between_bodies(h.joint, true);

	break_callbacks = 0;
	server->joint_set_break_force(h.joint, 1000.0);
	CHECK(server->joint_get_break_force(h.joint) == doctest::Approx(1000.0));
	server->joint_set_break_callback(h.joint, callable_mp_static(&on_joint_broken));

	for (int i = 0; i < 30; i++) {
		server->step(1.0 / 60.0);
	}
	CHECK(server->joint_is_broken(h.joint));
	// The callback runs from flush_queries, not from the step.
	CHECK(break_callbacks == 0);
	server->flush_queries();
	CHECK(break_callbacks == 1);
	CHECK(last_broken == h.joint);
	server->flush_queries();
	CHECK(break_callbacks == 1);

	// The released box now free-falls instead of hanging.
	const real_t y_before = Transform2D(server->body_get_state(h.box, PS2DE::BODY_STATE_TRANSFORM)).get_origin().y;
	for (int i = 0; i < 30; i++) {
		server->step(1.0 / 60.0);
	}
	const real_t y_after = Transform2D(server->body_get_state(h.box, PS2DE::BODY_STATE_TRANSFORM)).get_origin().y;
	CHECK(y_after > y_before + 100.0);

	free_hanging(server, h);
}

TEST_CASE("[SceneTree][GodotPhysics2D] Joint below its break threshold keeps holding") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);
	const Hanging h = create_hanging_box(server);
	server->joint_set_break_force(h.joint, 5000.0);
	server->joint_set_break_torque(h.joint, 100000.0);

	for (int i = 0; i < 120; i++) {
		server->step(1.0 / 60.0);
	}
	CHECK_FALSE(server->joint_is_broken(h.joint));
	const real_t y = Transform2D(server->body_get_state(h.box, PS2DE::BODY_STATE_TRANSFORM)).get_origin().y;
	CHECK(y == doctest::Approx(50.0).epsilon(0.05));

	// Thresholds of zero make the joint unbreakable again.
	server->joint_set_break_force(h.joint, 0.0);
	server->joint_set_break_torque(h.joint, 0.0);
	CHECK(server->joint_get_break_force(h.joint) == doctest::Approx(0.0));

	free_hanging(server, h);
}

} // namespace TestGodotPhysics2DJointBreak

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
