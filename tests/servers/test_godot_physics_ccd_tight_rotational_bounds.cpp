/**************************************************************************/
/*  test_godot_physics_ccd_tight_rotational_bounds.cpp                    */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER FOR A PARTICULAR PURPOSE AND */
/* NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE  */
/* LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION  */
/* OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION   */
/* WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.        */
/**************************************************************************/

#include "core/math/basis.h"
#include "servers/physics_ccd_tight_rotational_bounds.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_ccd_tight_rotational_bounds)

namespace TestGodotPhysicsCCDTightRotationalBounds {

static bool contains_point(const Rect2 &p_bounds, const Vector2 &p_point) {
	const Vector2 lower = p_bounds.position;
	const Vector2 upper = p_bounds.get_end();
	return p_point.x >= lower.x - real_t(0.0001) && p_point.x <= upper.x + real_t(0.0001) &&
			p_point.y >= lower.y - real_t(0.0001) && p_point.y <= upper.y + real_t(0.0001);
}

static bool contains_point(const AABB &p_bounds, const Vector3 &p_point) {
	const Vector3 lower = p_bounds.position;
	const Vector3 upper = p_bounds.get_end();
	return p_point.x >= lower.x - real_t(0.0001) && p_point.x <= upper.x + real_t(0.0001) &&
			p_point.y >= lower.y - real_t(0.0001) && p_point.y <= upper.y + real_t(0.0001) &&
			p_point.z >= lower.z - real_t(0.0001) && p_point.z <= upper.z + real_t(0.0001);
}

TEST_CASE("[GodotPhysics] Tight 2D rotation bounds contain intermediate corners") {
	const Rect2 initial(Vector2(8, -1), Vector2(4, 2));
	const Vector2 pivot(0, 0);
	const Vector2 translation(3, -2);
	for (real_t angle : { real_t(0.01), real_t(0.8), real_t(-1.3), real_t(7.0) }) {
		const Rect2 bound = godot_physics_ccd_tight_rotational_bounds(initial, pivot, angle, translation);
		for (int corner = 0; corner < 4; corner++) {
			const Vector2 original((corner & 1) ? initial.position.x : initial.get_end().x,
					(corner & 2) ? initial.position.y : initial.get_end().y);
			for (int step = 0; step <= 64; step++) {
				const real_t t = real_t(step) / real_t(64);
				const Vector2 rotated = (original - pivot).rotated(angle * t) + pivot + translation * t;
				CHECK(contains_point(bound, rotated));
			}
		}
	}
}

TEST_CASE("[GodotPhysics] Tight 3D rotation bounds contain intermediate corners") {
	const AABB initial(Vector3(8, -1, -2), Vector3(4, 2, 4));
	const Vector3 pivot(0, 0, 0);
	const Vector3 translation(3, -2, 1);
	for (real_t angle : { real_t(0.01), real_t(0.9), real_t(3.0), real_t(7.0) }) {
		const Vector3 axis = Vector3(1, 2, -3).normalized();
		const AABB bound = godot_physics_ccd_tight_rotational_bounds(initial, pivot, axis * angle, translation);
		for (int corner = 0; corner < 8; corner++) {
			const Vector3 original((corner & 1) ? initial.position.x : initial.get_end().x,
					(corner & 2) ? initial.position.y : initial.get_end().y,
					(corner & 4) ? initial.position.z : initial.get_end().z);
			for (int step = 0; step <= 64; step++) {
				const real_t t = real_t(step) / real_t(64);
				const Vector3 rotated = Basis(axis, angle * t).xform(original - pivot) + pivot + translation * t;
				CHECK(contains_point(bound, rotated));
			}
		}
	}
}

TEST_CASE("[GodotPhysics] Tight bounds reject extraneous radial broadphase area") {
	const Rect2 initial_2d(Vector2(8, -1), Vector2(4, 2));
	const real_t angle = real_t(0.4);
	const real_t padding_2d = godot_physics_ccd_rotational_padding(
			initial_2d, Vector2(), godot_physics_ccd_rotational_factor(angle));
	const Rect2 broad_2d = initial_2d.grow(padding_2d);
	const Rect2 tight_2d = godot_physics_ccd_tight_rotational_bounds(initial_2d, Vector2(), angle, Vector2());
	CHECK(tight_2d.size.x * tight_2d.size.y < broad_2d.size.x * broad_2d.size.y);

	const AABB initial_3d(Vector3(8, -1, -2), Vector3(4, 2, 4));
	const real_t padding_3d = godot_physics_ccd_rotational_padding(
			initial_3d, Vector3(), godot_physics_ccd_rotational_factor(angle));
	AABB broad_3d = initial_3d;
	broad_3d.grow_by(padding_3d);
	const AABB tight_3d = godot_physics_ccd_tight_rotational_bounds(
			initial_3d, Vector3(), Vector3(0, 0, angle), Vector3());
	CHECK(tight_3d.size.x * tight_3d.size.y * tight_3d.size.z <
			broad_3d.size.x * broad_3d.size.y * broad_3d.size.z);
}

TEST_CASE("[GodotPhysics] Tight bounds preserve pure translation and zero angular displacement") {
	const Rect2 r(Vector2(2, -1), Vector2(3, 4));
	const Rect2 b = godot_physics_ccd_tight_rotational_bounds(r, Vector2(), 0, Vector2(4, -3));
	CHECK(b == r.merge(Rect2(r.position + Vector2(4, -3), r.size)));

	const AABB a(Vector3(2, -1, 1), Vector3(3, 4, 2));
	const AABB next = godot_physics_ccd_tight_rotational_bounds(
			a, Vector3(), Vector3(), Vector3(4, -3, 1));
	AABB expected = a;
	expected.merge_with(AABB(a.position + Vector3(4, -3, 1), a.size));
	CHECK(next == expected);
}

} // namespace TestGodotPhysicsCCDTightRotationalBounds
