/**************************************************************************/
/*  test_segment_capsule.cpp                                              */
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

TEST_FORCE_LINK(test_segment_capsule)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestSegmentCapsule {

struct ContactCount {
	int count = 0;

	static void count_contact(const Vector2 &, const Vector2 &, void *p_userdata) {
		static_cast<ContactCount *>(p_userdata)->count++;
	}
};

static bool collide(const GodotSegmentShape2D &p_segment, const Transform2D &p_segment_transform,
		const GodotCapsuleShape2D &p_capsule, const Transform2D &p_capsule_transform,
		ContactCount *p_contact = nullptr, Vector2 *r_sep_axis = nullptr,
		const Vector2 &p_motion = Vector2(), real_t p_margin_a = 0.0, real_t p_margin_b = 0.0) {
	return sat_2d_calculate_penetration(&p_segment, p_segment_transform, Vector2(),
			&p_capsule, p_capsule_transform, p_motion,
			p_contact ? ContactCount::count_contact : nullptr, p_contact,
			false, r_sep_axis, p_margin_a, p_margin_b);
}

TEST_CASE("[GodotPhysics2D] Segment-capsule overlap-only nearest-point path") {
	GodotSegmentShape2D segment(Vector2(-4, 0), Vector2(4, 0), Vector2(0, -1));
	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(1, 4)); // Height 4, radius 1, half center segment 1.
	const Transform2D segment_transform;
	Transform2D capsule_transform;

	Vector2 sep_axis;
	capsule_transform.set_origin(Vector2(0, 4));
	CHECK_FALSE(collide(segment, segment_transform, capsule, capsule_transform, nullptr, &sep_axis));
	CHECK(sep_axis.is_equal_approx(Vector2(0, -1)));

	capsule_transform.set_origin(Vector2(0, real_t(2.0)));
	sep_axis = Vector2(1, 0);
	CHECK(collide(segment, segment_transform, capsule, capsule_transform, nullptr, &sep_axis));
	CHECK(sep_axis == Vector2());

	capsule_transform.set_origin(Vector2(0, real_t(2.4)));
	CHECK_FALSE(collide(segment, segment_transform, capsule, capsule_transform));
	CHECK(collide(segment, segment_transform, capsule, capsule_transform, nullptr, nullptr,
			Vector2(), real_t(0.25), real_t(0.2)));

	ContactCount count;
	capsule_transform.set_origin(Vector2(0, real_t(1.4)));
	CHECK(collide(segment, segment_transform, capsule, capsule_transform, &count));
	CHECK(count.count > 0); // Callback uses the original SAT manifold.
}

TEST_CASE("[GodotPhysics2D] Segment-capsule exterior grid versus distance oracle") {
	GodotSegmentShape2D segment(Vector2(-4, 0), Vector2(4, 0), Vector2(0, -1));
	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(1, 4));
	const Transform2D segment_transform;
	Transform2D capsule_transform;

	for (int x = -30; x <= 30; x++) {
		for (int y = -30; y <= 30; y++) {
			const Vector2 center(x * real_t(0.27) + real_t(0.019), y * real_t(0.16) + real_t(0.031));
			// For horizontal segment [-4,4] and vertical capsule [-1,1],
			// segment-to-segment distance is distance to this axis-aligned box.
			const real_t dx = MAX(Math::abs(center.x) - real_t(4.0), real_t(0.0));
			const real_t dy = MAX(Math::abs(center.y) - real_t(1.0), real_t(0.0));
			const real_t distance_squared = dx * dx + dy * dy;
			if (Math::abs(distance_squared - real_t(1.0)) <= real_t(0.0001)) {
				continue;
			}
			capsule_transform.set_origin(center);
			CHECK(collide(segment, segment_transform, capsule, capsule_transform) == (distance_squared < real_t(1.0)));
		}
	}
}

TEST_CASE("[GodotPhysics2D] Segment-capsule rotated, swept and scaled fallbacks") {
	GodotSegmentShape2D segment(Vector2(-4, 0), Vector2(4, 0), Vector2(0, -1));
	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(1, 4));
	const Transform2D segment_transform;
	Transform2D capsule_transform;

	const Transform2D rotated(real_t(Math::PI * 0.5), Vector2(0, real_t(0.5)));
	CHECK(collide(segment, segment_transform, capsule, rotated));

	capsule_transform.set_origin(Vector2(0, 4));
	CHECK(collide(segment, segment_transform, capsule, capsule_transform, nullptr, nullptr, Vector2(0, -3)));

	capsule_transform.columns[0] = Vector2(real_t(1.5), 0);
	capsule_transform.columns[1] = Vector2(0, real_t(1.5));
	capsule_transform.set_origin(Vector2(0, real_t(2.3)));
	ContactCount count;
	CHECK(collide(segment, segment_transform, capsule, capsule_transform, &count));
	CHECK(count.count > 0);
}

} // namespace TestSegmentCapsule

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
