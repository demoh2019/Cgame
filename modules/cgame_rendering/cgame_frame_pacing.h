/**************************************************************************/
/*  cgame_frame_pacing.h                                                  */
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

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Frame pacing like UE5 r.VSync / t.MaxFPS and Unity's targetFrameRate: steady frame delivery beats
// a higher but jittery average. Performance caps to (half) the display refresh, Ultra uses mailbox.
class CgameFramePacing : public RefCounted {
	GDCLASS(CgameFramePacing, RefCounted);

public:
	static constexpr float FALLBACK_REFRESH = 60.0f;

	struct Profile {
		int vsync = 1; // DisplayServerEnums::VSyncMode value.
		int max_fps = 0;
	};

protected:
	static void _bind_methods();

public:
	// Pure part (no engine singletons): used by tests.
	static Profile compute_profile(int p_level, float p_refresh_hz);

	static float display_refresh();
	static Dictionary settings(int p_level, float p_refresh_hz);
	static Dictionary apply(int p_level);
};
