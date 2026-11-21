/**************************************************************************/
/*  ai_action_cooldowns.cpp                                                 */
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

#include "ai_action_cooldowns.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

bool AIActionCooldowns::try_trigger(const StringName &p_action, double p_duration) {
	ERR_FAIL_COND_V_MSG(p_action.is_empty(), false, "Cooldown action key cannot be empty.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_duration) || p_duration < 0.0 || p_duration > 3600.0, false, "Cooldown duration must be finite and within [0, 3600] seconds.");
	if (get_remaining(p_action) > 0.0) {
		return false;
	}
	if (p_duration == 0.0) {
		return true;
	}
	ERR_FAIL_COND_V_MSG(!remaining.has(p_action) && remaining.size() >= MAX_ACTIONS, false, "A cooldown ledger supports at most sixteen active action keys.");
	remaining[p_action] = p_duration;
	return true;
}

void AIActionCooldowns::advance_time(double p_delta) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_delta) || p_delta < 0.0, "Cooldown delta must be finite and nonnegative.");
	if (p_delta == 0.0) {
		return;
	}
	Array keys = remaining.keys();
	for (int i = 0; i < keys.size(); ++i) {
		const StringName action = keys[i];
		const double next = double(remaining[action]) - p_delta;
		if (next <= 0.0) {
			remaining.erase(action);
		} else {
			remaining[action] = next;
		}
	}
}

double AIActionCooldowns::get_remaining(const StringName &p_action) const {
	return MAX(0.0, double(remaining.get(p_action, 0.0)));
}

void AIActionCooldowns::_bind_methods() {
	ClassDB::bind_method(D_METHOD("try_trigger", "action", "duration"), &AIActionCooldowns::try_trigger);
	ClassDB::bind_method(D_METHOD("advance_time", "delta"), &AIActionCooldowns::advance_time);
	ClassDB::bind_method(D_METHOD("get_remaining", "action"), &AIActionCooldowns::get_remaining);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &AIActionCooldowns::get_snapshot);
	ClassDB::bind_method(D_METHOD("reset"), &AIActionCooldowns::reset);
}
