/**************************************************************************/
/*  test_environment_weather_fog.cpp                                      */
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

TEST_FORCE_LINK(test_environment_weather_fog)

#ifndef _3D_DISABLED

#include "scene/resources/environment.h"

namespace TestEnvironmentWeatherFog {

TEST_CASE("[SceneTree][Environment] Atomic weather fog preserves visual parameters") {
	Ref<Environment> environment;
	environment.instantiate();
	const Color shoreline(0.45, 0.57, 0.64);
	const float density = 0.0035f;
	const float height = 2.6f;
	const float height_density = 0.00185f;
	const float sun_scatter = 0.23f;

	environment->configure_weather_fog(shoreline, density, height, height_density, sun_scatter);
	CHECK(environment->get_fog_light_color() == shoreline);
	CHECK(environment->get_fog_density() == density);
	CHECK(environment->get_fog_height() == height);
	CHECK(environment->get_fog_height_density() == height_density);
	CHECK(environment->get_fog_sun_scatter() == sun_scatter);

	// A no-op update should skip the RenderingServer call entirely.
	environment->configure_weather_fog(shoreline, density, height, height_density, sun_scatter);
	CHECK(environment->get_fog_density() == density);
	CHECK(environment->get_fog_sun_scatter() == sun_scatter);

	// Existing editor/animation individual setters must continue to work.
	environment->set_fog_height_density(-0.002f);
	CHECK(environment->get_fog_height_density() == -0.002f);
	environment->set_fog_height_density(-0.002f);
	CHECK(environment->get_fog_height_density() == -0.002f);

	const Color storm(0.27, 0.31, 0.36);
	environment->configure_weather_fog(storm, 0.007f, 3.0f, 0.0024f, 0.04f);
	CHECK(environment->get_fog_light_color() == storm);
	CHECK(environment->get_fog_density() == 0.007f);
	CHECK(environment->get_fog_height() == 3.0f);
	CHECK(environment->get_fog_height_density() == 0.0024f);
	CHECK(environment->get_fog_sun_scatter() == 0.04f);
}

} // namespace TestEnvironmentWeatherFog

#endif // _3D_DISABLED
