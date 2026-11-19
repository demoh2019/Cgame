/**************************************************************************/
/*  test_godot_physics_2d_concave_affine_culling.cpp                       */
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

TEST_FORCE_LINK(test_godot_physics_2d_concave_affine_culling)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d.h"

namespace TestGodotPhysics2DConcaveAffineCulling {

TEST_CASE("[GodotPhysics2D] Concave BVH culling honors sheared and scaled transforms") {
	GodotCircleShape2D circle;
	circle.set_data(real_t(0.25));

	GodotConcavePolygonShape2D concave;
	PackedVector2Array edges;
	edges.push_back(Vector2(0.0, -1.0));
	edges.push_back(Vector2(0.0, 1.0));
	concave.set_data(edges);

	// The world-space line is x = 2*y. A circle at (1.86, 0.9)
	// overlaps it even though the world X differs greatly from local X.
	const Transform2D shear(Vector2(1.0, 0.0), Vector2(2.0, 1.0), Vector2());
	const Transform2D near_circle(real_t(0.0), Vector2(1.86, 0.9));
	const Transform2D far_circle(real_t(0.0), Vector2(3.0, 0.9));
	CHECK(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, shear, Vector2(), nullptr, nullptr));
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle, far_circle, Vector2(),
			&concave, shear, Vector2(), nullptr, nullptr));

	// The same local geometry under nonuniform scale and rotation.
	const Transform2D scaled_rotated(Vector2(0.0, 2.0), Vector2(-0.5, 0.0), Vector2(4.0, -3.0));
	const Transform2D scaled_near(real_t(0.0), Vector2(3.75, -3.0));
	CHECK(GodotCollisionSolver2D::solve(&circle, scaled_near, Vector2(),
			&concave, scaled_rotated, Vector2(), nullptr, nullptr));
}

TEST_CASE("[GodotPhysics2D] Concave culling accounts for margins and relative motion") {
	GodotCircleShape2D circle;
	circle.set_data(real_t(0.25));

	GodotConcavePolygonShape2D concave;
	PackedVector2Array edges;
	edges.push_back(Vector2(0.0, -1.0));
	edges.push_back(Vector2(0.0, 1.0));
	concave.set_data(edges);

	const Transform2D identity;
	const Transform2D near_circle(real_t(0.0), Vector2(0.35, 0.0));
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, identity, Vector2(), nullptr, nullptr));
	CHECK(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, identity, Vector2(), nullptr, nullptr, real_t(0.15), real_t(0.0)));

	// A stationary circle meets a line that sweeps through it. The
	// broadphase must use motion_A - motion_B in the concave local frame.
	const Transform2D moving_circle(real_t(0.0), Vector2(1.0, 0.0));
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle, moving_circle, Vector2(),
			&concave, identity, Vector2(), nullptr, nullptr));
	CHECK(GodotCollisionSolver2D::solve(&circle, moving_circle, Vector2(),
			&concave, identity, Vector2(2.0, 0.0), nullptr, nullptr));
}

} // namespace TestGodotPhysics2DConcaveAffineCulling

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
