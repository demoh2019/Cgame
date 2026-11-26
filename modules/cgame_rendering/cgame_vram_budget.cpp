/**************************************************************************/
/*  cgame_vram_budget.cpp                                                 */
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

#include "cgame_vram_budget.h"

#include "core/object/class_db.h"

#include "core/math/math_funcs.h"
#include "servers/rendering/rendering_server.h"

double CgameVRAMBudget::budget_bytes(int p_level) {
	return BUDGET_MB[CLAMP(p_level, 0, 3)] * 1024.0 * 1024.0;
}

double CgameVRAMBudget::used_bytes() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return 0.0;
	}
	return (double)rs->get_rendering_info(RSE::RENDERING_INFO_VIDEO_MEM_USED);
}

bool CgameVRAMBudget::upgrade_allowed(double p_used, int p_level) {
	return Math::is_finite(p_used) && p_used > 0.0 && p_used <= budget_bytes(CLAMP(p_level, 0, 3) + 1) * RELIEF;
}

bool CgameVRAMBudget::sample(double p_used, int p_level, double p_delta) {
	// A suspended window or missing residency data is not evidence of pressure.
	if (!Math::is_finite(p_used) || p_used <= 0.0 || !Math::is_finite(p_delta) || p_delta <= 0.0 || p_delta > 0.2) {
		return false;
	}
	if (p_used > budget_bytes(p_level) * PRESSURE) {
		pressure_seconds += p_delta;
		if (pressure_seconds >= SUSTAIN) {
			pressure_seconds = 0.0;
			return p_level > 0;
		}
	} else {
		pressure_seconds = 0.0;
	}
	return false;
}

void CgameVRAMBudget::reset() {
	pressure_seconds = 0.0;
}

void CgameVRAMBudget::_bind_methods() {
	ClassDB::bind_static_method("CgameVRAMBudget", D_METHOD("budget_bytes", "level"), &CgameVRAMBudget::budget_bytes);
	ClassDB::bind_static_method("CgameVRAMBudget", D_METHOD("used_bytes"), &CgameVRAMBudget::used_bytes);
	ClassDB::bind_static_method("CgameVRAMBudget", D_METHOD("upgrade_allowed", "used", "level"), &CgameVRAMBudget::upgrade_allowed);
	ClassDB::bind_method(D_METHOD("sample", "used", "level", "delta"), &CgameVRAMBudget::sample);
	ClassDB::bind_method(D_METHOD("get_pressure_seconds"), &CgameVRAMBudget::get_pressure_seconds);
	ClassDB::bind_method(D_METHOD("reset"), &CgameVRAMBudget::reset);
}
