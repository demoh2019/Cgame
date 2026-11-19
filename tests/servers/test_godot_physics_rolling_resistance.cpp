/**************************************************************************/
/*  test_godot_physics_rolling_resistance.cpp                              */
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
/**************************************************************************/

#include "servers/physics_rolling_resistance.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_rolling_resistance)

namespace TestGodotPhysicsRollingResistance {

TEST_CASE("[GodotPhysics2D] Rolling resistance solver") {
	SUBCASE("Normal impulse caps torque") {
		CHECK(godot_physics_accumulate_rolling_impulse(0.0, -20.0, 2.0, 3.0, 1.0) == doctest::Approx(3.0));
	}
	SUBCASE("No overshoot at low angular speed") {
		CHECK(godot_physics_accumulate_rolling_impulse(0.0, 1.0, 2.0, 10.0, 1.0) == doctest::Approx(-0.5));
	}
	SUBCASE("One cap applies to all solver iterations") {
		const real_t first = godot_physics_accumulate_rolling_impulse(0.0, -10.0, 1.0, 2.0, 0.5);
		const real_t second = godot_physics_accumulate_rolling_impulse(first, -10.0, 1.0, 2.0, 0.5);
		CHECK(first == doctest::Approx(1.0));
		CHECK(second == doctest::Approx(1.0));
	}
	SUBCASE("Disappearing normal load releases previously applied torque") {
		CHECK(godot_physics_accumulate_rolling_impulse(1.0, 1.0, 1.0, 0.0, 0.5) == doctest::Approx(0.0));
	}
	SUBCASE("No torque for a static or locked pair") {
		CHECK(godot_physics_accumulate_rolling_impulse(0.0, 20.0, 0.0, 3.0, 0.5) == doctest::Approx(0.0));
		CHECK(godot_physics_accumulate_rolling_impulse(0.0, 20.0, 1.0, 3.0, 0.0) == doctest::Approx(0.0));
	}
	SUBCASE("Reversing body order reverses the torque") {
		const real_t a = godot_physics_accumulate_rolling_impulse(0.0, 3.0, 1.0, 2.0, 1.0);
		const real_t b = godot_physics_accumulate_rolling_impulse(0.0, -3.0, 1.0, 2.0, 1.0);
		CHECK(a == doctest::Approx(-b));
	}
}

} // namespace TestGodotPhysicsRollingResistance
