/**************************************************************************/
/*  test_smooth_damp.cpp                                                  */
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

TEST_FORCE_LINK(test_smooth_damp)

#include "core/math/random_number_generator.h"
#include "core/math/smooth_damp.h"

namespace TestSmoothDamp {

TEST_CASE("[SmoothDamp] Scalar converges monotonically without overshooting") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->set_smooth_time(0.3);
	real_t value = 0.0;
	real_t previous = value;
	for (int i = 0; i < 600; i++) {
		value = damper->step(value, real_t(10.0), real_t(1.0 / 60.0));
		CHECK(value >= previous - real_t(1e-6)); // Never moves backward.
		CHECK(value <= real_t(10.0) + real_t(1e-6)); // Never overshoots.
		previous = value;
	}
	CHECK(value == doctest::Approx(10.0).epsilon(0.001));
}

TEST_CASE("[SmoothDamp] Reaches most of the distance within a few smooth times") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->set_smooth_time(0.5);
	real_t value = 0.0;
	for (int i = 0; i < 60; i++) { // One second = two smooth times.
		value = damper->step(value, real_t(1.0), real_t(1.0 / 60.0));
	}
	CHECK(value > real_t(0.85));
	CHECK(value < real_t(1.0));
}

TEST_CASE("[SmoothDamp] Result is nearly independent of the frame rate") {
	real_t results[3];
	const int frame_rates[3] = { 30, 60, 240 };
	for (int r = 0; r < 3; r++) {
		Ref<SmoothDamp> damper = memnew(SmoothDamp);
		damper->set_smooth_time(0.4);
		real_t value = 0.0;
		const real_t delta = real_t(1.0) / real_t(frame_rates[r]);
		for (int i = 0; i < frame_rates[r] / 2; i++) { // Half a second of simulated time.
			value = damper->step(value, real_t(5.0), delta);
		}
		results[r] = value;
	}
	CHECK(results[0] == doctest::Approx(results[2]).epsilon(0.05));
	CHECK(results[1] == doctest::Approx(results[2]).epsilon(0.03));
}

TEST_CASE("[SmoothDamp] Max speed limits the approach") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->set_smooth_time(0.1);
	damper->set_max_speed(2.0);
	real_t value = 0.0;
	real_t highest_step = 0.0;
	for (int i = 0; i < 60; i++) {
		const real_t next = damper->step(value, real_t(100.0), real_t(1.0 / 60.0));
		highest_step = MAX(highest_step, (next - value) * real_t(60.0));
		value = next;
	}
	CHECK(highest_step <= real_t(2.0) * real_t(1.05));
	CHECK(value > real_t(1.0)); // It still makes progress.
	CHECK(value < real_t(3.0));
}

TEST_CASE("[SmoothDamp] Vectors follow a moving target and keep their own velocity") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->set_smooth_time(0.2);
	Vector3 position;
	Vector3 target;
	for (int i = 0; i < 300; i++) {
		target = Vector3(real_t(i) * real_t(0.05), 0.0, 3.0);
		position = damper->step(position, target, real_t(1.0 / 60.0));
	}
	const Vector3 velocity = damper->get_velocity();
	CHECK(velocity.x == doctest::Approx(3.0).epsilon(0.05)); // Target moves 0.05 per frame = 3 per second.
	// It trails behind the moving target by roughly velocity * smooth time.
	CHECK(target.x - position.x > real_t(0.3));
	CHECK(target.x - position.x < real_t(1.2));
	CHECK(position.z == doctest::Approx(3.0).epsilon(0.01));

	Ref<SmoothDamp> d2 = memnew(SmoothDamp);
	Vector2 p2 = d2->step(Vector2(), Vector2(4.0, 3.0), real_t(0.1));
	CHECK(p2.length() > real_t(0.0));
	CHECK(Variant(d2->get_velocity()).get_type() == Variant::VECTOR2);
	Vector4 p4 = d2->step(Vector4(), Vector4(1, 2, 3, 4), real_t(0.1)); // Type change resets velocity.
	CHECK(p4.length() > real_t(0.0));
	CHECK(Variant(d2->get_velocity()).get_type() == Variant::VECTOR4);
}

TEST_CASE("[SmoothDamp] Angles take the shortest way around the circle") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->set_smooth_time(0.2);
	real_t angle = Math::deg_to_rad(real_t(350.0));
	const real_t target = Math::deg_to_rad(real_t(10.0));
	real_t crossed_zero = false;
	for (int i = 0; i < 120; i++) {
		angle = damper->step_angle(angle, target, real_t(1.0 / 60.0));
		if (angle > Math::deg_to_rad(real_t(360.0))) {
			crossed_zero = true; // It moved up through 360 rather than back down through 180.
		}
	}
	CHECK(crossed_zero);
	CHECK(Math::angle_difference(double(angle), double(target)) == doctest::Approx(0.0).epsilon(0.01));
}

TEST_CASE("[SmoothDamp] Reset, zero delta and invalid input") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->step(real_t(0.0), real_t(10.0), real_t(0.1));
	CHECK(real_t(damper->get_velocity()) > real_t(0.0));
	damper->reset();
	CHECK(damper->get_velocity().get_type() == Variant::NIL);

	CHECK(real_t(damper->step(real_t(3.0), real_t(9.0), real_t(0.0))) == doctest::Approx(3.0));
	CHECK(real_t(damper->step(real_t(3.0), real_t(9.0), real_t(-1.0))) == doctest::Approx(3.0));

	// Integers are smoothed as floats.
	CHECK(real_t(damper->step(0, 100, real_t(0.1))) > real_t(0.0));

	ERR_PRINT_OFF;
	CHECK(damper->step(String("a"), String("b"), real_t(0.1)) == Variant(String("a")));
	CHECK(damper->step(Vector2(), Vector3(), real_t(0.1)) == Variant(Vector2()));
	ERR_PRINT_ON;
}

TEST_CASE("[SmoothDamp] Smooth time is clamped away from zero") {
	Ref<SmoothDamp> damper = memnew(SmoothDamp);
	damper->set_smooth_time(0.0);
	CHECK(damper->get_smooth_time() > real_t(0.0));
	const real_t value = damper->step(real_t(0.0), real_t(1.0), real_t(1.0 / 60.0));
	CHECK(Math::is_finite(value));
	CHECK(value <= real_t(1.0));
}

TEST_CASE("[RandomNumberGenerator] Unit circle and sphere helpers") {
	Ref<RandomNumberGenerator> rng = memnew(RandomNumberGenerator);
	rng->set_seed(1234);

	Vector2 centroid_2d;
	int inner_half_2d = 0;
	const int samples = 20000;
	for (int i = 0; i < samples; i++) {
		const Vector2 inside = rng->rand_in_circle(2.0);
		CHECK(inside.length() <= real_t(2.0) + real_t(1e-4));
		centroid_2d += inside;
		// Uniform over the area: a quarter of the points fall within half the radius.
		if (inside.length() < real_t(1.0)) {
			inner_half_2d++;
		}
		CHECK(rng->rand_on_circle(3.0).length() == doctest::Approx(3.0));
	}
	CHECK(centroid_2d.length() / samples < real_t(0.05));
	CHECK(real_t(inner_half_2d) / samples == doctest::Approx(0.25).epsilon(0.05));

	Vector3 centroid_3d;
	int inner_half_3d = 0;
	for (int i = 0; i < samples; i++) {
		const Vector3 inside = rng->rand_in_sphere(2.0);
		CHECK(inside.length() <= real_t(2.0) + real_t(1e-4));
		centroid_3d += inside;
		// Uniform over the volume: an eighth of the points fall within half the radius.
		if (inside.length() < real_t(1.0)) {
			inner_half_3d++;
		}
		const Vector3 on = rng->rand_on_sphere(4.0);
		CHECK(on.length() == doctest::Approx(4.0));
	}
	CHECK(centroid_3d.length() / samples < real_t(0.05));
	CHECK(real_t(inner_half_3d) / samples == doctest::Approx(0.125).epsilon(0.08));

	// Defaults are unit radius.
	CHECK(rng->rand_on_sphere().length() == doctest::Approx(1.0));
	CHECK(rng->rand_on_circle().length() == doctest::Approx(1.0));
}

TEST_CASE("[RandomNumberGenerator] Uniform random rotation and HSV color") {
	Ref<RandomNumberGenerator> rng = memnew(RandomNumberGenerator);
	rng->set_seed(99);

	// A uniform orientation sends a fixed axis to a uniformly distributed direction, so the mean
	// of the rotated vectors is ~0 and every rotation is a valid unit quaternion.
	Vector3 mean;
	const int samples = 20000;
	for (int i = 0; i < samples; i++) {
		const Quaternion q = rng->rand_rotation();
		CHECK(q.is_normalized());
		mean += q.xform(Vector3(0, 0, 1));
	}
	CHECK(mean.length() / samples < real_t(0.05));

	for (int i = 0; i < 200; i++) {
		const Color c = rng->rand_color_hsv(0.0, 0.1, 0.5, 0.6, 0.7, 0.8, 0.5, 0.5);
		CHECK(c.get_h() <= real_t(0.1) + real_t(0.001));
		CHECK(c.get_s() >= real_t(0.5) - real_t(0.001));
		CHECK(c.get_s() <= real_t(0.6) + real_t(0.001));
		CHECK(c.get_v() >= real_t(0.7) - real_t(0.001));
		CHECK(c.get_v() <= real_t(0.8) + real_t(0.001));
		CHECK(c.a == doctest::Approx(0.5));
	}
}

} // namespace TestSmoothDamp
