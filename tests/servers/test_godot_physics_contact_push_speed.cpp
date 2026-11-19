/**************************************************************************/
/*  test_godot_physics_contact_push_speed.cpp                              */
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

#include "servers/physics_contact_push_speed.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_contact_push_speed)

namespace TestGodotPhysicsContactPushSpeed {

TEST_CASE("[GodotPhysics] Contact bias push speed cap") {
	SUBCASE("Disabled by default: preserve original bias") {
		CHECK(godot_physics_limit_contact_bias(2000.0, 0.0) == doctest::Approx(2000.0));
		CHECK(godot_physics_limit_contact_bias(12.0, -1.0) == doctest::Approx(12.0));
	}
	SUBCASE("Clamp only excessive separation correction") {
		CHECK(godot_physics_limit_contact_bias(2000.0, 10.0) == doctest::Approx(10.0));
		CHECK(godot_physics_limit_contact_bias(3.0, 10.0) == doctest::Approx(3.0));
		CHECK(godot_physics_limit_contact_bias(10.0, 10.0) == doctest::Approx(10.0));
		CHECK(godot_physics_limit_contact_bias(0.0, 10.0) == doctest::Approx(0.0));
	}
	SUBCASE("Distinct physics units work without changing the rule") {
		// 2D uses pixels/second, 3D uses meters/second.
		CHECK(godot_physics_limit_contact_bias(500.0, 120.0) == doctest::Approx(120.0));
		CHECK(godot_physics_limit_contact_bias(8.0, 2.5) == doctest::Approx(2.5));
	}
}

} // namespace TestGodotPhysicsContactPushSpeed
