/**************************************************************************/
/*  cgame_area_lights.cpp                                                 */
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

#include "cgame_area_lights.h"

#include "core/object/class_db.h"

#include "scene/3d/light_3d.h"
#include "scene/main/scene_tree.h"
#include "servers/rendering/rendering_server.h"

int CgameAreaLights::level = 1;

const StringName &CgameAreaLights::get_group() {
	static const StringName group = StringName("aa_area_light");
	return group;
}

const StringName &CgameAreaLights::get_meta_radius() {
	static const StringName meta = StringName("aa_area_radius");
	return meta;
}

int CgameAreaLights::filter_quality(int p_level) {
	switch (CLAMP(p_level, 0, 3)) {
		case 0:
			return RSE::SHADOW_QUALITY_HARD;
		case 1:
			return RSE::SHADOW_QUALITY_SOFT_LOW;
		case 2:
			return RSE::SHADOW_QUALITY_SOFT_MEDIUM;
		default:
			return RSE::SHADOW_QUALITY_SOFT_HIGH;
	}
}

float CgameAreaLights::size_for(int p_level, float p_emitter_radius) {
	return CLAMP(p_level, 0, 3) >= 2 ? MAX(0.0f, p_emitter_radius) : 0.0f;
}

void CgameAreaLights::_apply_one(Light3D *p_light) {
	if (p_light == nullptr) {
		return;
	}
	if (Object::cast_to<OmniLight3D>(p_light) == nullptr && Object::cast_to<SpotLight3D>(p_light) == nullptr) {
		return;
	}
	const float radius = (float)p_light->get_meta(get_meta_radius(), 0.0f);
	p_light->set_param(Light3D::PARAM_SIZE, size_for(level, radius));
}

void CgameAreaLights::register_light(Light3D *p_light, float p_emitter_radius) {
	if (p_light == nullptr) {
		return;
	}
	p_light->set_meta(get_meta_radius(), p_emitter_radius);
	if (!p_light->is_in_group(get_group())) {
		p_light->add_to_group(get_group());
	}
	_apply_one(p_light);
}

void CgameAreaLights::configure(int p_level, SceneTree *p_tree) {
	level = CLAMP(p_level, 0, 3);
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr) {
		rs->positional_soft_shadow_filter_set_quality((RSE::ShadowQuality)filter_quality(level));
	}
	if (p_tree == nullptr) {
		return;
	}
	Vector<Node *> nodes = p_tree->get_nodes_in_group(get_group());
	for (Node *node : nodes) {
		_apply_one(Object::cast_to<Light3D>(node));
	}
}

void CgameAreaLights::_bind_methods() {
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("filter_quality", "level"), &CgameAreaLights::filter_quality);
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("size_for", "level", "emitter_radius"), &CgameAreaLights::size_for);
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("register_light", "light", "emitter_radius"), &CgameAreaLights::register_light);
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("configure", "level", "tree"), &CgameAreaLights::configure);
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("get_level"), &CgameAreaLights::get_level);
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("get_group"), &CgameAreaLights::get_group);
	ClassDB::bind_static_method("CgameAreaLights", D_METHOD("get_meta_radius"), &CgameAreaLights::get_meta_radius);
}
