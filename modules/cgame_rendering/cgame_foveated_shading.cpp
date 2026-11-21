/**************************************************************************/
/*  cgame_foveated_shading.cpp                                            */
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

#include "cgame_foveated_shading.h"

#include "core/object/class_db.h"

#include "core/math/math_funcs.h"
#include "scene/main/viewport.h"

Ref<ImageTexture> CgameFoveatedShading::cached;
String CgameFoveatedShading::cached_key;

CgameFoveatedShading::Profile CgameFoveatedShading::compute_profile(int p_level, const String &p_rendering_method) {
	Profile profile;
	if (p_rendering_method != "forward_plus" && p_rendering_method != "mobile") {
		return profile;
	}
	switch (CLAMP(p_level, 0, 3)) {
		case 0: {
			profile.enabled = true;
			profile.inner = 0.42f;
			profile.outer = 0.72f;
		} break;
		case 1: {
			profile.enabled = true;
			profile.inner = 0.6f;
			profile.outer = 0.95f;
		} break;
		default: {
		} break;
	}
	return profile;
}

CgameFoveatedShading::Rate CgameFoveatedShading::rate_at(float p_u, float p_v, float p_inner, float p_outer) {
	const float r = Math::sqrt(p_u * p_u + p_v * p_v);
	if (r > p_outer) {
		return RATE_4X4;
	}
	if (r > p_inner) {
		// Top/bottom of a landscape screen hold less gameplay than the sides.
		return Math::abs(p_v) > Math::abs(p_u) * 0.75f ? RATE_2X2 : RATE_2X1;
	}
	return RATE_1X1;
}

Vector<uint8_t> CgameFoveatedShading::build_map_data(const Vector2i &p_size, float p_inner, float p_outer) {
	const int w = MAX(1, p_size.x);
	const int h = MAX(1, p_size.y);
	Vector<uint8_t> data;
	data.resize(w * h * 3);
	uint8_t *ptr = data.ptrw();
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			const float u = ((float)x + 0.5f) / (float)w * 2.0f - 1.0f;
			const float v = ((float)y + 0.5f) / (float)h * 2.0f - 1.0f;
			const Rate rate = rate_at(u, v, p_inner, p_outer);
			const int o = (y * w + x) * 3;
			ptr[o] = rate.r;
			ptr[o + 1] = rate.g;
			ptr[o + 2] = 0;
		}
	}
	return data;
}

Dictionary CgameFoveatedShading::settings(int p_level, const String &p_rendering_method) {
	const Profile profile = compute_profile(p_level, p_rendering_method);
	Dictionary result;
	result["enabled"] = profile.enabled;
	if (profile.enabled) {
		result["inner"] = profile.inner;
		result["outer"] = profile.outer;
	}
	return result;
}

Ref<Image> CgameFoveatedShading::build_map(const Vector2i &p_size, float p_inner, float p_outer) {
	const int w = MAX(1, p_size.x);
	const int h = MAX(1, p_size.y);
	return Image::create_from_data(w, h, false, Image::FORMAT_RGB8, build_map_data(p_size, p_inner, p_outer));
}

bool CgameFoveatedShading::apply(Viewport *p_viewport, int p_level, const String &p_rendering_method) {
	if (p_viewport == nullptr) {
		return false;
	}
	const Profile profile = compute_profile(p_level, p_rendering_method);
	if (!profile.enabled) {
		p_viewport->set_vrs_mode(Viewport::VRS_DISABLED);
		p_viewport->set_vrs_texture(Ref<Texture2D>());
		return false;
	}
	const Vector2i px = Vector2i(p_viewport->get_visible_rect().size);
	const Vector2i tiles = Vector2i(MAX(1, px.x / TILE), MAX(1, px.y / TILE));
	const String key = vformat("%d:%d:%.2f:%.2f", tiles.x, tiles.y, profile.inner, profile.outer);
	if (cached.is_null() || key != cached_key) {
		cached = ImageTexture::create_from_image(build_map(tiles, profile.inner, profile.outer));
		cached_key = key;
	}
	p_viewport->set_vrs_texture(cached);
	p_viewport->set_vrs_update_mode(Viewport::VRS_UPDATE_ONCE);
	p_viewport->set_vrs_mode(Viewport::VRS_TEXTURE);
	return true;
}

void CgameFoveatedShading::_bind_methods() {
	ClassDB::bind_static_method("CgameFoveatedShading", D_METHOD("settings", "level", "rendering_method"), &CgameFoveatedShading::settings);
	ClassDB::bind_static_method("CgameFoveatedShading", D_METHOD("build_map", "size", "inner", "outer"), &CgameFoveatedShading::build_map);
	ClassDB::bind_static_method("CgameFoveatedShading", D_METHOD("apply", "viewport", "level", "rendering_method"), &CgameFoveatedShading::apply);
}
