/**************************************************************************/
/*  cgame_frame_pacing.cpp                                                */
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

#include "cgame_frame_pacing.h"

#include "core/object/class_db.h"

#include "core/config/engine.h"
#include "core/math/math_funcs.h"
#include "servers/display/display_server.h"

CgameFramePacing::Profile CgameFramePacing::compute_profile(int p_level, float p_refresh_hz) {
	const int tier = CLAMP(p_level, 0, 3);
	const float hz = Math::is_finite(p_refresh_hz) && p_refresh_hz >= 30.0f && p_refresh_hz <= 1000.0f ? p_refresh_hz : FALLBACK_REFRESH;
	Profile profile;
	switch (tier) {
		case 0: {
			// Half-rate on high-refresh panels keeps laptops cool and frame time even.
			profile.vsync = DisplayServerEnums::VSYNC_ENABLED;
			profile.max_fps = hz > 90.0f ? (int)Math::round(hz / 2.0f) : (int)Math::round(hz);
		} break;
		case 1: {
			profile.vsync = DisplayServerEnums::VSYNC_ENABLED;
			profile.max_fps = (int)Math::round(hz);
		} break;
		case 2: {
			profile.vsync = DisplayServerEnums::VSYNC_ADAPTIVE;
			profile.max_fps = (int)Math::round(hz);
		} break;
		default: {
			// Mailbox: newest frame wins, no tearing, lowest input latency.
			profile.vsync = DisplayServerEnums::VSYNC_MAILBOX;
			profile.max_fps = 0;
		} break;
	}
	return profile;
}

float CgameFramePacing::display_refresh() {
	DisplayServer *ds = DisplayServer::get_singleton();
	if (ds == nullptr) {
		return FALLBACK_REFRESH;
	}
	const float hz = ds->screen_get_refresh_rate();
	return Math::is_finite(hz) && hz >= 30.0f && hz <= 1000.0f ? hz : FALLBACK_REFRESH;
}

Dictionary CgameFramePacing::settings(int p_level, float p_refresh_hz) {
	const Profile profile = compute_profile(p_level, p_refresh_hz);
	Dictionary result;
	result["vsync"] = profile.vsync;
	result["max_fps"] = profile.max_fps;
	return result;
}

Dictionary CgameFramePacing::apply(int p_level) {
	const Profile profile = compute_profile(p_level, display_refresh());
	DisplayServer *ds = DisplayServer::get_singleton();
	if (ds != nullptr && ds->get_name() != "headless") {
		ds->window_set_vsync_mode((DisplayServerEnums::VSyncMode)profile.vsync);
	}
	if (Engine::get_singleton() != nullptr) {
		Engine::get_singleton()->set_max_fps(profile.max_fps);
	}
	Dictionary result;
	result["vsync"] = profile.vsync;
	result["max_fps"] = profile.max_fps;
	return result;
}

void CgameFramePacing::_bind_methods() {
	ClassDB::bind_static_method("CgameFramePacing", D_METHOD("display_refresh"), &CgameFramePacing::display_refresh);
	ClassDB::bind_static_method("CgameFramePacing", D_METHOD("settings", "level", "refresh_hz"), &CgameFramePacing::settings);
	ClassDB::bind_static_method("CgameFramePacing", D_METHOD("apply", "level"), &CgameFramePacing::apply);
}
