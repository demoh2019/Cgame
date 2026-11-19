/**************************************************************************/
/*  test_curve.cpp                                                        */
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

TEST_FORCE_LINK(test_curve)

#include "core/math/math_funcs.h"
#include "scene/resources/curve.h"

namespace TestCurve {

TEST_CASE("[Curve] Default curve") {
	const Ref<Curve> curve = memnew(Curve);

	CHECK_MESSAGE(
			curve->get_point_count() == 0,
			"Default curve should contain the expected number of points.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(0)),
			"Default curve should return the expected value at offset 0.0.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(0.5)),
			"Default curve should return the expected value at offset 0.5.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(1)),
			"Default curve should return the expected value at offset 1.0.");
}

TEST_CASE("[Curve] Custom unit curve with free tangents") {
	Ref<Curve> curve = memnew(Curve);
	// "Sawtooth" curve with an open ending towards the 1.0 offset.
	curve->add_point(Vector2(0, 0));
	curve->add_point(Vector2(0.25, 1));
	curve->add_point(Vector2(0.5, 0));
	curve->add_point(Vector2(0.75, 1));
	curve->set_bake_resolution(11);

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_left_tangent(0)),
			"get_point_left_tangent() should return the expected value for point index 0.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_right_tangent(0)),
			"get_point_right_tangent() should return the expected value for point index 0.");
	CHECK_MESSAGE(
			curve->get_point_left_mode(0) == Curve::TangentMode::TANGENT_FREE,
			"get_point_left_mode() should return the expected value for point index 0.");
	CHECK_MESSAGE(
			curve->get_point_right_mode(0) == Curve::TangentMode::TANGENT_FREE,
			"get_point_right_mode() should return the expected value for point index 0.");

	CHECK_MESSAGE(
			curve->get_point_count() == 4,
			"Custom free curve should contain the expected number of points.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(-0.1)),
			"Custom free curve should return the expected value at offset -0.1.");
	CHECK_MESSAGE(
			curve->sample(0.1) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected value at offset 0.1.");
	CHECK_MESSAGE(
			curve->sample(0.4) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected value at offset 0.4.");
	CHECK_MESSAGE(
			curve->sample(0.7) == doctest::Approx((real_t)0.896),
			"Custom free curve should return the expected value at offset 0.7.");
	CHECK_MESSAGE(
			curve->sample(1) == doctest::Approx(1),
			"Custom free curve should return the expected value at offset 1.");
	CHECK_MESSAGE(
			curve->sample(2) == doctest::Approx(1),
			"Custom free curve should return the expected value at offset 2.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample_baked(-0.1)),
			"Custom free curve should return the expected baked value at offset -0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.1) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected baked value at offset 0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.4) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected baked value at offset 0.4.");
	CHECK_MESSAGE(
			curve->sample_baked(0.7) == doctest::Approx((real_t)0.896),
			"Custom free curve should return the expected baked value at offset 0.7.");
	CHECK_MESSAGE(
			curve->sample_baked(1) == doctest::Approx(1),
			"Custom free curve should return the expected baked value at offset 1.");
	CHECK_MESSAGE(
			curve->sample_baked(2) == doctest::Approx(1),
			"Custom free curve should return the expected baked value at offset 2.");

	curve->remove_point(1);
	CHECK_MESSAGE(
			curve->sample(0.1) == doctest::Approx(0),
			"Custom free curve should return the expected value at offset 0.1 after removing point at index 1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.1) == doctest::Approx(0),
			"Custom free curve should return the expected baked value at offset 0.1 after removing point at index 1.");

	curve->clear_points();
	CHECK_MESSAGE(
			curve->sample(0.6) == doctest::Approx(0),
			"Custom free curve should return the expected value at offset 0.6 after clearing all points.");
	CHECK_MESSAGE(
			curve->sample_baked(0.6) == doctest::Approx(0),
			"Custom free curve should return the expected baked value at offset 0.6 after clearing all points.");
}

TEST_CASE("[Curve] Custom non-unit curve with free tangents") {
	Ref<Curve> curve = memnew(Curve);
	curve->set_min_domain(-100.0);
	curve->set_max_domain(100.0);
	// "Sawtooth" curve with an open ending towards the 100 offset.
	curve->add_point(Vector2(-100, 0));
	curve->add_point(Vector2(-50, 1));
	curve->add_point(Vector2(0, 0));
	curve->add_point(Vector2(50, 1));
	curve->set_bake_resolution(11);

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_left_tangent(0)),
			"get_point_left_tangent() should return the expected value for point index 0.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_right_tangent(0)),
			"get_point_right_tangent() should return the expected value for point index 0.");
	CHECK_MESSAGE(
			curve->get_point_left_mode(0) == Curve::TangentMode::TANGENT_FREE,
			"get_point_left_mode() should return the expected value for point index 0.");
	CHECK_MESSAGE(
			curve->get_point_right_mode(0) == Curve::TangentMode::TANGENT_FREE,
			"get_point_right_mode() should return the expected value for point index 0.");

	CHECK_MESSAGE(
			curve->get_point_count() == 4,
			"Custom free curve should contain the expected number of points.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(-200)),
			"Custom free curve should return the expected value at offset -200.");
	CHECK_MESSAGE(
			curve->sample(0.1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 0.1.");
	CHECK_MESSAGE(
			curve->sample(0.4 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 0.4.");
	CHECK_MESSAGE(
			curve->sample(0.7 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.896),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 0.7.");
	CHECK_MESSAGE(
			curve->sample(1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 1.");
	CHECK_MESSAGE(
			curve->sample(2 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 2.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample_baked(-200)),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's -0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.4 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.352),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 0.4.");
	CHECK_MESSAGE(
			curve->sample_baked(0.7 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.896),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 0.7.");
	CHECK_MESSAGE(
			curve->sample_baked(1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 1.");
	CHECK_MESSAGE(
			curve->sample_baked(2 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 2.");

	curve->remove_point(1);
	CHECK_MESSAGE(
			curve->sample(0.1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(0),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 0.1 after removing point at index 1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(0),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 0.1 after removing point at index 1.");

	curve->clear_points();
	CHECK_MESSAGE(
			curve->sample(0.6 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(0),
			"Custom free curve should return the expected value at offset 0.6 after clearing all points.");
	CHECK_MESSAGE(
			curve->sample_baked(0.6 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(0),
			"Custom free curve should return the expected baked value at offset 0.6 after clearing all points.");
}

TEST_CASE("[Curve] Custom unit curve with linear tangents") {
	Ref<Curve> curve = memnew(Curve);
	// "Sawtooth" curve with an open ending towards the 1.0 offset.
	curve->add_point(Vector2(0, 0), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);
	curve->add_point(Vector2(0.25, 1), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);
	curve->add_point(Vector2(0.5, 0), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);
	curve->add_point(Vector2(0.75, 1), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);

	CHECK_MESSAGE(
			curve->get_point_left_tangent(3) == doctest::Approx(4),
			"get_point_left_tangent() should return the expected value for point index 3.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_right_tangent(3)),
			"get_point_right_tangent() should return the expected value for point index 3.");
	CHECK_MESSAGE(
			curve->get_point_left_mode(3) == Curve::TangentMode::TANGENT_LINEAR,
			"get_point_left_mode() should return the expected value for point index 3.");
	CHECK_MESSAGE(
			curve->get_point_right_mode(3) == Curve::TangentMode::TANGENT_LINEAR,
			"get_point_right_mode() should return the expected value for point index 3.");

	ERR_PRINT_OFF;
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_right_tangent(300)),
			"get_point_right_tangent() should return the expected value for invalid point index 300.");
	CHECK_MESSAGE(
			curve->get_point_left_mode(-12345) == Curve::TangentMode::TANGENT_FREE,
			"get_point_left_mode() should return the expected value for invalid point index -12345.");
	ERR_PRINT_ON;

	CHECK_MESSAGE(
			curve->get_point_count() == 4,
			"Custom linear curve should contain the expected number of points.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(-0.1)),
			"Custom linear curve should return the expected value at offset -0.1.");
	CHECK_MESSAGE(
			curve->sample(0.1) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected value at offset 0.1.");
	CHECK_MESSAGE(
			curve->sample(0.4) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected value at offset 0.4.");
	CHECK_MESSAGE(
			curve->sample(0.7) == doctest::Approx((real_t)0.8),
			"Custom linear curve should return the expected value at offset 0.7.");
	CHECK_MESSAGE(
			curve->sample(1) == doctest::Approx(1),
			"Custom linear curve should return the expected value at offset 1.0.");
	CHECK_MESSAGE(
			curve->sample(2) == doctest::Approx(1),
			"Custom linear curve should return the expected value at offset 2.0.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample_baked(-0.1)),
			"Custom linear curve should return the expected baked value at offset -0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.1) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected baked value at offset 0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.4) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected baked value at offset 0.4.");
	CHECK_MESSAGE(
			curve->sample_baked(0.7) == doctest::Approx((real_t)0.8),
			"Custom linear curve should return the expected baked value at offset 0.7.");
	CHECK_MESSAGE(
			curve->sample_baked(1) == doctest::Approx(1),
			"Custom linear curve should return the expected baked value at offset 1.0.");
	CHECK_MESSAGE(
			curve->sample_baked(2) == doctest::Approx(1),
			"Custom linear curve should return the expected baked value at offset 2.0.");

	ERR_PRINT_OFF;
	curve->remove_point(10);
	ERR_PRINT_ON;
	CHECK_MESSAGE(
			curve->sample(0.7) == doctest::Approx((real_t)0.8),
			"Custom free curve should return the expected value at offset 0.7 after removing point at invalid index 10.");
	CHECK_MESSAGE(
			curve->sample_baked(0.7) == doctest::Approx((real_t)0.8),
			"Custom free curve should return the expected baked value at offset 0.7 after removing point at invalid index 10.");
}

TEST_CASE("[Curve] Custom non-unit curve with linear tangents") {
	Ref<Curve> curve = memnew(Curve);
	curve->set_min_domain(-100.0);
	curve->set_max_domain(100.0);
	// "Sawtooth" curve with an open ending towards the 100 offset.
	curve->add_point(Vector2(-100, 0), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);
	curve->add_point(Vector2(-50, 1), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);
	curve->add_point(Vector2(0, 0), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);
	curve->add_point(Vector2(50, 1), 0, 0, Curve::TangentMode::TANGENT_LINEAR, Curve::TangentMode::TANGENT_LINEAR);

	CHECK_MESSAGE(
			curve->get_point_left_tangent(3) == doctest::Approx(1.f / 50),
			"get_point_left_tangent() should return the expected value for point index 3.");
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_right_tangent(3)),
			"get_point_right_tangent() should return the expected value for point index 3.");
	CHECK_MESSAGE(
			curve->get_point_left_mode(3) == Curve::TangentMode::TANGENT_LINEAR,
			"get_point_left_mode() should return the expected value for point index 3.");
	CHECK_MESSAGE(
			curve->get_point_right_mode(3) == Curve::TangentMode::TANGENT_LINEAR,
			"get_point_right_mode() should return the expected value for point index 3.");

	ERR_PRINT_OFF;
	CHECK_MESSAGE(
			Math::is_zero_approx(curve->get_point_right_tangent(300)),
			"get_point_right_tangent() should return the expected value for invalid point index 300.");
	CHECK_MESSAGE(
			curve->get_point_left_mode(-12345) == Curve::TangentMode::TANGENT_FREE,
			"get_point_left_mode() should return the expected value for invalid point index -12345.");
	ERR_PRINT_ON;

	CHECK_MESSAGE(
			curve->get_point_count() == 4,
			"Custom linear unit curve should contain the expected number of points.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample(-0.1 * curve->get_domain_range() + curve->get_min_domain())),
			"Custom linear curve should return the expected value at offset equivalent to a unit curve's -0.1.");
	CHECK_MESSAGE(
			curve->sample(0.1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected value at offset equivalent to a unit curve's 0.1.");
	CHECK_MESSAGE(
			curve->sample(0.4 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected value at offset equivalent to a unit curve's 0.4.");
	CHECK_MESSAGE(
			curve->sample(0.7 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.8),
			"Custom linear curve should return the expected value at offset equivalent to a unit curve's 0.7.");
	CHECK_MESSAGE(
			curve->sample(1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom linear curve should return the expected value at offset equivalent to a unit curve's 1.0.");
	CHECK_MESSAGE(
			curve->sample(2 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom linear curve should return the expected value at offset equivalent to a unit curve's 2.0.");

	CHECK_MESSAGE(
			Math::is_zero_approx(curve->sample_baked(-0.1 * curve->get_domain_range() + curve->get_min_domain())),
			"Custom linear curve should return the expected baked value at offset equivalent to a unit curve's -0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected baked value at offset equivalent to a unit curve's 0.1.");
	CHECK_MESSAGE(
			curve->sample_baked(0.4 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.4),
			"Custom linear curve should return the expected baked value at offset equivalent to a unit curve's 0.4.");
	CHECK_MESSAGE(
			curve->sample_baked(0.7 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.8),
			"Custom linear curve should return the expected baked value at offset equivalent to a unit curve's 0.7.");
	CHECK_MESSAGE(
			curve->sample_baked(1 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom linear curve should return the expected baked value at offset equivalent to a unit curve's 1.0.");
	CHECK_MESSAGE(
			curve->sample_baked(2 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx(1),
			"Custom linear curve should return the expected baked value at offset equivalent to a unit curve's 2.0.");

	ERR_PRINT_OFF;
	curve->remove_point(10);
	ERR_PRINT_ON;
	CHECK_MESSAGE(
			curve->sample(0.7 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.8),
			"Custom free curve should return the expected value at offset equivalent to a unit curve's 0.7 after removing point at invalid index 10.");
	CHECK_MESSAGE(
			curve->sample_baked(0.7 * curve->get_domain_range() + curve->get_min_domain()) == doctest::Approx((real_t)0.8),
			"Custom free curve should return the expected baked value at offset equivalent to a unit curve's 0.7 after removing point at invalid index 10.");
}

TEST_CASE("[Curve] Straight line offset test") {
	Ref<Curve> curve = memnew(Curve);
	curve->add_point(Vector2(0, 0));
	curve->add_point(Vector2(1, 1));

	CHECK_MESSAGE(
			curve->sample_baked(1.0 - (0.5 / curve->get_bake_resolution())) != curve->sample_baked(1),
			"Straight line curve should return different baked values at offset 1 vs offset (1 - 0.5 / bake resolution) .");
}

TEST_CASE("[Curve2D] Linear sampling should return exact value") {
	Ref<Curve2D> curve = memnew(Curve2D);
	real_t len = 2048.0;

	curve->add_point(Vector2(0, 0));
	curve->add_point(Vector2(len, 0));

	real_t baked_length = curve->get_baked_length();
	CHECK(len == baked_length);

	for (int i = 0; i < len; i++) {
		Vector2 pos = curve->sample_baked(i);
		CHECK_MESSAGE(Math::is_equal_approx(pos.x, i), "sample_baked should return exact value");
	}
}

TEST_CASE("[Curve3D] Linear sampling should return exact value") {
	Ref<Curve3D> curve = memnew(Curve3D);
	real_t len = 2048.0;

	curve->add_point(Vector3(0, 0, 0));
	curve->add_point(Vector3(len, 0, 0));
	ERR_PRINT_OFF
	real_t baked_length = curve->get_baked_length();
	ERR_PRINT_ON
	CHECK(len == baked_length);

	for (int i = 0; i < len; i++) {
		Vector3 pos = curve->sample_baked(i);
		CHECK_MESSAGE(Math::is_equal_approx(pos.x, i), "sample_baked should return exact value");
	}
}


TEST_CASE("[Curve] Hot-path index search preserves exact control values") {
	Ref<Curve> curve = memnew(Curve);
	// A longer curve exercises both halves of the binary search repeatedly.
	for (int i = 0; i <= 64; ++i) {
		const real_t value = ((i * 13) % 29) / (real_t)29;
		curve->add_point(Vector2(i / (real_t)64, value));
	}
	CHECK(curve->get_point_count() == 65);
	for (int i = 0; i <= 64; ++i) {
		const real_t value = ((i * 13) % 29) / (real_t)29;
		CHECK_MESSAGE(Math::is_equal_approx(curve->sample(i / (real_t)64), value),
				"Sampling a stored control-point position must return the exact control value.");
	}
	CHECK(Math::is_equal_approx(curve->sample(-5), curve->sample(0)));
	CHECK(Math::is_equal_approx(curve->sample(5), curve->sample(1)));
}

TEST_CASE("[Curve] Hot-path index search keeps single and empty curves safe") {
	Ref<Curve> curve = memnew(Curve);
	CHECK(curve->sample(0.5) == 0.0);
	curve->add_point(Vector2(0.5, 0.75));
	CHECK(Math::is_equal_approx(curve->sample(-2), (real_t)0.75));
	CHECK(Math::is_equal_approx(curve->sample(2), (real_t)0.75));
}


TEST_CASE("[Curve][Performance] Rebaking reuses the cache and overwrites all sample endpoints") {
	Ref<Curve> curve = memnew(Curve);
	curve->add_point(Vector2(0, 0));
	curve->add_point(Vector2(1, 1));
	curve->set_bake_resolution(257);

	for (int iteration = 0; iteration <= 100; iteration++) {
		const real_t last = iteration / real_t(100);
		curve->set_point_value(1, last);
		curve->bake();
		CHECK(Math::is_equal_approx(curve->sample_baked(0), (real_t)0));
		CHECK(Math::is_equal_approx(curve->sample_baked(1), last));
		CHECK(Math::is_equal_approx(curve->sample_baked(0.5), curve->sample(0.5)));
	}

	// Reusing memory must not expose old samples after all points are removed.
	curve->clear_points();
	curve->bake();
	CHECK(curve->sample_baked(0) == 0);
	CHECK(curve->sample_baked(0.5) == 0);
	CHECK(curve->sample_baked(1) == 0);

	// Resolution changes should still resize correctly, even when only one
	// baked element is requested and both endpoints alias the same slot.
	curve->add_point(Vector2(0, 0.25));
	curve->add_point(Vector2(1, 0.75));
	curve->set_bake_resolution(1);
	curve->bake();
	CHECK(Math::is_equal_approx(curve->sample_baked(0.5), (real_t)0.75));

	curve->set_bake_resolution(512);
	curve->bake();
	CHECK(Math::is_equal_approx(curve->sample_baked(0), (real_t)0.25));
	CHECK(Math::is_equal_approx(curve->sample_baked(1), (real_t)0.75));
}


TEST_CASE("[Curve] Monotone baking matches direct sampling over hundreds of points") {
	Ref<Curve> curve = memnew(Curve);
	curve->set_bake_resolution(1000);
	for (int i = 0; i <= 256; i++) {
		const real_t x = real_t(i) / 256.0;
		const real_t y = real_t((i * 73) % 257) / 257.0;
		curve->add_point(Vector2(x, y), -real_t(i % 5) / 7.0, real_t(i % 7) / 11.0);
	}
	curve->bake();
	for (int i = 1; i < 999; i++) {
		const real_t x = curve->get_domain_range() * i / real_t(999) + curve->get_min_domain();
		CHECK(curve->sample_baked(x) == doctest::Approx(curve->sample(x)).epsilon(0.0001));
	}

	// Rebaking reuses the cache and must still produce current samples.
	curve->set_point_value(128, real_t(0.75));
	curve->bake();
	for (int i = 1; i < 999; i += 7) {
		const real_t x = curve->get_domain_range() * i / real_t(999) + curve->get_min_domain();
		CHECK(curve->sample_baked(x) == doctest::Approx(curve->sample(x)).epsilon(0.0001));
	}
}

TEST_CASE("[Curve] Monotone baking preserves overlapping control points") {
	Ref<Curve> curve = memnew(Curve);
	curve->add_point(Vector2(0, 0.1));
	curve->add_point(Vector2(0.5, 0.4));
	curve->add_point(Vector2(0.5, 0.6));
	curve->add_point(Vector2(1, 0.9));
	curve->set_bake_resolution(101);
	curve->bake();
	for (int i = 1; i < 100; i++) {
		const real_t x = real_t(i) / 100.0;
		CHECK(curve->sample_baked(x) == doctest::Approx(curve->sample(x)).epsilon(0.0001));
	}
}

TEST_CASE("[Curve][Performance] Linear tangents reuse direct segment slope") {
	Ref<Curve> curve = memnew(Curve);
	constexpr int COUNT = 128;
	for (int i = 0; i < COUNT; ++i) {
		const real_t x = real_t(i) / real_t(COUNT - 1);
		const real_t y = real_t((i * 47) % COUNT) / real_t(COUNT);
		curve->add_point(Vector2(x, y), 0, 0, Curve::TANGENT_LINEAR, Curve::TANGENT_LINEAR);
	}
	REQUIRE(curve->get_point_count() == COUNT);
	for (int i = 1; i < COUNT; ++i) {
		const Vector2 a = curve->get_point_position(i - 1);
		const Vector2 b = curve->get_point_position(i);
		const real_t expected_slope = (b.y - a.y) / (b.x - a.x);
		CHECK(curve->get_point_right_tangent(i - 1) == doctest::Approx(expected_slope).epsilon(0.0001));
		CHECK(curve->get_point_left_tangent(i) == doctest::Approx(expected_slope).epsilon(0.0001));
	}
	curve->set_point_value(63, 0.25);
	for (int i = 63; i <= 64; ++i) {
		const Vector2 a = curve->get_point_position(i - 1);
		const Vector2 b = curve->get_point_position(i);
		CHECK(curve->get_point_left_tangent(i) == doctest::Approx((b.y - a.y) / (b.x - a.x)).epsilon(0.0001));
	}
}


TEST_CASE("[Curve] Cleaning duplicates retains strictly increasing points") {
	Ref<Curve> curve = memnew(Curve);
	for (int i = 0; i <= 128; i++) {
		const real_t x = real_t(i) / real_t(128);
		curve->add_point(Vector2(x, real_t(i % 7) / real_t(7)));
	}

	curve->clean_dupes();
	REQUIRE(curve->get_point_count() == 129);
	for (int i = 0; i <= 128; i++) {
		CHECK(curve->get_point_position(i).x == doctest::Approx(real_t(i) / real_t(128)));
	}
	// Normalized clean curves should remain stable across repeated calls.
	curve->clean_dupes();
	CHECK(curve->get_point_count() == 129);
}

TEST_CASE("[Curve] Cleaning thousands of duplicate points preserves first values") {
	Ref<Curve> curve = memnew(Curve);
	const int unique_count = 2048;
	Array packed_points;
	packed_points.resize(unique_count * 2 * 5);
	for (int i = 0; i < unique_count; i++) {
		const real_t x = real_t(i) / real_t(2048);
		for (int duplicate = 0; duplicate < 2; duplicate++) {
			const int offset = (i * 2 + duplicate) * 5;
			packed_points[offset] = Vector2(x, duplicate ? real_t(0.75) : real_t(0.25));
			packed_points[offset + 1] = 0.0;
			packed_points[offset + 2] = 0.0;
			packed_points[offset + 3] = int(Curve::TANGENT_FREE);
			packed_points[offset + 4] = int(Curve::TANGENT_FREE);
		}
	}
	curve->set_data(packed_points);
	REQUIRE(curve->get_point_count() == unique_count * 2);
	curve->clean_dupes();
	REQUIRE(curve->get_point_count() == unique_count);
	for (int i = 0; i < unique_count; i++) {
		const Vector2 point = curve->get_point_position(i);
		CHECK(point.x == doctest::Approx(real_t(i) / real_t(2048)));
		CHECK(point.y == doctest::Approx(real_t(0.25)));
	}
	curve->clean_dupes();
	CHECK(curve->get_point_count() == unique_count);
}

} // namespace TestCurve
