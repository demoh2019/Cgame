/**************************************************************************/
/*  test_directional_light_3d.cpp                                         */
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
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_directional_light_3d)

#ifndef _3D_DISABLED

#include "scene/3d/light_3d.h"

namespace TestDirectionalLight3D {

TEST_CASE("[SceneTree][DirectionalLight3D] Shadow mode changes and duplicate assignments") {
	DirectionalLight3D *light = memnew(DirectionalLight3D);
	CHECK(light->get_shadow_mode() == DirectionalLight3D::SHADOW_PARALLEL_4_SPLITS);

	light->set_shadow_mode(DirectionalLight3D::SHADOW_PARALLEL_4_SPLITS);
	CHECK(light->get_shadow_mode() == DirectionalLight3D::SHADOW_PARALLEL_4_SPLITS);
	light->set_shadow_mode(DirectionalLight3D::SHADOW_PARALLEL_2_SPLITS);
	light->set_shadow_mode(DirectionalLight3D::SHADOW_PARALLEL_2_SPLITS);
	CHECK(light->get_shadow_mode() == DirectionalLight3D::SHADOW_PARALLEL_2_SPLITS);
	light->set_shadow_mode(DirectionalLight3D::SHADOW_ORTHOGONAL);
	CHECK(light->get_shadow_mode() == DirectionalLight3D::SHADOW_ORTHOGONAL);
	memdelete(light);
}

TEST_CASE("[SceneTree][DirectionalLight3D] Invalid shadow mode does not mutate state") {
	DirectionalLight3D *light = memnew(DirectionalLight3D);
	ERR_PRINT_OFF;
	light->set_shadow_mode(static_cast<DirectionalLight3D::ShadowMode>(-1));
	ERR_PRINT_ON;
	CHECK(light->get_shadow_mode() == DirectionalLight3D::SHADOW_PARALLEL_4_SPLITS);
	memdelete(light);
}

} // namespace TestDirectionalLight3D

#endif // _3D_DISABLED
