/**************************************************************************/
/*  test_godot_physics_2d_solver.cpp                                      */
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

TEST_FORCE_LINK(test_godot_physics_2d_solver)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "core/config/project_settings.h"
#include "modules/godot_physics_2d/godot_body_2d.h"
#include "modules/godot_physics_2d/godot_constraint_2d.h"
#include "modules/godot_physics_2d/godot_physics_server_2d.h"
#include "servers/physics_2d/physics_server_2d.h"

namespace TestGodotPhysics2DSolver {

TEST_CASE("[GodotPhysics2D] Bias angular velocity clamp is symmetric") {
	GodotBody2D body;
	body.set_param(PS2DE::BODY_PARAM_INERTIA, 1.0);

	const real_t max_delta_av = 2.0;

	// An impulse at +Y pushing along +X yields negative angular velocity
	// (clockwise), the mirrored impulse yields positive angular velocity.
	body.apply_bias_impulse(Vector2(100.0, 0.0), Vector2(0.0, 1.0), max_delta_av);
	CHECK(body.get_biased_angular_velocity() == doctest::Approx(-max_delta_av));

	body.apply_bias_impulse(Vector2(-100.0, 0.0), Vector2(0.0, 1.0), max_delta_av);
	CHECK(body.get_biased_angular_velocity() == doctest::Approx(0.0));

	body.apply_bias_impulse(Vector2(-100.0, 0.0), Vector2(0.0, 1.0), max_delta_av);
	CHECK(body.get_biased_angular_velocity() == doctest::Approx(max_delta_av));

	// Small impulses are never clamped.
	body.apply_bias_impulse(Vector2(0.5, 0.0), Vector2(0.0, 1.0), max_delta_av);
	CHECK(body.get_biased_angular_velocity() == doctest::Approx(max_delta_av - 0.5));

	// A zero limit disables angular bias, a negative limit leaves it unclamped.
	body.apply_bias_impulse(Vector2(100.0, 0.0), Vector2(0.0, 1.0), 0.0);
	CHECK(body.get_biased_angular_velocity() == doctest::Approx(max_delta_av - 0.5));
	body.apply_bias_impulse(Vector2(100.0, 0.0), Vector2(0.0, 1.0), -1.0);
	CHECK(body.get_biased_angular_velocity() == doctest::Approx(max_delta_av - 100.5));
}

static RID create_space(PhysicsServer2D *p_server, real_t p_gravity) {
	RID space = p_server->space_create();
	p_server->space_set_active(space, true);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_GRAVITY, p_gravity);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_GRAVITY_VECTOR, Vector2(0.0, 1.0));
	p_server->area_set_param(space, PS2DE::AREA_PARAM_LINEAR_DAMP, 0.0);
	p_server->area_set_param(space, PS2DE::AREA_PARAM_ANGULAR_DAMP, 0.0);
	return space;
}

static RID create_body(PhysicsServer2D *p_server, RID p_space, RID p_shape, PS2DE::BodyMode p_mode, const Vector2 &p_position) {
	RID body = p_server->body_create();
	p_server->body_set_mode(body, p_mode);
	p_server->body_add_shape(body, p_shape);
	p_server->body_set_state(body, PS2DE::BODY_STATE_TRANSFORM, Transform2D(0.0, p_position));
	p_server->body_set_space(body, p_space);
	return body;
}

static int64_t collision_pairs(PhysicsServer2D *p_server) {
	return p_server->get_process_info(PS2DE::INFO_COLLISION_PAIRS);
}

TEST_CASE("[SceneTree][GodotPhysics2D] Pooled broadphase pairs survive heavy churn") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);

	const real_t step = 1.0 / 60.0;
	RID space = create_space(server, 0.0);

	RID circle = server->circle_shape_create();
	server->shape_set_data(circle, 6.0);

	// A dense overlapping grid creates far more body pairs than a single pool page.
	const int side = 24;
	Vector<RID> bodies;
	for (int y = 0; y < side; y++) {
		for (int x = 0; x < side; x++) {
			bodies.push_back(create_body(server, space, circle, PS2DE::BODY_MODE_RIGID, Vector2(x * 10.0, y * 10.0)));
		}
	}

	// One area overlapping everything creates area-body pairs, a second area an area-area pair.
	RID area_shape = server->rectangle_shape_create();
	server->shape_set_data(area_shape, Vector2(side * 10.0, side * 10.0));
	Vector<RID> areas;
	for (int i = 0; i < 2; i++) {
		RID area = server->area_create();
		server->area_add_shape(area, area_shape);
		server->area_set_monitorable(area, true);
		server->area_set_transform(area, Transform2D(0.0, Vector2(side * 5.0, side * 5.0)));
		server->area_set_space(area, space);
		areas.push_back(area);
	}

	server->step(step);
	const int64_t initial_pairs = collision_pairs(server);
	CHECK(initial_pairs > 1024);

	// The overlapping bodies push each other apart, creating and destroying pairs.
	for (int i = 0; i < 30; i++) {
		server->step(step);
	}
	CHECK(collision_pairs(server) > 0);

	// Remove every other body while pairs are alive, then keep stepping so that
	// freed pool slots are reused by new pairs.
	for (int i = 0; i < bodies.size(); i += 2) {
		server->free_rid(bodies[i]);
	}
	for (int i = 0; i < 10; i++) {
		server->step(step);
	}
	for (int i = 0; i < bodies.size(); i += 2) {
		bodies.write[i] = create_body(server, space, circle, PS2DE::BODY_MODE_RIGID, Vector2((i % side) * 10.0, (i / side) * 10.0));
	}
	server->step(step);
	CHECK(collision_pairs(server) > 0);

	for (const RID &body : bodies) {
		server->free_rid(body);
	}
	for (const RID &area : areas) {
		server->free_rid(area);
	}
	server->step(step);
	CHECK(collision_pairs(server) == 0);

	server->free_rid(area_shape);
	server->free_rid(circle);
	server->free_rid(space);
}

TEST_CASE("[SceneTree][GodotPhysics2D] Coulomb friction stops a sliding box at the analytic distance") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);

	const real_t step = 1.0 / 120.0;
	const real_t gravity = 980.0;
	const real_t friction = 0.5;
	const real_t initial_speed = 300.0;
	RID space = create_space(server, gravity);
	server->space_set_param(space, PS2DE::SPACE_PARAM_BODY_TIME_TO_SLEEP, 1000.0);

	RID floor_shape = server->rectangle_shape_create();
	server->shape_set_data(floor_shape, Vector2(5000.0, 20.0));
	RID floor = create_body(server, space, floor_shape, PS2DE::BODY_MODE_STATIC, Vector2(0.0, 20.0));
	server->body_set_param(floor, PS2DE::BODY_PARAM_FRICTION, friction);

	RID box_shape = server->rectangle_shape_create();
	server->shape_set_data(box_shape, Vector2(10.0, 10.0));
	RID box = create_body(server, space, box_shape, PS2DE::BODY_MODE_RIGID, Vector2(0.0, -10.0));
	server->body_set_param(box, PS2DE::BODY_PARAM_FRICTION, friction);
	server->body_set_param(box, PS2DE::BODY_PARAM_MASS, 1.0);

	// Settle on the floor before sliding.
	for (int i = 0; i < 30; i++) {
		server->step(step);
	}
	const Vector2 start = Transform2D(server->body_get_state(box, PS2DE::BODY_STATE_TRANSFORM)).get_origin();
	server->body_set_state(box, PS2DE::BODY_STATE_LINEAR_VELOCITY, Vector2(initial_speed, 0.0));

	for (int i = 0; i < 240; i++) {
		server->step(step);
	}

	const Vector2 end = Transform2D(server->body_get_state(box, PS2DE::BODY_STATE_TRANSFORM)).get_origin();
	const Vector2 velocity = server->body_get_state(box, PS2DE::BODY_STATE_LINEAR_VELOCITY);
	const real_t expected_distance = initial_speed * initial_speed / (2.0 * friction * gravity);

	CHECK(Math::abs(velocity.x) < 1.0);
	CHECK(end.x - start.x == doctest::Approx(expected_distance).epsilon(0.1));
	// The box keeps resting on the floor instead of sinking or bouncing.
	CHECK(Math::abs(end.y - start.y) < 1.0);

	server->free_rid(box);
	server->free_rid(floor);
	server->free_rid(box_shape);
	server->free_rid(floor_shape);
	server->free_rid(space);
}

static Vector<Vector2> simulate_pile(PhysicsServer2D *p_server, int p_side, int p_steps, real_t &r_floor_y, real_t &r_wall_x) {
	const real_t step = 1.0 / 60.0;
	const real_t radius = 5.0;
	const real_t spacing = 10.0;
	RID space = create_space(p_server, 980.0);
	p_server->space_set_param(space, PS2DE::SPACE_PARAM_BODY_TIME_TO_SLEEP, 1000.0);

	const real_t width = p_side * spacing;
	r_floor_y = 0.0;
	r_wall_x = width;

	RID wall_shape = p_server->rectangle_shape_create();
	p_server->shape_set_data(wall_shape, Vector2(width, width));
	RID walls = p_server->body_create();
	p_server->body_set_mode(walls, PS2DE::BODY_MODE_STATIC);
	p_server->body_add_shape(walls, wall_shape, Transform2D(0.0, Vector2(width * 0.5, width))); // Floor.
	p_server->body_add_shape(walls, wall_shape, Transform2D(0.0, Vector2(-width, -width * 0.5))); // Left wall.
	p_server->body_add_shape(walls, wall_shape, Transform2D(0.0, Vector2(width * 2.0, -width * 0.5))); // Right wall.
	p_server->body_set_space(walls, space);

	RID circle = p_server->circle_shape_create();
	p_server->shape_set_data(circle, radius);
	Vector<RID> bodies;
	for (int y = 0; y < p_side; y++) {
		for (int x = 0; x < p_side; x++) {
			// Slightly overlapping rows keep every body in a single contact island.
			const Vector2 position(radius + x * spacing + (y % 2) * 0.5, -radius - y * (spacing - 0.25));
			bodies.push_back(create_body(p_server, space, circle, PS2DE::BODY_MODE_RIGID, position));
		}
	}

	for (int i = 0; i < p_steps; i++) {
		p_server->step(step);
	}

	Vector<Vector2> positions;
	for (const RID &body : bodies) {
		positions.push_back(Transform2D(p_server->body_get_state(body, PS2DE::BODY_STATE_TRANSFORM)).get_origin());
		p_server->free_rid(body);
	}
	p_server->free_rid(walls);
	p_server->free_rid(circle);
	p_server->free_rid(wall_shape);
	p_server->free_rid(space);
	return positions;
}

TEST_CASE("[SceneTree][GodotPhysics2D] Large islands are solved in parallel deterministically") {
	PhysicsServer2D *server = PhysicsServer2D::get_singleton();
	REQUIRE(server != nullptr);

	// 40x40 bodies form one island with thousands of contacts, which is
	// solved through the graph-colored parallel path.
	const int side = 40;
	real_t floor_y = 0.0;
	real_t wall_x = 0.0;
	const Vector<Vector2> first = simulate_pile(server, side, 45, floor_y, wall_x);
	const Vector<Vector2> second = simulate_pile(server, side, 45, floor_y, wall_x);

	REQUIRE(first.size() == side * side);
	REQUIRE(second.size() == side * side);

	int mismatches = 0;
	int escaped = 0;
	for (int i = 0; i < first.size(); i++) {
		if (first[i] != second[i]) {
			mismatches++;
		}
		// Nothing tunnels through the floor or the walls of the container.
		if (first[i].y > floor_y || first[i].x < 0.0 || first[i].x > wall_x) {
			escaped++;
		}
	}
	CHECK(mismatches == 0);
	CHECK(escaped == 0);
}

TEST_CASE("[SceneTree][GodotPhysics2D] Broadphase pairing margin setting is registered with pixel-scale default") {
	REQUIRE(ProjectSettings::get_singleton()->has_setting("physics/2d/broadphase_pairing_margin"));
	CHECK(real_t(GLOBAL_GET("physics/2d/broadphase_pairing_margin")) == doctest::Approx(1.0));
}

class PairStub2D : public GodotConstraint2D {
	GodotBody2D *bodies[2] = { nullptr, nullptr };

public:
	virtual bool setup(real_t p_step) override { return false; }
	virtual bool pre_solve(real_t p_step) override { return false; }
	virtual void solve(real_t p_step) override {}

	PairStub2D(GodotBody2D *p_a, GodotBody2D *p_b) :
			GodotConstraint2D(bodies, 2) {
		bodies[0] = p_a;
		bodies[1] = p_b;
		p_a->add_constraint(this, 0);
		p_b->add_constraint(this, 1);
	}
	~PairStub2D() {
		bodies[0]->remove_constraint(this, 0);
		bodies[1]->remove_constraint(this, 1);
	}
};

TEST_CASE("[GodotPhysics2D] Body constraint slots survive removal in any order") {
	const int count = 257;
	GodotBody2D shared;
	LocalVector<GodotBody2D> others;
	others.resize(count);

	Vector<PairStub2D *> constraints;
	for (int i = 0; i < count; i++) {
		constraints.push_back(memnew(PairStub2D(&shared, &others[i])));
	}
	CHECK(shared.get_constraint_list().size() == uint32_t(count));

	// 37 is coprime with 257, so every constraint is removed once, in scrambled order.
	for (int i = 0; i < count; i++) {
		const int victim = (i * 37) % count;
		memdelete(constraints[victim]);
		constraints.write[victim] = nullptr;
		uint32_t alive = 0;
		for (PairStub2D *c : constraints) {
			if (!c) {
				continue;
			}
			alive++;
			REQUIRE(c->get_body_slot(0) < shared.get_constraint_list().size());
			CHECK(shared.get_constraint_list()[c->get_body_slot(0)].first == c);
		}
		CHECK(shared.get_constraint_list().size() == alive);
	}
	CHECK(shared.get_constraint_list().is_empty());
}

} // namespace TestGodotPhysics2DSolver

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
