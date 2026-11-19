/**************************************************************************/
/*  test_physics_ccd_circle_segment_toi.cpp                                       */
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

#include "servers/physics_ccd_circle_segment_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_circle_segment_toi)

namespace TestPhysicsCCDCircleSegmentTOI {

TEST_CASE("[Physics][CircleSegmentTOI] Glancing entry against a segment endpoint") {
	double fraction = -1.0;
	// A circle with radius 1 grazes the lower endpoint (0,-1) of a
	// vertical line. Its leading point ray at y=-1.8 misses entirely.
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(-4.0, -1.8), Vector2(8.0, 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.425) < 0.000001);

	// Reversing which shape moves reverses the relative sweep, without
	// changing the first contact fraction.
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(4.0, -1.8), Vector2(-8.0, 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.425) < 0.000001);

	// The crossing must be independent of segment endpoint ordering.
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(-4.0, -1.8), Vector2(8.0, 0.0),
			Vector2(0.0, 1.0), Vector2(0.0, -1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.425) < 0.000001);
}

TEST_CASE("[Physics][CircleSegmentTOI] Side crossings and zero-length segments") {
	double fraction = -1.0;
	// Arbitrarily oriented (here horizontal) segments are handled by
	// rotating the sweep to the capsule's local axis.
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(1.0, -4.0), Vector2(0.0, 8.0),
			Vector2(0.0, 0.0), Vector2(2.0, 0.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.375) < 0.000001);

	// A degenerate segment is a point, whose Minkowski sum is a circle.
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(-4.0, 0.3), Vector2(8.0, 0.0),
			Vector2(), Vector2(),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::HIT);
	CHECK(Math::abs(fraction - (4.0 - Math::sqrt(0.91)) / 8.0) < 0.000001);
}

TEST_CASE("[Physics][CircleSegmentTOI] Preserve contact fallback, misses and precision") {
	double fraction = -1.0;
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(0.0, 0.0), Vector2(8.0, 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::FALLBACK);
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(-4.0, -2.01), Vector2(8.0, 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::MISS);
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(-4.0, -1.8), Vector2(-8.0, 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::MISS);
	CHECK(physics_ccd_circle_segment_toi(
			Vector2(-4.0, -1.8), Vector2(8.0, 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			0.0, fraction) == PhysicsCCDCircleSegmentTOIResult::FALLBACK);

	CHECK(physics_ccd_circle_segment_toi(
			Vector2(real_t(-1e20), 0.0), Vector2(real_t(2e20), 0.0),
			Vector2(0.0, -1.0), Vector2(0.0, 1.0),
			1.0, fraction) == PhysicsCCDCircleSegmentTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.5) < 0.000000001);
}

} // namespace TestPhysicsCCDCircleSegmentTOI
