/**************************************************************************/
/*  test_bvh_segment.cpp                                                  */
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

TEST_FORCE_LINK(test_bvh_segment)

#include "core/math/aabb.h"
#include "core/math/bvh_abb.h"
#include "core/math/rect2.h"

namespace TestBVHSegment {

// Deterministic quarter-unit coordinates make expected edge inclusion exact
// (also on 32-bit real_t builds), without requiring RNG allocations.
static real_t next_quarter(uint32_t &r_seed) {
	r_seed = r_seed * 1664525U + 1013904223U;
	return real_t(int32_t((r_seed >> 8) % 321) - 160) * real_t(0.25);
}

TEST_CASE("[BVH] Packed 2D segment intersection matches Rect2 and entry fractions") {
	using Bounds = BVH_ABB<Rect2, Vector2>;
	uint32_t seed = 0x2134a77bU;
	for (int iteration = 0; iteration < 12000; ++iteration) {
		const Vector2 origin(next_quarter(seed), next_quarter(seed));
		const Vector2 size(Math::abs(next_quarter(seed)) + real_t(0.25), Math::abs(next_quarter(seed)) + real_t(0.25));
		const Rect2 rect(origin, size);
		Bounds packed;
		packed.from(rect);

		const Vector2 from(next_quarter(seed), next_quarter(seed));
		Vector2 to(next_quarter(seed), next_quarter(seed));
		if (iteration % 7 == 0) {
			to.x = from.x; // Axis-aligned.
		}
		if (iteration % 11 == 0) {
			to = from; // Degenerate segment.
		}
		const typename Bounds::Segment segment = { from, to };
		Vector2 reference_point;
		const bool reference_hit = rect.intersects_segment(from, to, &reference_point);
		real_t fraction = -1.0;
		const bool packed_hit = packed.intersects_segment(segment, &fraction);
		CHECK(packed_hit == reference_hit);
		CHECK(packed.intersects_segment(segment) == reference_hit);
		if (reference_hit) {
			CHECK(fraction >= 0.0);
			CHECK(fraction <= 1.0);
			const Vector2 travel = to - from;
			if (travel.length_squared() > 0.0) {
				const real_t expected_fraction = (reference_point - from).dot(travel) / travel.length_squared();
				CHECK(Math::abs(fraction - expected_fraction) < real_t(0.0001));
			} else {
				CHECK(fraction == 0.0);
			}
		} else {
			CHECK(fraction == -1.0); // Misses must not overwrite the output.
		}
	}

	const Rect2 rect(Vector2(-2, -3), Vector2(4, 6));
	Bounds packed;
	packed.from(rect);
	real_t fraction = -1.0;
	CHECK(packed.intersects_segment({ Vector2(0, 0), Vector2(10, 0) }, &fraction));
	CHECK(fraction == 0.0); // Starts inside.
	CHECK(packed.intersects_segment({ Vector2(-10, 3), Vector2(10, 3) })); // Grazes a face.
	CHECK(packed.intersects_segment({ Vector2(-10, -3), Vector2(-2, -3) })); // Hits a corner.
	CHECK(!packed.intersects_segment({ Vector2(-10, 4), Vector2(10, 4) }));
}

TEST_CASE("[BVH] Packed 3D segment intersection matches AABB and entry fractions") {
	using Bounds = BVH_ABB<AABB, Vector3>;
	uint32_t seed = 0x875a231fU;
	for (int iteration = 0; iteration < 12000; ++iteration) {
		const Vector3 origin(next_quarter(seed), next_quarter(seed), next_quarter(seed));
		const Vector3 size(Math::abs(next_quarter(seed)) + real_t(0.25), Math::abs(next_quarter(seed)) + real_t(0.25), Math::abs(next_quarter(seed)) + real_t(0.25));
		const AABB bounds(origin, size);
		Bounds packed;
		packed.from(bounds);

		const Vector3 from(next_quarter(seed), next_quarter(seed), next_quarter(seed));
		Vector3 to(next_quarter(seed), next_quarter(seed), next_quarter(seed));
		if (iteration % 7 == 0) {
			to.x = from.x;
		}
		if (iteration % 11 == 0) {
			to = from;
		}
		const typename Bounds::Segment segment = { from, to };
		Vector3 reference_point;
		const bool reference_hit = bounds.intersects_segment(from, to, &reference_point);
		real_t fraction = -1.0;
		const bool packed_hit = packed.intersects_segment(segment, &fraction);
		CHECK(packed_hit == reference_hit);
		CHECK(packed.intersects_segment(segment) == reference_hit);
		if (reference_hit) {
			CHECK(fraction >= 0.0);
			CHECK(fraction <= 1.0);
			const Vector3 travel = to - from;
			if (travel.length_squared() > 0.0) {
				const real_t expected_fraction = (reference_point - from).dot(travel) / travel.length_squared();
				CHECK(Math::abs(fraction - expected_fraction) < real_t(0.0001));
			} else {
				CHECK(fraction == 0.0);
			}
		} else {
			CHECK(fraction == -1.0);
		}
	}

	const AABB bounds(Vector3(-2, -3, -4), Vector3(4, 6, 8));
	Bounds packed;
	packed.from(bounds);
	real_t fraction = -1.0;
	CHECK(packed.intersects_segment({ Vector3(0, 0, 0), Vector3(10, 0, 0) }, &fraction));
	CHECK(fraction == 0.0);
	CHECK(packed.intersects_segment({ Vector3(-10, 3, 0), Vector3(10, 3, 0) }));
	CHECK(packed.intersects_segment({ Vector3(-10, -3, -4), Vector3(-2, -3, -4) }));
	CHECK(!packed.intersects_segment({ Vector3(-10, 4, 0), Vector3(10, 4, 0) }));
}

} // namespace TestBVHSegment
