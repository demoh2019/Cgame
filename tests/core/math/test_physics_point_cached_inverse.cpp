/**************************************************************************/
/*  test_physics_point_cached_inverse.cpp                                 */
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

TEST_FORCE_LINK(test_physics_point_cached_inverse)

#include "core/math/transform_2d.h"
#include "core/math/transform_3d.h"

namespace TestPhysicsPointCachedInverse {

TEST_CASE("[Physics] Cached 2D body and shape inverses match composed affine inverse") {
	// Both transforms include translation and nonorthogonal/nonuniform axes.
	const Transform2D body(Vector2(1.3, 0.2), Vector2(-0.3, 0.9), Vector2(5, -8));
	const Transform2D shape(Vector2(0.9, -0.2), Vector2(0.4, 1.4), Vector2(-2, 3));
	const Transform2D old_inverse = (body * shape).affine_inverse();
	const Transform2D shape_inverse = shape.affine_inverse();
	const Transform2D body_inverse = body.affine_inverse();

	for (int i = 0; i < 512; ++i) {
		const Vector2 point(real_t((i * 19) % 101) * 0.11 - 5.0,
				real_t((i * 37) % 97) * 0.13 - 6.0);
		const Vector2 world = body.xform(shape.xform(point));
		const Vector2 previously = old_inverse.xform(world);
		const Vector2 cached = shape_inverse.xform(body_inverse.xform(world));
		CHECK(cached.distance_to(previously) < real_t(0.0001));
		CHECK(cached.distance_to(point) < real_t(0.0001));
	}
}

TEST_CASE("[Physics] Cached 3D body and shape inverses match composed affine inverse") {
	const Basis body_basis(Vector3(1.2, 0.15, 0.02), Vector3(-0.2, 1.0, 0.3), Vector3(0.03, -0.1, 1.35));
	const Basis shape_basis(Vector3(0.75, 0.12, -0.03), Vector3(-0.17, 1.1, 0.09), Vector3(0.06, -0.13, 0.9));
	const Transform3D body(body_basis, Vector3(5, -8, 3));
	const Transform3D shape(shape_basis, Vector3(-2, 3, -1));
	const Transform3D old_inverse = (body * shape).affine_inverse();
	const Transform3D shape_inverse = shape.affine_inverse();
	const Transform3D body_inverse = body.affine_inverse();

	for (int i = 0; i < 512; ++i) {
		const Vector3 point(real_t((i * 19) % 101) * 0.11 - 5.0,
				real_t((i * 37) % 97) * 0.13 - 6.0,
				real_t((i * 23) % 89) * 0.09 - 4.0);
		const Vector3 world = body.xform(shape.xform(point));
		const Vector3 previously = old_inverse.xform(world);
		const Vector3 cached = shape_inverse.xform(body_inverse.xform(world));
		CHECK(cached.distance_to(previously) < real_t(0.0001));
		CHECK(cached.distance_to(point) < real_t(0.0001));
	}
}

} // namespace TestPhysicsPointCachedInverse
