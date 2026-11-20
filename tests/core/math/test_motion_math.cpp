/**************************************************************************/
/*  test_motion_math.cpp                                                  */
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

TEST_FORCE_LINK(test_motion_math)

#include "core/math/sampling.h"
#include "core/math/spring_damper.h"
#include "core/variant/variant_utility.h"

namespace TestMotionMath {

TEST_CASE("[SpringDamper] Critically damped spring converges without overshoot") {
	Ref<SpringDamper> spring = memnew(SpringDamper);
	spring->set_frequency(2.0);
	spring->set_damping_ratio(1.0);
	real_t value = 0.0;
	real_t previous = 0.0;
	for (int i = 0; i < 300; i++) {
		value = spring->step(value, 10.0, 1.0 / 60.0);
		CHECK(value <= 10.0 + CMP_EPSILON);
		CHECK(value >= previous - CMP_EPSILON);
		previous = value;
	}
	CHECK(value == doctest::Approx(10.0).epsilon(0.001));
}

TEST_CASE("[SpringDamper] Under-damped spring overshoots then settles") {
	Ref<SpringDamper> spring = memnew(SpringDamper);
	spring->set_frequency(3.0);
	spring->set_damping_ratio(0.2);
	real_t value = 0.0;
	real_t peak = 0.0;
	for (int i = 0; i < 600; i++) {
		value = spring->step(value, 1.0, 1.0 / 60.0);
		peak = MAX(peak, value);
	}
	CHECK(peak > 1.1);
	CHECK(value == doctest::Approx(1.0).epsilon(0.01));
}

TEST_CASE("[SpringDamper] Result is frame-rate independent") {
	Ref<SpringDamper> a = memnew(SpringDamper);
	Ref<SpringDamper> b = memnew(SpringDamper);
	for (Ref<SpringDamper> s : { a, b }) {
		s->set_frequency(1.5);
		s->set_damping_ratio(0.6);
	}
	Vector3 va;
	Vector3 vb;
	const Vector3 target(4, -2, 1);
	for (int i = 0; i < 30; i++) {
		va = a->step(va, target, 1.0 / 30.0);
	}
	for (int i = 0; i < 240; i++) {
		vb = b->step(vb, target, 1.0 / 240.0);
	}
	CHECK(va.is_equal_approx(vb));
}

TEST_CASE("[SpringDamper] Over-damped and impulse") {
	Ref<SpringDamper> spring = memnew(SpringDamper);
	spring->set_frequency(2.0);
	spring->set_damping_ratio(2.0);
	real_t value = spring->step(0.0, 1.0, 0.5);
	CHECK(value > 0.0);
	CHECK(value < 1.0);
	spring->reset();
	spring->add_impulse(5.0);
	value = spring->step(0.0, 0.0, 0.05);
	CHECK(value > 0.0);
}

TEST_CASE("[PIDController] Drives a simple plant to the target") {
	Ref<PIDController> pid = memnew(PIDController);
	pid->set_proportional_gain(4.0);
	pid->set_integral_gain(1.0);
	pid->set_derivative_gain(1.0);
	real_t position = 0.0;
	real_t velocity = 0.0;
	const real_t dt = 1.0 / 60.0;
	for (int i = 0; i < 60 * 20; i++) {
		const real_t force = pid->step(position, 5.0, dt) - 1.0; // Constant disturbance.
		velocity += force * dt;
		position += velocity * dt;
	}
	CHECK(position == doctest::Approx(5.0).epsilon(0.02));
}

TEST_CASE("[PIDController] Limits clamp integral and output") {
	Ref<PIDController> pid = memnew(PIDController);
	pid->set_proportional_gain(100.0);
	pid->set_integral_gain(1.0);
	pid->set_integral_limit(2.0);
	pid->set_output_limit(10.0);
	for (int i = 0; i < 100; i++) {
		CHECK(Math::abs(pid->step(0.0, 50.0, 0.1)) <= 10.0 + CMP_EPSILON);
	}
	CHECK(pid->get_integral() == doctest::Approx(2.0));
	pid->reset();
	CHECK(pid->get_integral() == doctest::Approx(0.0));
}

TEST_CASE("[Sampling] Halton sequence") {
	CHECK(Sampling::halton(1, 2) == doctest::Approx(0.5));
	CHECK(Sampling::halton(2, 2) == doctest::Approx(0.25));
	CHECK(Sampling::halton(3, 2) == doctest::Approx(0.75));
	CHECK(Sampling::halton(1, 3) == doctest::Approx(1.0 / 3.0));
	const PackedVector2Array pts = Sampling::halton_2d(16);
	CHECK(pts.size() == 16);
	for (const Vector2 &p : pts) {
		CHECK(p.x >= 0.0);
		CHECK(p.x < 1.0);
		CHECK(p.y >= 0.0);
		CHECK(p.y < 1.0);
	}
}

TEST_CASE("[Sampling] Poisson disk keeps minimum distance and is deterministic") {
	const Vector2 size(50, 30);
	const real_t radius = 3.0;
	const PackedVector2Array a = Sampling::poisson_disk_2d(size, radius, 42);
	const PackedVector2Array b = Sampling::poisson_disk_2d(size, radius, 42);
	CHECK(a.size() > 50);
	CHECK(a == b);
	for (int i = 0; i < a.size(); i++) {
		CHECK(a[i].x >= 0.0);
		CHECK(a[i].y >= 0.0);
		CHECK(a[i].x < size.x);
		CHECK(a[i].y < size.y);
		for (int j = i + 1; j < a.size(); j++) {
			CHECK(a[i].distance_to(a[j]) >= radius - CMP_EPSILON);
		}
	}
	CHECK(Sampling::poisson_disk_2d(size, radius, 43) != a);
	CHECK(Sampling::poisson_disk_2d(size, radius, 42, 30, 10).size() == 10);
}

TEST_CASE("[VariantUtility] damp, damp_angle and remap_clamped") {
	CHECK(VariantUtilityFunctions::remap_clamped(150, 0, 100, 0, 1) == doctest::Approx(1.0));
	CHECK(VariantUtilityFunctions::remap_clamped(-5, 0, 100, 0, 1) == doctest::Approx(0.0));
	CHECK(VariantUtilityFunctions::remap_clamped(25, 0, 100, 10, 20) == doctest::Approx(12.5));
	CHECK(VariantUtilityFunctions::remap_clamped(25, 100, 0, 0, 1) == doctest::Approx(0.75));

	// Frame-rate independence: two half steps equal one full step.
	const double one = VariantUtilityFunctions::damp(0.0, 10.0, 5.0, 0.2);
	const double half = VariantUtilityFunctions::damp(VariantUtilityFunctions::damp(0.0, 10.0, 5.0, 0.1), 10.0, 5.0, 0.1);
	CHECK(one == doctest::Approx(half));
	CHECK(VariantUtilityFunctions::damp(3.0, 10.0, 5.0, 0.0) == doctest::Approx(3.0));

	const double angle = VariantUtilityFunctions::damp_angle(Math::deg_to_rad(170.0), Math::deg_to_rad(-170.0), 100.0, 1.0);
	CHECK(Math::abs(Math::angle_difference(angle, Math::deg_to_rad(-170.0))) < 0.001);
}

} // namespace TestMotionMath
