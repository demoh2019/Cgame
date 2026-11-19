/**************************************************************************/
/*  test_gltf_spotlight.h                                                 */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF   */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/*                                                                        */
/**************************************************************************/

#pragma once

#include "modules/gltf/extensions/gltf_light.h"

#include "scene/3d/light_3d.h"
#include "tests/test_macros.h"

namespace TestGltfSpotlight {

TEST_CASE("[GLTFLight] Spot attenuation maps to expected inner cone ratios") {
	struct Case {
		float attenuation;
		float expected_ratio;
	};
	const Case cases[] = {
		{ 0.1f, 0.980198f },
		{ 1.0f, 0.818182f },
		{ 4.0f, 0.428571f },
		{ 10.0f, 0.0f },
	};
	for (const Case &test_case : cases) {
		SpotLight3D *original = memnew(SpotLight3D);
		original->set_param(SpotLight3D::PARAM_SPOT_ANGLE, 60.0f);
		original->set_param(SpotLight3D::PARAM_SPOT_ATTENUATION, test_case.attenuation);
		Ref<GLTFLight> gltf = GLTFLight::from_node(original);
		REQUIRE(gltf.is_valid());
		CHECK(Math::abs(gltf->get_outer_cone_angle() - Math::deg_to_rad(60.0f)) < 0.00001f);
		CHECK(Math::abs(gltf->get_inner_cone_angle() / gltf->get_outer_cone_angle() - test_case.expected_ratio) < 0.0001f);
		memdelete(original);
	}
}

TEST_CASE("[GLTFLight] Spotlight attenuation survives Godot to glTF to Godot round-trip") {
	const float attenuations[] = { 0.1f, 1.0f, 4.0f, 10.0f };
	for (float attenuation : attenuations) {
		SpotLight3D *original = memnew(SpotLight3D);
		original->set_param(SpotLight3D::PARAM_SPOT_ANGLE, 60.0f);
		original->set_param(SpotLight3D::PARAM_SPOT_ATTENUATION, attenuation);
		Ref<GLTFLight> gltf = GLTFLight::from_node(original);
		Light3D *restored = gltf->to_node();
		SpotLight3D *restored_spot = Object::cast_to<SpotLight3D>(restored);
		REQUIRE(restored_spot != nullptr);
		CHECK(Math::abs(restored_spot->get_param(SpotLight3D::PARAM_SPOT_ATTENUATION) - attenuation) < 0.001f);
		CHECK(Math::abs(restored_spot->get_param(SpotLight3D::PARAM_SPOT_ANGLE) - 60.0f) < 0.0001f);
		memdelete(restored);
		memdelete(original);
	}
}

TEST_CASE("[GLTFLight] Equal inner and outer angles produce non-diverging attenuation") {
	Ref<GLTFLight> gltf;
	gltf.instantiate();
	gltf->set_light_type("spot");
	gltf->set_outer_cone_angle(0.5f);
	gltf->set_inner_cone_angle(0.5f);
	Light3D *node = gltf->to_node();
	SpotLight3D *spot = Object::cast_to<SpotLight3D>(node);
	REQUIRE(spot != nullptr);
	CHECK(spot->get_param(SpotLight3D::PARAM_SPOT_ATTENUATION) == 0.0f);
	Ref<GLTFLight> exported = GLTFLight::from_node(spot);
	CHECK(exported->get_inner_cone_angle() < exported->get_outer_cone_angle());
	CHECK(exported->get_inner_cone_angle() > 0.0f);
	memdelete(node);
}

TEST_CASE("[GLTFLight] Zero attenuation exports valid inner angle below outer") {
	SpotLight3D *original = memnew(SpotLight3D);
	original->set_param(SpotLight3D::PARAM_SPOT_ANGLE, 45.0f);
	original->set_param(SpotLight3D::PARAM_SPOT_ATTENUATION, 0.0f);
	Ref<GLTFLight> exported = GLTFLight::from_node(original);
	CHECK(exported->get_inner_cone_angle() < exported->get_outer_cone_angle());
	CHECK(exported->get_inner_cone_angle() > 0.0f);
	CHECK(Math::abs(exported->get_inner_cone_angle() / exported->get_outer_cone_angle() - 0.999999f) < 0.00001f);
	memdelete(original);
}

TEST_CASE("[GLTFLight] glTF spotlight with half-angle cone imports expected Godot attenuation") {
	Ref<GLTFLight> gltf;
	gltf.instantiate();
	gltf->set_light_type("spot");
	gltf->set_outer_cone_angle(0.1f);
	gltf->set_inner_cone_angle(0.05f);
	Light3D *node = gltf->to_node();
	SpotLight3D *spot = Object::cast_to<SpotLight3D>(node);
	REQUIRE(spot != nullptr);
	CHECK(Math::abs(spot->get_param(SpotLight3D::PARAM_SPOT_ATTENUATION) - (10.0f / 3.0f)) < 0.0002f);
	CHECK(Math::abs(spot->get_param(SpotLight3D::PARAM_SPOT_ANGLE) - Math::rad_to_deg(0.1f)) < 0.0001f);
	memdelete(node);
}

TEST_CASE("[GLTFLight] glTF dictionary accepts equal cone angles without losing values") {
	Dictionary spot;
	spot["innerConeAngle"] = 0.3f;
	spot["outerConeAngle"] = 0.3f;
	Dictionary d;
	d["type"] = "spot";
	d["spot"] = spot;
	Ref<GLTFLight> imported = GLTFLight::from_dictionary(d);
	REQUIRE(imported.is_valid());
	CHECK(Math::abs(imported->get_inner_cone_angle() - 0.3f) < 0.00001f);
	CHECK(Math::abs(imported->get_outer_cone_angle() - 0.3f) < 0.00001f);
}

} // namespace TestGltfSpotlight
