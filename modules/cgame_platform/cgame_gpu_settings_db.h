/**************************************************************************/
/*  cgame_gpu_settings_db.h                                               */
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

// GPU family database mapping an adapter name to a recommended quality level (0 low .. 3 ultra), resolution scale
// and feature toggles. Adapters are matched by regular expression, first rule wins. Measured frame times learned
// at runtime override the static heuristic using the median frame time per quality level.
class CgameGPUSettingsDB : public RefCounted {
	GDCLASS(CgameGPUSettingsDB, RefCounted);

public:
	static constexpr int MAX_LEVEL = 3;
	static constexpr int MAX_SAMPLES_PER_LEVEL = 31;
	static constexpr double TARGET_FRAME_MS = 1000.0 / 60.0;

	static String get_default_path() { return "user://gpu_learned.json"; }

private:
	static Dictionary _fallback(const String &p_name, const String &p_vendor);
	static Dictionary _medians(const String &p_adapter, const String &p_path);
	static Dictionary _load(const String &p_path);

protected:
	static void _bind_methods();

public:
	static Dictionary match_adapter(const String &p_adapter, const String &p_vendor = "");
	static Dictionary features_for(int p_level);
	static Dictionary recommend(const String &p_adapter, const String &p_vendor = "", double p_target_ms = TARGET_FRAME_MS, const String &p_path = "user://gpu_learned.json");
	static bool learn(const String &p_adapter, double p_measured_frame_ms, int p_level, const String &p_path = "user://gpu_learned.json");
	static Dictionary recommend_current();
	static int get_rule_count();
};
