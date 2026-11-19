/**************************************************************************/
/*  test_godot_physics_2d_solver_priority.cpp                             */
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

TEST_FORCE_LINK(test_godot_physics_2d_solver_priority)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "servers/physics_2d/physics_server_2d.h"

namespace TestGodotPhysics2DSolverPriority {

// Stacks `height` boxes (20 px) on a floor with a low solver iteration count and returns how far
// the top box ended up below its ideal rest height, i.e. how much the stack compressed.
static real_t stack_sag(PhysicsServer2D *p_server, int p_height, int p_priority) {
	RID space = p_server->space_create();
	p_server->space_set_active(space, true);
	p_server->space_set_param(space, PS2DE::SPACE_PARAM_SOLVER_ITERATIONS, 8);
	p_server->space_set_param(space, PS2DE::SPACE_PARAM_BODY_TIME_TO_SLEEP, 1000.0);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_GRAVITY, 980.0);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_GRAVITY_VECTOR, Vector2(0.0, 1.0));
	p_server->area_set_param(space, PS2DE::AREA_PARAM_LINEAR_DAMP, 0.0);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_ANGULAR_DAMP, 0.0);

	RID floor_shape = p_server->rectangle_shape_create();
	p_server->shape_set_data(floor_shape, Vector2(500.0, 10.0));
	RID floor = p_server->body_create();
	p_server->body_set_mode(floor, PS2DE::BODY_MODE_STATIC);
	p_server->body_add_shape(floor, floor_shape);
	p_server->body_set_state(floor, PS2DE::BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.0, 10.0)));
	p_server->body_set_space(floor, space);

	RID box_shape = p_server->rectangle_shape_create();
	p_server->shape_set_data(box_shape, Vector2(10.0, 10.0));
	Vector<RID> boxes;
	for (int i = 0; i < p_height; i++) {
		RID box = p_server->body_create();
		p_server->body_set_mode(box, PS2DE::BODY_MODE_RIGID);
		p_server->body_add_shape(box, box_shape);
		p_server->body_set_param(box, PS2DE::BODY_PARAM_MASS, 1.0);
		p_server->body_set_param(box, PS2DE::BODY_PARAM_BOUNCE, 0.0);
		p_server->body_set_solver_priority(box, p_priority);
		// Rest height of box i is -10 - 20 * i (y points down, floor top is at y = 0).
		p_server->body_set_state(box, PS2DE::BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(0.0, -10.0 - 20.0 * i)));
		p_server->body_set_space(box, space);
		boxes.push_back(box);
	}

	for (int step = 0; step < 240; step++) {
		p_server->step(1.0 / 60.0);
	}
	const real_t top_y = Transform2D(p_server->body_get_state(boxes[p_height - 1], PS2DE::BODY_STATE_TRANSFORM)).get_origin().y;
	const real_t ideal_y = -10.0 - 20.0 * (p_height - 1);
	const real_t sag = top_y - ideal_y; // positive: compressed toward the floor

	for (const RID &box : boxes) {
		p_server->free_rid(box);
	}
	p_server->free_rid(floor);
	p_server->free_rid(box_shape);
	p_server->free_rid(floor_shape);
	p_server->free_rid(space);
	return sag;
}

TEST_CASE("[SceneTree][GodotPhysics2D] Body solver priority stiffens contacts") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);

	const real_t sag_default = stack_sag(server, 10, 1);
	const real_t sag_priority = stack_sag(server, 10, 8);
	MESSAGE("sag default=", sag_default, " priority8=", sag_priority);

	// A ten box stack needs far more than 8 iterations to stay up. Eight times the iterations on
	// the same contacts (64 solves) keeps it standing, and priority can never make it worse.
	CHECK(sag_priority < real_t(10.0));
	CHECK(sag_priority <= sag_default);
	// The default priority is untouched by the feature: results stay deterministic.
	CHECK(stack_sag(server, 10, 1) == doctest::Approx(sag_default));
}

TEST_CASE("[SceneTree][GodotPhysics2D] Body solver priority is clamped and readable") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);
	RID body = server->body_create();
	CHECK(server->body_get_solver_priority(body) == 1);
	server->body_set_solver_priority(body, 5);
	CHECK(server->body_get_solver_priority(body) == 5);
	server->body_set_solver_priority(body, 100);
	CHECK(server->body_get_solver_priority(body) == 8);
	server->body_set_solver_priority(body, -3);
	CHECK(server->body_get_solver_priority(body) == 1);
	server->free_rid(body);
}

} // namespace TestGodotPhysics2DSolverPriority

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
