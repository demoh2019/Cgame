/**************************************************************************/
/*  cgame_hdr_output.cpp                                                  */
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

#include "cgame_hdr_output.h"

#include "core/object/class_db.h"
#include "core/os/os.h"

#include "servers/display/display_server.h"

bool CgameHDROutput::wanted(int p_level, const String &p_rendering_method, bool p_supported) {
	return p_supported && p_rendering_method != "gl_compatibility" && CLAMP(p_level, 0, 3) >= 2;
}

bool CgameHDROutput::supported() {
	DisplayServer *ds = DisplayServer::get_singleton();
	if (ds == nullptr || ds->get_name() == "headless") {
		return false;
	}
	return ds->window_is_hdr_output_supported();
}

bool CgameHDROutput::apply(int p_level, const String &p_rendering_method) {
	DisplayServer *ds = DisplayServer::get_singleton();
	if (ds == nullptr) {
		return false;
	}
	const bool on = wanted(p_level, p_rendering_method, supported());
	ds->window_request_hdr_output(on);
	// Apple devices expose reference white through their brightness control, not this API.
	if (on && OS::get_singleton()->get_name() != "macOS") {
		// UI and diffuse white stay comfortable; highlights (sun, fire, lightning) use the headroom.
		ds->window_set_hdr_output_reference_luminance(PAPER_WHITE_NITS);
	}
	return on;
}

void CgameHDROutput::_bind_methods() {
	ClassDB::bind_static_method("CgameHDROutput", D_METHOD("wanted", "level", "rendering_method", "supported"), &CgameHDROutput::wanted);
	ClassDB::bind_static_method("CgameHDROutput", D_METHOD("supported"), &CgameHDROutput::supported);
	ClassDB::bind_static_method("CgameHDROutput", D_METHOD("apply", "level", "rendering_method"), &CgameHDROutput::apply);
}
