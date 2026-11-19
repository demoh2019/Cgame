/**************************************************************************/
/*  test_godot_physics_manifold_reduction_3d.cpp                          */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_manifold_reduction_3d.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_manifold_reduction_3d)

namespace TestGodotPhysicsManifoldReduction3D {

TEST_CASE("[GodotPhysics3D] Keep the broad original contact patch") {
	const Vector3 points[5] = {
		Vector3(-1, -1, 0), Vector3(1, -1, 0),
		Vector3(1, 1, 0), Vector3(-1, 1, 0),
		Vector3(0, 0, 0),
	};
	const real_t depths[5] = { 2, 1, 1, 1, real_t(0.5) };
	const Vector3 normals[5] = { Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1) };
	// The incoming center point has no benefit for patch coverage.
	CHECK(GodotPhysicsManifoldReduction3D::choose_replacement(points, depths, normals) == -1);
}

TEST_CASE("[GodotPhysics3D] Replace an interior point to cover the surface") {
	const Vector3 points[5] = {
		Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, real_t(0.2), 0), Vector3(10, 0, 0),
	};
	const real_t depths[5] = { 2, 1, 1, 1, real_t(0.5) };
	const Vector3 normals[5] = { Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1) };
	CHECK(GodotPhysicsManifoldReduction3D::choose_replacement(points, depths, normals) == 3);
}

TEST_CASE("[GodotPhysics3D] Never discard the deepest penetration") {
	const Vector3 points[5] = {
		Vector3(-1, -1, 0), Vector3(1, -1, 0),
		Vector3(1, 1, 0), Vector3(-1, 1, 0), Vector3(0, 0, 0),
	};
	const real_t depths[5] = { 1, 1, 1, 1, 3 };
	const Vector3 normals[5] = { Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1) };
	const int replace = GodotPhysicsManifoldReduction3D::choose_replacement(points, depths, normals);
	CHECK(replace >= 0);
	CHECK(replace < GodotPhysicsManifoldReduction3D::MAX_CONTACTS);
}

TEST_CASE("[GodotPhysics3D] Different face normals retain the legacy depth selection") {
	const Vector3 points[5] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1),
	};
	const real_t depths[5] = { 1, 2, 3, 4, real_t(0.5) };
	const Vector3 normals[5] = { Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 0) };
	CHECK(GodotPhysicsManifoldReduction3D::choose_replacement(points, depths, normals) == -1);
	const real_t deep_new[5] = { 1, 2, 3, 4, 5 };
	CHECK(GodotPhysicsManifoldReduction3D::choose_replacement(points, deep_new, normals) == 0);
}

TEST_CASE("[GodotPhysics3D] Degenerate line contact does not replace a valid point") {
	const Vector3 points[5] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0),
		Vector3(3, 0, 0), Vector3(4, 0, 0),
	};
	const real_t depths[5] = { 2, 1, 1, 1, real_t(0.5) };
	const Vector3 normals[5] = { Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1) };
	CHECK(GodotPhysicsManifoldReduction3D::choose_replacement(points, depths, normals) == -1);
}

} // namespace TestGodotPhysicsManifoldReduction3D
