/**************************************************************************/
/*  test_vehicle_drivetrain.cpp                                           */
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

TEST_FORCE_LINK(test_vehicle_drivetrain)

#include "core/object/callable_mp.h"

#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/physics/drivetrain_model.h"
#include "scene/3d/physics/static_body_3d.h"
#include "scene/3d/physics/vehicle_body_3d.h"
#include "scene/3d/physics/vehicle_drivetrain_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/box_shape_3d.h"
#include "servers/physics_3d/physics_server_3d.h"

namespace TestVehicleDrivetrain {

using namespace DrivetrainModel;

TEST_CASE("[Drivetrain] Torque curve, ratios and engine speed") {
	Config config;
	// The built-in curve peaks in the middle of the range and never drops below 0.6.
	CHECK(torque_multiplier(config, 0.5) == doctest::Approx(1.0));
	CHECK(torque_multiplier(config, 0.0) == doctest::Approx(0.6));
	CHECK(torque_multiplier(config, 1.0) == doctest::Approx(0.6));
	CHECK(torque_multiplier(config, -3.0) == doctest::Approx(0.6)); // Clamped.
	// A custom curve is interpolated evenly over 0..max_rpm.
	config.torque_curve.push_back(0.0);
	config.torque_curve.push_back(1.0);
	config.torque_curve.push_back(0.5);
	CHECK(torque_multiplier(config, 0.0) == doctest::Approx(0.0));
	CHECK(torque_multiplier(config, 0.25) == doctest::Approx(0.5));
	CHECK(torque_multiplier(config, 0.5) == doctest::Approx(1.0));
	CHECK(torque_multiplier(config, 1.0) == doctest::Approx(0.5));

	config = Config();
	CHECK(total_ratio(config, 1) == doctest::Approx(3.6 * 3.7));
	CHECK(total_ratio(config, 5) == doctest::Approx(0.85 * 3.7));
	CHECK(total_ratio(config, 99) == doctest::Approx(0.85 * 3.7)); // Clamped to the last gear.
	CHECK(total_ratio(config, -1) == doctest::Approx(3.2 * 3.7));
	CHECK(total_ratio(config, 0) == doctest::Approx(0.0));
}

TEST_CASE("[Drivetrain] Launch torque is strongest in first gear and flows to the wheels") {
	Config config;
	State state;
	state.gear = 1;
	const Output launch = step(config, state, 1.0, 0.0, false, false, 0.016);
	// At a standstill the clutch slips at launch_rpm: full torque of that rpm.
	const real_t expected_engine = config.peak_torque * torque_multiplier(config, config.launch_rpm / config.max_rpm);
	CHECK(launch.engine_torque == doctest::Approx(expected_engine));
	CHECK(launch.wheel_torque == doctest::Approx(expected_engine * 3.6 * 3.7 * 0.9));
	CHECK(launch.engine_rpm == doctest::Approx(config.idle_rpm));

	// No throttle, no wheel speed: nothing happens.
	const Output idle = step(config, state, 0.0, 0.0, false, false, 0.016);
	CHECK(idle.wheel_torque == doctest::Approx(0.0));

	// Higher gears give less wheel torque for the same engine torque.
	State second;
	second.gear = 2;
	const Output in_second = step(config, second, 1.0, 0.0, false, false, 0.016);
	CHECK(in_second.wheel_torque < launch.wheel_torque);
	CHECK(in_second.wheel_torque > 0.0);

	// Throttle is clamped to 0..1.
	State clamped;
	clamped.gear = 1;
	const Output over = step(config, clamped, 5.0, 0.0, false, false, 0.016);
	CHECK(over.engine_torque == doctest::Approx(launch.engine_torque));
}

TEST_CASE("[Drivetrain] Engine speed follows the wheels and the rev limiter cuts the torque") {
	Config config;
	State state;
	state.gear = 3; // Ratio 1.5 * 3.7 = 5.55.
	const Output cruising = step(config, state, 0.5, 600.0, false, false, 0.016);
	CHECK(cruising.engine_rpm == doctest::Approx(600.0 * 1.5 * 3.7).epsilon(0.001));
	CHECK(cruising.engine_torque > 0.0);

	// Past the limit, no drive torque even at full throttle.
	const Output limited = step(config, state, 1.0, 6500.0 / 5.55 + 50.0, false, false, 0.016);
	CHECK(limited.engine_rpm >= config.max_rpm);
	CHECK(limited.wheel_torque == doctest::Approx(0.0));

	// Idle is a floor for the engine speed.
	State slow;
	slow.gear = 5;
	CHECK(step(config, slow, 0.0, 10.0, false, false, 0.016).engine_rpm == doctest::Approx(config.idle_rpm));
}

TEST_CASE("[Drivetrain] Automatic gearbox shifts up with hysteresis and cuts torque while shifting") {
	Config config;
	State state;
	state.gear = 1;
	// Spin the wheels up to the upshift rpm of first gear: 5500 / 13.32 = 413 rpm.
	const real_t wheel_rpm = config.shift_up_rpm / (3.6 * 3.7) + 5.0;
	const Output shifting = step(config, state, 1.0, wheel_rpm, true, false, 0.016);
	CHECK(shifting.shifted);
	CHECK(state.gear == 2);
	CHECK(shifting.wheel_torque == doctest::Approx(0.0)); // The clutch is open during the shift.
	CHECK(state.shift_timer > 0.0);

	// After the shift time the torque flows again, in the new gear's ratio.
	real_t torque = 0.0;
	for (int i = 0; i < 30 && torque == 0.0; i++) {
		torque = step(config, state, 1.0, wheel_rpm, true, false, 0.016).wheel_torque;
	}
	CHECK(torque > 0.0);
	CHECK(state.gear == 2);

	// A gear never shifts up again right after: the engine rpm fell (hysteresis from the lower rpm).
	for (int i = 0; i < 20; i++) {
		step(config, state, 1.0, wheel_rpm, true, false, 0.016);
	}
	CHECK(state.gear == 2);

	// Slowing down far enough shifts back down, but not so far that it would immediately shift up again.
	State coast;
	coast.gear = 4;
	for (int i = 0; i < 40; i++) {
		step(config, coast, 0.0, 120.0, true, false, 0.016); // Engine rpm in 4th: 120 * 1.1 * 3.7 = 488 < idle.
	}
	CHECK(coast.gear < 4);
	CHECK(coast.gear >= 1);

	// Manual mode never shifts on its own.
	State manual;
	manual.gear = 1;
	step(config, manual, 1.0, wheel_rpm * 3.0, false, false, 0.016);
	CHECK(manual.gear == 1);
}

TEST_CASE("[Drivetrain] Reverse only engages when nearly stopped; engine braking opposes the motion") {
	Config config;
	State state;
	state.gear = 3;
	// Moving forward fast: reverse request is ignored.
	step(config, state, 1.0, 400.0, false, true, 0.016);
	CHECK(state.gear == 3);
	// Almost stopped: it engages after the shift.
	State stopped;
	stopped.gear = 1;
	step(config, stopped, 0.0, 5.0, false, true, 0.016);
	CHECK(stopped.gear == -1);
	Output backing;
	for (int i = 0; i < 30; i++) {
		backing = step(config, stopped, 1.0, 0.0, false, true, 0.016);
	}
	CHECK(backing.wheel_torque < 0.0); // Pushes the car backward.
	// Releasing the request goes back to first once stopped.
	step(config, stopped, 0.0, 0.0, false, false, 0.016);
	CHECK(stopped.gear == 1);

	// Throttle released: braking torque against the direction of travel, forward or backward.
	State rolling;
	rolling.gear = 3;
	CHECK(step(config, rolling, 0.0, 300.0, false, false, 0.016).wheel_torque < 0.0);
	State rolling_back;
	rolling_back.gear = 3;
	CHECK(step(config, rolling_back, 0.0, -300.0, false, false, 0.016).wheel_torque > 0.0);
	// No engine braking when standing still.
	State parked;
	parked.gear = 1;
	CHECK(step(config, parked, 0.0, 0.0, false, false, 0.016).wheel_torque == doctest::Approx(0.0));

	// Neutral transmits nothing.
	State neutral;
	neutral.gear = 0;
	CHECK(step(config, neutral, 1.0, 100.0, false, false, 0.016).wheel_torque == doctest::Approx(0.0));
}

static VehicleBody3D *make_car(Node3D *p_parent, VehicleDrivetrain3D **r_drivetrain) {
	StaticBody3D *road = memnew(StaticBody3D);
	CollisionShape3D *road_collider = memnew(CollisionShape3D);
	Ref<BoxShape3D> road_shape;
	road_shape.instantiate();
	road_shape->set_size(Vector3(20000, 1, 40));
	road_collider->set_shape(road_shape);
	road->add_child(road_collider);
	road->set_position(Vector3(0, -0.5, 0));
	p_parent->add_child(road);

	VehicleBody3D *car = memnew(VehicleBody3D);
	car->set_mass(1000.0);
	// The default damping would cap the speed below the shift points of a modest engine.
	car->set_linear_damp_mode(RigidBody3D::DAMP_MODE_REPLACE);
	car->set_linear_damp(0.02);
	CollisionShape3D *body_collider = memnew(CollisionShape3D);
	Ref<BoxShape3D> body_shape;
	body_shape.instantiate();
	body_shape->set_size(Vector3(1.6, 0.5, 3.6));
	body_collider->set_shape(body_shape);
	body_collider->set_position(Vector3(0, 0.5, 0));
	car->add_child(body_collider);
	for (int i = 0; i < 4; i++) {
		VehicleWheel3D *wheel = memnew(VehicleWheel3D);
		wheel->set_position(Vector3((i & 1) ? 0.8 : -0.8, 0.4, (i & 2) ? 1.3 : -1.3));
		wheel->set_radius(0.35);
		wheel->set_use_as_traction(i >= 2); // Rear wheel drive.
		wheel->set_use_as_steering(i < 2);
		wheel->set_suspension_travel(0.3);
		wheel->set_suspension_stiffness(40.0);
		wheel->set_friction_slip(3.0);
		wheel->set_suspension_rest_length(0.3);
		car->add_child(wheel);
	}
	VehicleDrivetrain3D *drivetrain = memnew(VehicleDrivetrain3D);
	car->add_child(drivetrain);
	*r_drivetrain = drivetrain;
	// The road is long in both directions, so it does not matter which way the car faces.
	car->set_rotation(Vector3(0, Math::PI * 0.5 * -1.0, 0));
	car->set_position(Vector3(0, 0.8, 0));
	p_parent->add_child(car);
	return car;
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

TEST_CASE("[SceneTree][VehicleDrivetrain3D] A car accelerates through the gears and is limited by the rev limiter") {
	Node3D *world = memnew(Node3D);
	VehicleDrivetrain3D *drivetrain = nullptr;
	VehicleBody3D *car = make_car(world, &drivetrain);
	SceneTree::get_singleton()->get_root()->add_child(world);

	int gear_changes = 0;
	struct Counter : public Object {
		int *count = nullptr;
		int highest = 0;
		void on_gear(int p_gear) {
			(*count)++;
			highest = MAX(highest, p_gear);
		}
	} counter;
	counter.count = &gear_changes;
	drivetrain->connect("gear_changed", callable_mp(&counter, &Counter::on_gear));

	simulate(60); // Let the suspension settle.
	CHECK(drivetrain->get_gear() == 1);
	CHECK(drivetrain->get_engine_rpm() == doctest::Approx(drivetrain->get_idle_rpm()).epsilon(0.05));

	drivetrain->set_throttle(1.0);
	real_t speed_after_2s = 0.0;
	real_t highest_rpm = 0.0;
	for (int i = 0; i < 50 * 60; i++) {
		simulate(1);
		highest_rpm = MAX(highest_rpm, drivetrain->get_engine_rpm());
		if (i == 2 * 60) {
			speed_after_2s = car->get_linear_velocity().length();
		}
	}
	const real_t final_speed = car->get_linear_velocity().length();
	// It drives forward, gets faster over time, and shifts up through several gears.
	CHECK(car->get_linear_velocity().dot(car->get_global_transform().basis.get_column(2)) > 0.0);
	CHECK(speed_after_2s > real_t(3.0));
	CHECK(final_speed > speed_after_2s * real_t(2.0));
	CHECK(gear_changes >= 3);
	CHECK(counter.highest >= 4);
	CHECK(drivetrain->get_gear() >= 4);
	// Engine speed stays within its range (a small overshoot is allowed by the limiter).
	CHECK(highest_rpm <= drivetrain->get_max_rpm() * real_t(1.06));
	// The top speed cannot exceed what the rev limiter allows in the highest gear.
	const real_t wheel_radius = 0.35;
	const real_t top_speed_limit = drivetrain->get_max_rpm() / (drivetrain->get_gear_ratios()[4] * drivetrain->get_final_drive()) * Math::TAU / 60.0 * wheel_radius;
	CHECK(final_speed <= top_speed_limit * real_t(1.05));

	// Releasing the throttle slows the car through engine braking and drag.
	drivetrain->set_throttle(0.0);
	simulate(5 * 60);
	CHECK(car->get_linear_velocity().length() < final_speed);

	memdelete(world);
}

} // namespace TestVehicleDrivetrain
