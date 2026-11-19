/**************************************************************************/
/*  test_godot_physics_2d_affine_margin_rows.cpp                           */
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

TEST_FORCE_LINK(test_godot_physics_2d_affine_margin_rows)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d.h"

namespace TestGodotPhysics2DAffineMarginRows {

TEST_CASE("[GodotPhysics2D] Concave margin expands along inverse affine rows") {
	GodotCircleShape2D circle;
	circle.set_data(real_t(0.1));

	GodotConcavePolygonShape2D concave;
	PackedVector2Array edges;
	edges.push_back(Vector2(0.0, -1.0));
	edges.push_back(Vector2(0.0, 1.0));
	concave.set_data(edges);

	const Transform2D compressed(Vector2(0.1, 0.0), Vector2(0.0, 1.0), Vector2());
	const Transform2D near_circle(real_t(0.0), Vector2(0.65, 0.0));
	const Transform2D far_circle(real_t(0.0), Vector2(1.2, 0.0));

	// Inverse X scaling is 10: a world margin of 0.6 expands the local
	// query by 6, not 0.06. The old implementation lost this contact.
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, compressed, Vector2(), nullptr, nullptr));
	CHECK(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, compressed, Vector2(), nullptr, nullptr, nullptr, real_t(0.6), real_t(0.0)));
	CHECK(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, compressed, Vector2(), nullptr, nullptr, nullptr, real_t(0.0), real_t(0.6)));
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle, far_circle, Vector2(),
			&concave, compressed, Vector2(), nullptr, nullptr, nullptr, real_t(0.6), real_t(0.0)));

	const Transform2D sheared_compressed(Vector2(0.1, 0.0), Vector2(2.0, 1.0), Vector2());
	// The inverse local-X row is (10,-20), with norm sqrt(500).
	CHECK(GodotCollisionSolver2D::solve(&circle, near_circle, Vector2(),
			&concave, sheared_compressed, Vector2(), nullptr, nullptr, nullptr, real_t(0.6), real_t(0.0)));
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle, Transform2D(real_t(0.0), Vector2(4.0, 0.0)), Vector2(),
			&concave, sheared_compressed, Vector2(), nullptr, nullptr, nullptr, real_t(0.6), real_t(0.0)));
}

} // namespace TestGodotPhysics2DAffineMarginRows

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
