/**************************************************************************/
/*  test_physics_manifold_reduction_2d.cpp                                */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_manifold_reduction_2d.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_manifold_reduction_2d)

namespace TestPhysicsManifoldReduction2D {

TEST_CASE("[PhysicsManifold2D] Retain deepest contact and improve manifold span") {
	const Vector2 points[] = { Vector2(0, 0), Vector2(1, 0), Vector2(10, 0) };
	const real_t depths[] = { 4, 3, 1 };
	const Vector2 normals[] = { Vector2(0, 1), Vector2(0, 1), Vector2(0, 1) };
	CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(points, depths, normals) == 1);
}

TEST_CASE("[PhysicsManifold2D] Deepest new contact keeps the farthest partner") {
	const Vector2 points[] = { Vector2(0, 0), Vector2(10, 0), Vector2(8, 0) };
	const real_t depths[] = { 1, 2, 5 };
	const Vector2 normals[] = { Vector2(0, 1), Vector2(0, 1), Vector2(0, 1) };
	CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(points, depths, normals) == 1);
}

TEST_CASE("[PhysicsManifold2D] Preserve stable old contacts when span barely changes") {
	const Vector2 points[] = { Vector2(0, 0), Vector2(10, 0), Vector2(0.2, 0) };
	const real_t depths[] = { 4, 3, 1 };
	const Vector2 normals[] = { Vector2(0, 1), Vector2(0, 1), Vector2(0, 1) };
	CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(points, depths, normals) == -1);
}

TEST_CASE("[PhysicsManifold2D] Mixed contact normals use legacy depth reduction") {
	const Vector2 points[] = { Vector2(0, 0), Vector2(1, 0), Vector2(10, 0) };
	const Vector2 normals[] = { Vector2(0, 1), Vector2(1, 0), Vector2(0, 1) };
	const real_t deeper_new[] = { 4, 1, 3 };
	const real_t shallow_new[] = { 4, 3, 1 };
	CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(points, deeper_new, normals) == 1);
	CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(points, shallow_new, normals) == -1);
}

TEST_CASE("[PhysicsManifold2D] Tangent span is invariant under rigid rotation") {
	const Vector2 points[] = { Vector2(2, 3), Vector2(3, 3), Vector2(12, 3) };
	const real_t depths[] = { 4, 3, 1 };
	const Vector2 normals[] = { Vector2(0, 1), Vector2(0, 1), Vector2(0, 1) };
	for (int i = 0; i < 12; i++) {
		Vector2 rotated_points[3];
		Vector2 rotated_normals[3];
		const real_t angle = real_t(i) * real_t(0.27);
		for (int j = 0; j < 3; j++) {
			rotated_points[j] = points[j].rotated(angle) + Vector2(1000, -1000);
			rotated_normals[j] = normals[j].rotated(angle);
		}
		CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(rotated_points, depths, rotated_normals) == 1);
	}
}

TEST_CASE("[PhysicsManifold2D] Zero tangent span retains the earlier manifold") {
	const Vector2 points[] = { Vector2(0, 0), Vector2(0, 2), Vector2(0, 10) };
	const real_t depths[] = { 4, 3, 1 };
	const Vector2 normals[] = { Vector2(0, 1), Vector2(0, 1), Vector2(0, 1) };
	CHECK(GodotPhysicsManifoldReduction2D::choose_replacement(points, depths, normals) == -1);
}

} // namespace TestPhysicsManifoldReduction2D
