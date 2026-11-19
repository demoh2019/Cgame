/**************************************************************************/
/*  test_restitution_velocity.cpp                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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

TEST_FORCE_LINK(test_restitution_velocity)

#include "core/math/math_funcs.h"
#include "core/math/physics_contact.h"

TEST_CASE("[Physics] Restitution threshold ignores resting and separating contacts") {
	using GodotPhysicsContact::restitution_velocity;

	CHECK(restitution_velocity(1.0, -0.99, 1.0) == 0.0);
	CHECK(restitution_velocity(1.0, -1.0, 1.0) == 0.0);
	CHECK(restitution_velocity(1.0, 0.5, 1.0) == 0.0);
	CHECK(restitution_velocity(0.0, -10.0, 1.0) == 0.0);
}

TEST_CASE("[Physics] Restitution retains fast impacts and material scaling") {
	using GodotPhysicsContact::restitution_velocity;

	CHECK(Math::is_equal_approx(restitution_velocity(0.5, -4.0, 1.0), (real_t)-2.0));
	CHECK(Math::is_equal_approx(restitution_velocity(1.0, -4.0, 1.0), (real_t)-4.0));
	CHECK(Math::is_equal_approx(restitution_velocity(0.25, -20.0, 10.0), (real_t)-5.0));
	CHECK(Math::is_equal_approx(restitution_velocity(0.5, -4.0, 0.0), (real_t)-2.0));
}
