/**************************************************************************/
/*  test_foot_placement_modifier_3d.cpp                                   */
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

TEST_FORCE_LINK(test_foot_placement_modifier_3d)

#ifndef _3D_DISABLED

#include "scene/3d/foot_placement_modifier_3d.h"
#include "scene/3d/stride_warping_modifier_3d.h"

namespace TestFootPlacementModifier3D {

TEST_CASE("[SceneTree][FootPlacementModifier3D] solve_two_bone_angles") {
	SUBCASE("Fully extended chain") {
		Vector2 a = FootPlacementModifier3D::solve_two_bone_angles(1.0f, 1.0f, 2.0f);
		CHECK(a.x == doctest::Approx(0.0f).epsilon(0.001));
		CHECK(a.y == doctest::Approx((float)Math::PI).epsilon(0.001));
	}
	SUBCASE("Target beyond reach is clamped") {
		Vector2 a = FootPlacementModifier3D::solve_two_bone_angles(1.0f, 1.0f, 5.0f);
		CHECK(a.x == doctest::Approx(0.0f).epsilon(0.001));
		CHECK(a.y == doctest::Approx((float)Math::PI).epsilon(0.001));
	}
	SUBCASE("Right angle knee") {
		Vector2 a = FootPlacementModifier3D::solve_two_bone_angles(1.0f, 1.0f, Math::sqrt(2.0f));
		CHECK(a.x == doctest::Approx((float)Math::PI / 4.0f).epsilon(0.001));
		CHECK(a.y == doctest::Approx((float)Math::PI / 2.0f).epsilon(0.001));
	}
	SUBCASE("Equilateral triangle") {
		Vector2 a = FootPlacementModifier3D::solve_two_bone_angles(1.0f, 1.0f, 1.0f);
		CHECK(a.x == doctest::Approx((float)Math::PI / 3.0f).epsilon(0.001));
		CHECK(a.y == doctest::Approx((float)Math::PI / 3.0f).epsilon(0.001));
	}
	SUBCASE("Angles of a triangle sum to PI") {
		Vector2 a = FootPlacementModifier3D::solve_two_bone_angles(0.45f, 0.4f, 0.7f);
		float other = (float)Math::PI - a.x - a.y; // Angle at the target (end) vertex.
		CHECK(other > 0.0f);
		CHECK(Math::sin(other) / 0.45f == doctest::Approx(Math::sin(a.y) / 0.7f).epsilon(0.001));
	}
	SUBCASE("Degenerate lengths do not produce NaN") {
		Vector2 a = FootPlacementModifier3D::solve_two_bone_angles(0.0f, 1.0f, 1.0f);
		CHECK_FALSE(Math::is_nan(a.x));
		CHECK_FALSE(Math::is_nan(a.y));
	}
}

TEST_CASE("[SceneTree][FootPlacementModifier3D] pelvis_offset") {
	PackedFloat32Array offsets;
	CHECK(FootPlacementModifier3D::pelvis_offset(offsets, 0.5f) == doctest::Approx(0.0f));

	offsets.push_back(0.1f);
	offsets.push_back(0.3f);
	CHECK_MESSAGE(FootPlacementModifier3D::pelvis_offset(offsets, 0.5f) == doctest::Approx(0.0f), "Only upward offsets do not move the pelvis.");

	offsets.push_back(-0.2f);
	CHECK(FootPlacementModifier3D::pelvis_offset(offsets, 0.5f) == doctest::Approx(-0.2f));
	CHECK_MESSAGE(FootPlacementModifier3D::pelvis_offset(offsets, 0.1f) == doctest::Approx(-0.1f), "Clamped by max offset.");

	offsets.push_back(-0.35f);
	CHECK(FootPlacementModifier3D::pelvis_offset(offsets, 1.0f) == doctest::Approx(-0.35f));
	CHECK(FootPlacementModifier3D::pelvis_offset(offsets, 0.0f) == doctest::Approx(0.0f));
}

TEST_CASE("[SceneTree][FootPlacementModifier3D] ground_normal_from_samples and clamped_alignment") {
	SUBCASE("Flat ground") {
		Vector3 n = FootPlacementModifier3D::ground_normal_from_samples(1.0f, 1.0f, 1.0f, 0.1f);
		CHECK(n.is_equal_approx(Vector3(0, 1, 0)));
	}
	SUBCASE("Slope rising along +X tilts the normal towards -X") {
		Vector3 n = FootPlacementModifier3D::ground_normal_from_samples(0.0f, 0.1f, 0.0f, 0.1f);
		CHECK(n.x < 0.0f);
		CHECK(n.y > 0.0f);
		CHECK(Math::is_zero_approx(n.z));
		CHECK(n.length() == doctest::Approx(1.0f));
		// 45 degree slope.
		CHECK(n.is_equal_approx(Vector3(-Math::sqrt(0.5f), Math::sqrt(0.5f), 0)));
	}
	SUBCASE("Slope rising along +Z tilts the normal towards -Z") {
		Vector3 n = FootPlacementModifier3D::ground_normal_from_samples(0.0f, 0.0f, 0.1f, 0.1f);
		CHECK(n.z < 0.0f);
		CHECK(Math::is_zero_approx(n.x));
	}
	SUBCASE("Alignment is clamped") {
		Vector3 up(0, 1, 0);
		Vector3 steep = Vector3(1, 1, 0).normalized(); // 45 degrees.
		Quaternion q = FootPlacementModifier3D::clamped_alignment(up, steep, Math::deg_to_rad(20.0f));
		CHECK(q.get_angle() == doctest::Approx(Math::deg_to_rad(20.0f)).epsilon(0.001));
		Quaternion full = FootPlacementModifier3D::clamped_alignment(up, steep, Math::deg_to_rad(80.0f));
		CHECK((full.xform(up)).is_equal_approx(steep));
		Quaternion none = FootPlacementModifier3D::clamped_alignment(up, up, Math::deg_to_rad(80.0f));
		CHECK(none.is_equal_approx(Quaternion()));
	}
}

TEST_CASE("[SceneTree][StrideWarpingModifier3D] stride scale and foot warping") {
	CHECK(StrideWarpingModifier3D::compute_stride_scale(3.0f, 4.0f, 0.5f, 2.0f) == doctest::Approx(0.75f));
	CHECK(StrideWarpingModifier3D::compute_stride_scale(10.0f, 4.0f, 0.5f, 2.0f) == doctest::Approx(2.0f));
	CHECK(StrideWarpingModifier3D::compute_stride_scale(0.1f, 4.0f, 0.5f, 2.0f) == doctest::Approx(0.5f));
	CHECK_MESSAGE(StrideWarpingModifier3D::compute_stride_scale(3.0f, 0.0f, 0.5f, 2.0f) == doctest::Approx(1.0f), "Zero animation speed gives identity.");

	Vector3 pelvis(1, 1, 1);
	Vector3 foot(2, 0.2f, 4);
	Vector3 warped = StrideWarpingModifier3D::warp_foot_position(foot, pelvis, 2.0f);
	CHECK(warped.is_equal_approx(Vector3(3, 0.2f, 7)));
	CHECK(StrideWarpingModifier3D::warp_foot_position(foot, pelvis, 1.0f).is_equal_approx(foot));
	CHECK(StrideWarpingModifier3D::warp_foot_position(foot, pelvis, 0.0f).is_equal_approx(Vector3(1, 0.2f, 1)));
}

TEST_CASE("[SceneTree][FootPlacementModifier3D] leg properties") {
	FootPlacementModifier3D *mod = memnew(FootPlacementModifier3D);
	CHECK(mod->get_leg_count() == 0);
	int idx = mod->add_leg("thigh_l", "calf_l", "foot_l", 0.05f);
	CHECK(idx == 0);
	mod->set_leg_count(2);
	CHECK(mod->get_leg_count() == 2);
	mod->set("legs/1/foot_bone", "foot_r");
	CHECK(String(mod->get("legs/1/foot_bone")) == "foot_r");
	CHECK(String(mod->get("legs/0/thigh_bone")) == "thigh_l");
	CHECK(float(mod->get("legs/0/foot_height_offset")) == doctest::Approx(0.05f));
	mod->clear_legs();
	CHECK(mod->get_leg_count() == 0);
	memdelete(mod);
}

} // namespace TestFootPlacementModifier3D

#endif // _3D_DISABLED
