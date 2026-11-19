/**************************************************************************/
/*  test_godot_physics_2d_body_limits.cpp                                 */
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

TEST_FORCE_LINK(test_godot_physics_2d_body_limits)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "servers/physics_2d/physics_server_2d.h"

namespace TestGodotPhysics2DBodyLimits {

static RID make_space(PhysicsServer2D *p_server, real_t p_gravity) {
	RID space = p_server->space_create();
	p_server->space_set_active(space, true);
	p_server->space_set_param(space, PS2DE::SPACE_PARAM_BODY_TIME_TO_SLEEP, 1000.0);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_GRAVITY, p_gravity);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_GRAVITY_VECTOR, Vector2(0.0, 1.0));
	p_server->area_set_param(space, PS2DE::AREA_PARAM_LINEAR_DAMP, 0.0);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_ANGULAR_DAMP, 0.0);
	return space;
}

static RID make_box(PhysicsServer2D *p_server, RID p_space, RID p_shape, const Vector2 &p_position) {
	RID body = p_server->body_create();
	p_server->body_set_mode(body, PS2DE::BODY_MODE_RIGID);
	p_server->body_add_shape(body, p_shape);
	p_server->body_set_state(body, PS2DE::BODY_STATE_TRANSFORM, Transform2D(0.0, p_position));
	p_server->body_set_space(body, p_space);
	return body;
}

TEST_CASE("[SceneTree][GodotPhysics2D] Per-body speed limits override and fall back to the project setting") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);

	RID space = make_space(server, 980.0);
	RID shape = server->rectangle_shape_create();
	server->shape_set_data(shape, Vector2(5.0, 5.0));
	RID limited = make_box(server, space, shape, Vector2(0.0, 0.0));
	RID free_body = make_box(server, space, shape, Vector2(100.0, 0.0));
	RID spinner = make_box(server, space, shape, Vector2(200.0, 0.0));

	CHECK(server->body_get_max_linear_velocity(limited) == doctest::Approx(0.0));
	server->body_set_max_linear_velocity(limited, 120.0);
	CHECK(server->body_get_max_linear_velocity(limited) == doctest::Approx(120.0));
	server->body_set_max_angular_velocity(spinner, 2.0);
	server->body_set_state(spinner, PS2DE::BODY_STATE_ANGULAR_VELOCITY, 50.0);
	server->body_set_state(limited, PS2DE::BODY_STATE_LINEAR_VELOCITY, Vector2(1000.0, 0.0));

	real_t limited_max = 0.0;
	real_t free_max = 0.0;
	real_t spin_max = 0.0;
	for (int i = 0; i < 90; i++) {
		server->step(1.0 / 60.0);
		limited_max = MAX(limited_max, Vector2(server->body_get_state(limited, PS2DE::BODY_STATE_LINEAR_VELOCITY)).length());
		free_max = MAX(free_max, Vector2(server->body_get_state(free_body, PS2DE::BODY_STATE_LINEAR_VELOCITY)).length());
		spin_max = MAX(spin_max, Math::abs(real_t(server->body_get_state(spinner, PS2DE::BODY_STATE_ANGULAR_VELOCITY))));
	}
	CHECK(limited_max <= real_t(120.0) * real_t(1.001));
	CHECK(limited_max > real_t(100.0)); // It actually reaches its cap while falling.
	CHECK(free_max > real_t(1000.0)); // The unlimited body keeps accelerating.
	CHECK(spin_max <= real_t(2.0) * real_t(1.001));

	// Setting the limit back to zero removes the cap again.
	server->body_set_max_linear_velocity(limited, 0.0);
	server->body_set_state(limited, PS2DE::BODY_STATE_LINEAR_VELOCITY, Vector2(1000.0, 0.0));
	server->step(1.0 / 60.0);
	CHECK(Vector2(server->body_get_state(limited, PS2DE::BODY_STATE_LINEAR_VELOCITY)).length() > real_t(500.0));

	server->free_rid(spinner);
	server->free_rid(free_body);
	server->free_rid(limited);
	server->free_rid(shape);
	server->free_rid(space);
}

// Two heavily overlapping boxes (no gravity): returns the largest speed one box reaches while
// being pushed out.
static real_t peak_pushout_speed(PhysicsServer2D *p_server, real_t p_limit) {
	RID space = make_space(p_server, 0.0);
	RID shape = p_server->rectangle_shape_create();
	p_server->shape_set_data(shape, Vector2(10.0, 10.0));
	RID a = make_box(p_server, space, shape, Vector2(0.0, 0.0));
	RID b = make_box(p_server, space, shape, Vector2(5.0, 0.0)); // Overlaps by 15 px.
	p_server->body_set_max_depenetration_velocity(b, p_limit);

	// Penetration recovery moves bodies through a separate bias velocity, so measure the real
	// displacement per step rather than linear_velocity.
	real_t peak = 0.0;
	real_t previous_x = Transform2D(p_server->body_get_state(b, PS2DE::BODY_STATE_TRANSFORM)).get_origin().x;
	for (int i = 0; i < 30; i++) {
		p_server->step(1.0 / 60.0);
		const real_t x = Transform2D(p_server->body_get_state(b, PS2DE::BODY_STATE_TRANSFORM)).get_origin().x;
		peak = MAX(peak, Math::abs(x - previous_x) * real_t(60.0));
		previous_x = x;
	}
	const real_t separation = Transform2D(p_server->body_get_state(b, PS2DE::BODY_STATE_TRANSFORM)).get_origin().x - Transform2D(p_server->body_get_state(a, PS2DE::BODY_STATE_TRANSFORM)).get_origin().x;
	// Whatever the limit, the boxes must eventually separate.
	MESSAGE("limit=", p_limit, " peak=", peak, " separation after 0.5s=", separation);

	p_server->free_rid(b);
	p_server->free_rid(a);
	p_server->free_rid(shape);
	p_server->free_rid(space);
	return peak;
}

TEST_CASE("[SceneTree][GodotPhysics2D] Max depenetration velocity limits how fast embedded bodies are pushed apart") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);

	const real_t unlimited = peak_pushout_speed(server, 0.0);
	const real_t limited = peak_pushout_speed(server, 40.0);
	CHECK(unlimited > real_t(100.0));
	CHECK(limited < unlimited * real_t(0.5));
	// The limit bounds the correction velocity; a small allowance covers ordinary contact velocity.
	CHECK(limited < real_t(60.0));
}

} // namespace TestGodotPhysics2DBodyLimits

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
