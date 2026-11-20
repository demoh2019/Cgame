/**************************************************************************/
/*  test_native_lens_and_flicker.cpp                                      */
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
/* the above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_native_lens_and_flicker)

#ifndef _3D_DISABLED

#include "scene/3d/light_3d.h"
#include "scene/resources/environment.h"

namespace TestNativeLensAndFlicker {

TEST_CASE("[SceneTree][Environment] Lens vignette and white balance are clamped and stored") {
	Ref<Environment> environment;
	environment.instantiate();
	CHECK(environment->get_lens_vignette() == 0.0f);
	CHECK(environment->get_lens_white_temperature() == 0.0f);
	CHECK(environment->get_lens_white_tint() == 0.0f);

	environment->set_lens_vignette(0.45f);
	CHECK(environment->get_lens_vignette() == doctest::Approx(0.45f));
	environment->set_lens_vignette(3.0f);
	CHECK(environment->get_lens_vignette() == 1.0f);
	environment->set_lens_vignette(-1.0f);
	CHECK(environment->get_lens_vignette() == 0.0f);

	environment->set_lens_white_temperature(0.3f);
	environment->set_lens_white_tint(-0.2f);
	CHECK(environment->get_lens_white_temperature() == doctest::Approx(0.3f));
	CHECK(environment->get_lens_white_tint() == doctest::Approx(-0.2f));
	environment->set_lens_white_temperature(5.0f);
	environment->set_lens_white_tint(-5.0f);
	CHECK(environment->get_lens_white_temperature() == 1.0f);
	CHECK(environment->get_lens_white_tint() == -1.0f);
}

TEST_CASE("[SceneTree][Light3D] Native flicker stays bounded and keeps the base energy") {
	for (int i = 0; i < 2000; i++) {
		const double t = i * 0.0137;
		const float f = Light3D::flicker_factor(t, 0.4f, 1.3f);
		CHECK(f >= 1.0f - 0.4f - 0.0001f);
		CHECK(f <= 1.0f + 0.35f * 0.4f + 0.0001f);
	}
	CHECK(Light3D::flicker_factor(12.5, 0.0f, 0.7f) == 1.0f);

	OmniLight3D *light = memnew(OmniLight3D);
	light->set_param(Light3D::PARAM_ENERGY, 2.5f);
	light->set_flicker(0.5f);
	light->set_flicker_speed(1.5f);
	CHECK(light->get_flicker() == 0.5f);
	CHECK(light->get_flicker_speed() == 1.5f);
	// Flicker only modulates what is sent to the renderer.
	CHECK(light->get_param(Light3D::PARAM_ENERGY) == doctest::Approx(2.5f));
	light->set_flicker(2.0f);
	CHECK(light->get_flicker() == 1.0f);
	light->set_flicker(0.0f);
	CHECK(light->get_flicker() == 0.0f);
	light->set_flicker_color_shift(0.6f);
	CHECK(light->get_flicker_color_shift() == doctest::Approx(0.6f));
	light->set_flicker_color_shift(4.0f);
	CHECK(light->get_flicker_color_shift() == 1.0f);
	// Color shift never touches the stored light color.
	CHECK(light->get_color() == Color(1, 1, 1));
	memdelete(light);
}

} // namespace TestNativeLensAndFlicker

#endif // _3D_DISABLED
