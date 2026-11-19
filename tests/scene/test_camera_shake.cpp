/**************************************************************************/
/*  test_camera_shake.cpp                                                 */
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

TEST_FORCE_LINK(test_camera_shake)

#include "scene/2d/camera_2d.h"
#include "scene/3d/camera_3d.h"
#include "scene/main/camera_shake.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"
#include "scene/main/window.h"

namespace TestCameraShake {

TEST_CASE("[CameraShake] Trauma is clamped and decays linearly") {
	CameraShake shake;
	shake.add_trauma(0.4);
	shake.add_trauma(0.4);
	CHECK(shake.trauma == doctest::Approx(0.8));
	shake.add_trauma(5.0);
	CHECK(shake.trauma == doctest::Approx(1.0));
	shake.add_trauma(-5.0);
	CHECK(shake.trauma == doctest::Approx(0.0));
	shake.set_trauma(Math::NaN);
	CHECK(shake.trauma == doctest::Approx(0.0));

	shake.set_trauma(1.0);
	CHECK(shake.advance(0.25, 2.0, 25.0)); // 1.0 - 2.0 * 0.25 = 0.5
	CHECK(shake.trauma == doctest::Approx(0.5));
	CHECK(shake.phase == doctest::Approx(0.25 * 25.0));
	CHECK_FALSE(shake.advance(1.0, 2.0, 25.0));
	CHECK(shake.trauma == doctest::Approx(0.0));
	// With no trauma, time stops and nothing is sampled.
	const double phase = shake.phase;
	CHECK_FALSE(shake.advance(1.0, 2.0, 25.0));
	CHECK(shake.phase == doctest::Approx(phase));
	CHECK(shake.get_intensity(2.0) == doctest::Approx(0.0));

	// Zero or negative delta never changes the state.
	shake.set_trauma(0.7);
	shake.advance(0.0, 2.0, 25.0);
	shake.advance(-1.0, 2.0, 25.0);
	CHECK(shake.trauma == doctest::Approx(0.7));
}

TEST_CASE("[CameraShake] Intensity follows trauma to the given power") {
	CameraShake shake;
	shake.set_trauma(0.5);
	CHECK(shake.get_intensity(1.0) == doctest::Approx(0.5));
	CHECK(shake.get_intensity(2.0) == doctest::Approx(0.25));
	CHECK(shake.get_intensity(0.0) == doctest::Approx(1.0));
	CHECK(shake.get_intensity(-3.0) == doctest::Approx(1.0)); // Negative exponents are clamped.
}

TEST_CASE("[CameraShake] Noise is bounded, smooth and deterministic") {
	real_t previous = CameraShake::noise(0.0, 0);
	real_t largest_step = 0.0;
	real_t minimum = 1.0;
	real_t maximum = -1.0;
	for (int i = 1; i <= 20000; i++) {
		const double x = double(i) * 0.01;
		const real_t value = CameraShake::noise(x, 0);
		CHECK(value >= real_t(-1.0));
		CHECK(value <= real_t(1.0));
		largest_step = MAX(largest_step, Math::abs(value - previous));
		minimum = MIN(minimum, value);
		maximum = MAX(maximum, value);
		previous = value;
	}
	CHECK(largest_step < real_t(0.06)); // Smooth: no jumps between 0.01 time steps.
	CHECK(minimum < real_t(-0.7)); // And it actually uses the range.
	CHECK(maximum > real_t(0.7));

	CHECK(CameraShake::noise(3.7, 2) == CameraShake::noise(3.7, 2));
	// Channels are independent streams.
	int different = 0;
	for (int i = 0; i < 100; i++) {
		if (!Math::is_equal_approx(CameraShake::noise(double(i) * 0.37, 0), CameraShake::noise(double(i) * 0.37, 1))) {
			different++;
		}
	}
	CHECK(different > 90);
	// Negative time works too.
	CHECK(Math::abs(CameraShake::noise(-12.3, 4)) <= real_t(1.0));
	// The noise is continuous across lattice points.
	CHECK(CameraShake::noise(5.0 - 1e-9, 1) == doctest::Approx(CameraShake::noise(5.0 + 1e-9, 1)).epsilon(0.001));
}

TEST_CASE("[SceneTree][Camera2D] Trauma shakes the view and fades out") {
	Camera2D *camera = memnew(Camera2D);
	SceneTree::get_singleton()->get_root()->add_child(camera);
	camera->make_current();
	camera->set_shake_max_offset(Vector2(20, 10));
	camera->set_shake_decay(2.0);

	// No trauma: no shake and the transform is the plain camera transform.
	SceneTree::get_singleton()->process(0.016);
	CHECK(camera->get_shake_offset() == Vector2());
	const Transform2D rest = camera->get_viewport()->get_canvas_transform();

	camera->add_trauma(1.0);
	CHECK(camera->get_trauma() == doctest::Approx(1.0));
	real_t largest = 0.0;
	bool moved = false;
	for (int i = 0; i < 20; i++) {
		SceneTree::get_singleton()->process(0.016);
		const Vector2 offset = camera->get_shake_offset();
		CHECK(Math::abs(offset.x) <= real_t(20.0) + real_t(1e-3));
		CHECK(Math::abs(offset.y) <= real_t(10.0) + real_t(1e-3));
		largest = MAX(largest, offset.length());
		if (!camera->get_viewport()->get_canvas_transform().is_equal_approx(rest)) {
			moved = true;
		}
	}
	CHECK(moved);
	CHECK(largest > real_t(1.0));
	CHECK(camera->get_trauma() < real_t(1.0));

	// Trauma 1 at decay 2 lasts half a second; run well past it.
	for (int i = 0; i < 60; i++) {
		SceneTree::get_singleton()->process(0.016);
	}
	CHECK(camera->get_trauma() == doctest::Approx(0.0));
	CHECK(camera->get_shake_offset() == Vector2());
	CHECK(camera->get_shake_rotation() == doctest::Approx(0.0));
	CHECK(camera->get_viewport()->get_canvas_transform().is_equal_approx(rest));

	// Setting trauma to zero stops the shake immediately.
	camera->set_trauma(0.8);
	SceneTree::get_singleton()->process(0.016);
	CHECK(camera->get_shake_offset() != Vector2());
	camera->set_trauma(0.0);
	CHECK(camera->get_shake_offset() == Vector2());

	memdelete(camera);
}

TEST_CASE("[SceneTree][Camera2D] Shake scales with zoom like other offsets") {
	Camera2D *camera = memnew(Camera2D);
	SceneTree::get_singleton()->get_root()->add_child(camera);
	camera->make_current();
	camera->set_shake_max_offset(Vector2(10, 10));
	camera->set_shake_max_rotation(0.0);
	camera->set_zoom(Vector2(2, 2));
	camera->add_trauma(1.0);
	SceneTree::get_singleton()->process(0.016);
	const Vector2 offset = camera->get_shake_offset();
	CHECK(offset != Vector2());
	// The view origin moves by the pixel offset divided by the zoom.
	const Transform2D shaken = camera->get_viewport()->get_canvas_transform();
	camera->set_trauma(0.0);
	SceneTree::get_singleton()->process(0.016);
	const Transform2D rest = camera->get_viewport()->get_canvas_transform();
	const Vector2 world_shift = rest.affine_inverse().get_origin() - shaken.affine_inverse().get_origin();
	CHECK(world_shift.length() == doctest::Approx((offset * real_t(0.5)).length()).epsilon(0.01));
	memdelete(camera);
}

TEST_CASE("[SceneTree][Camera2D] Shake rotation pivots around the center of the view") {
	Camera2D *camera = memnew(Camera2D);
	SceneTree::get_singleton()->get_root()->add_child(camera);
	camera->set_global_position(Vector2(100, 100));
	camera->make_current();
	camera->set_shake_max_offset(Vector2());
	camera->set_shake_max_rotation(0.4);
	camera->add_trauma(1.0);

	bool rotated = false;
	for (int i = 0; i < 10; i++) {
		SceneTree::get_singleton()->process(0.016);
		const Transform2D canvas = camera->get_viewport()->get_canvas_transform();
		const Vector2 center = camera->get_viewport()->get_visible_rect().size * 0.5;
		// Whatever the roll, the camera position stays exactly under the middle of the screen.
		CHECK(canvas.affine_inverse().xform(center).is_equal_approx(Vector2(100, 100)));
		if (Math::abs(camera->get_shake_rotation()) > real_t(0.01)) {
			rotated = true;
		}
	}
	CHECK(rotated);
	memdelete(camera);
}

TEST_CASE("[SceneTree][Camera3D] Trauma shakes the rendered view only") {
	Camera3D *camera = memnew(Camera3D);
	SceneTree::get_singleton()->get_root()->add_child(camera);
	camera->set_global_transform(Transform3D(Basis(), Vector3(1, 2, 3)));
	camera->set_shake_max_offset(Vector3(0.5, 0.5, 0.5));
	camera->set_shake_decay(2.0);

	SceneTree::get_singleton()->process(0.016);
	const Transform3D rest = camera->get_camera_transform();
	CHECK(rest.origin.is_equal_approx(Vector3(1, 2, 3)));

	camera->add_trauma(1.0);
	bool moved = false;
	for (int i = 0; i < 20; i++) {
		SceneTree::get_singleton()->process(0.016);
		const Vector3 translation = camera->get_shake_translation();
		CHECK(Math::abs(translation.x) <= real_t(0.5) + real_t(1e-4));
		CHECK(Math::abs(translation.y) <= real_t(0.5) + real_t(1e-4));
		CHECK(Math::abs(translation.z) <= real_t(0.5) + real_t(1e-4));
		if (!camera->get_camera_transform().origin.is_equal_approx(rest.origin) || !camera->get_camera_transform().basis.is_equal_approx(rest.basis)) {
			moved = true;
		}
	}
	CHECK(moved);
	// The node itself is untouched; only the camera view is shaken.
	CHECK(camera->get_global_transform().origin.is_equal_approx(Vector3(1, 2, 3)));
	CHECK(camera->get_global_transform().basis.is_equal_approx(Basis()));
	CHECK(camera->get_camera_transform().basis.is_orthonormal());

	for (int i = 0; i < 60; i++) {
		SceneTree::get_singleton()->process(0.016);
	}
	CHECK(camera->get_trauma() == doctest::Approx(0.0));
	CHECK(camera->get_shake_translation() == Vector3());
	CHECK(camera->get_shake_rotation() == Vector3());
	CHECK(camera->get_camera_transform().origin.is_equal_approx(rest.origin));
	CHECK(camera->get_camera_transform().basis.is_equal_approx(rest.basis));

	memdelete(camera);
}

} // namespace TestCameraShake
