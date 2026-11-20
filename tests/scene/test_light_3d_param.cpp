/**************************************************************************/
/*  test_light_3d_param.cpp                                               */
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

TEST_FORCE_LINK(test_light_3d_param)

#ifndef _3D_DISABLED

#include "scene/3d/light_3d.h"

namespace TestLight3DParam {

TEST_CASE("[SceneTree][Light3D] Repeated light parameter assignments preserve state") {
	DirectionalLight3D *sun = memnew(DirectionalLight3D);
	CHECK(sun->get_param(Light3D::PARAM_SHADOW_MAX_DISTANCE) == 100);
	sun->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 100);
	CHECK(sun->get_param(Light3D::PARAM_SHADOW_MAX_DISTANCE) == 100);
	sun->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 70);
	sun->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 70);
	CHECK(sun->get_param(Light3D::PARAM_SHADOW_MAX_DISTANCE) == 70);
	sun->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 100);
	CHECK(sun->get_param(Light3D::PARAM_SHADOW_MAX_DISTANCE) == 100);
	memdelete(sun);
}

TEST_CASE("[SceneTree][Light3D] First zero-valued parameter assignment is valid") {
	OmniLight3D *light = memnew(OmniLight3D);
	light->set_param(Light3D::PARAM_SIZE, 0.0);
	light->set_param(Light3D::PARAM_SIZE, 0.0);
	CHECK(light->get_param(Light3D::PARAM_SIZE) == 0.0);
	light->set_param(Light3D::PARAM_SIZE, 0.75);
	CHECK(light->get_param(Light3D::PARAM_SIZE) == 0.75);
	memdelete(light);
}

} // namespace TestLight3DParam

#endif // _3D_DISABLED
