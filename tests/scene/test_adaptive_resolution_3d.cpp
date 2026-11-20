/**************************************************************************/
/*  test_adaptive_resolution_3d.cpp                                       */
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
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_adaptive_resolution_3d)

#ifndef _3D_DISABLED

#include "core/math/math_funcs.h"
#include "scene/3d/adaptive_resolution_3d.h"

namespace TestAdaptiveResolution3D {

TEST_CASE("[SceneTree][AdaptiveResolution3D] GPU-budget scaling") {
	constexpr float min_scale = 0.67f;
	constexpr float max_scale = 1.0f;
	constexpr float step_down = 0.05f;
	constexpr float step_up = 0.025f;
	constexpr double target_ms = 15.0;

	SUBCASE("Sustained GPU overload lowers 3D scale by bounded steps") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				1.0f, 21.0, target_ms, min_scale, max_scale, step_down, step_up), 0.95f));
	}

	SUBCASE("GPU headroom restores scale more slowly") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				0.8f, 8.0, target_ms, min_scale, max_scale, step_down, step_up), 0.825f));
	}

	SUBCASE("Hysteresis holds scale near GPU budget") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				0.8f, 15.1, target_ms, min_scale, max_scale, step_down, step_up), 0.8f));
	}

	SUBCASE("Resolution never drops below minimum") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				0.68f, 30.0, target_ms, min_scale, max_scale, step_down, step_up), min_scale));
	}

	SUBCASE("Resolution never exceeds maximum") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				0.99f, 5.0, target_ms, min_scale, max_scale, step_down, step_up), max_scale));
	}

	SUBCASE("Unmeasurable GPU time does not reduce resolution") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				1.0f, 0.0, target_ms, min_scale, max_scale, step_down, step_up), 1.0f));
	}

	SUBCASE("Invalid scale ordering is handled") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				1.2f, 20.0, target_ms, 1.0f, 0.67f, step_down, step_up), 0.95f));
	}

	SUBCASE("Negative steps cannot reverse adjustment direction") {
		CHECK(Math::is_equal_approx(AdaptiveResolution3D::calculate_next_scale(
				0.8f, 20.0, target_ms, min_scale, max_scale, -0.05f, step_up), 0.8f));
	}
}

} // namespace TestAdaptiveResolution3D

#endif // _3D_DISABLED
