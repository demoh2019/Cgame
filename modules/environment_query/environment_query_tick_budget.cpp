/**************************************************************************/
/*  environment_query_tick_budget.cpp                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the Software without restriction, including without limitation the     */
/* rights to use, copy, modify, merge, publish, distribute, sublicense,    */
/* and/or sell copies of the Software, and to permit persons to whom the   */
/* Software is furnished to do so, subject to the following conditions:   */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,    */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "environment_query_tick_budget.h"

#include "core/object/class_db.h"

void EnvironmentQueryTickBudget::_bind_methods() {
	ClassDB::bind_method(D_METHOD("begin_tick", "tick", "regular_quota_us", "urgent_quota_us"), &EnvironmentQueryTickBudget::begin_tick, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("try_admit_step", "urgent"), &EnvironmentQueryTickBudget::try_admit_step, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("record_step", "actual_us"), &EnvironmentQueryTickBudget::record_step);
	ClassDB::bind_method(D_METHOD("cancel_pending_step"), &EnvironmentQueryTickBudget::cancel_pending_step);
	ClassDB::bind_method(D_METHOD("get_remaining_us", "urgent"), &EnvironmentQueryTickBudget::get_remaining_us, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_tick"), &EnvironmentQueryTickBudget::get_tick);
	ClassDB::bind_method(D_METHOD("get_regular_spent_us"), &EnvironmentQueryTickBudget::get_regular_spent_us);
	ClassDB::bind_method(D_METHOD("get_urgent_spent_us"), &EnvironmentQueryTickBudget::get_urgent_spent_us);
	ClassDB::bind_method(D_METHOD("get_regular_completed"), &EnvironmentQueryTickBudget::get_regular_completed);
	ClassDB::bind_method(D_METHOD("get_urgent_completed"), &EnvironmentQueryTickBudget::get_urgent_completed);
	ClassDB::bind_method(D_METHOD("get_denied_count"), &EnvironmentQueryTickBudget::get_denied_count);
	ClassDB::bind_method(D_METHOD("is_pending"), &EnvironmentQueryTickBudget::is_pending);
}

bool EnvironmentQueryTickBudget::begin_tick(int64_t p_tick, int p_regular_quota_us, int p_urgent_quota_us) {
	ERR_FAIL_COND_V_MSG(p_tick < 0 || p_regular_quota_us < 0 || p_regular_quota_us > 1000000 ||
			p_urgent_quota_us < 0 || p_urgent_quota_us > 1000000, false,
			"EQS tick budgets require nonnegative ticks and 0..1000000us quotas.");
	// Re-entering the same authoritative tick must never refill the ledger.
	if (p_tick == tick) {
		return regular_quota_us == p_regular_quota_us && urgent_quota_us == p_urgent_quota_us;
	}
	ERR_FAIL_COND_V_MSG(pending, false, "Record or cancel the active EQS step before changing ticks.");
	tick = p_tick;
	regular_quota_us = p_regular_quota_us;
	urgent_quota_us = p_urgent_quota_us;
	regular_spent_us = 0;
	urgent_spent_us = 0;
	regular_completed = 0;
	urgent_completed = 0;
	denied = 0;
	return true;
}

int EnvironmentQueryTickBudget::get_remaining_us(bool p_urgent) const {
	if (tick < 0) {
		return 0;
	}
	const int64_t allowance = p_urgent ? urgent_quota_us : regular_quota_us;
	const int64_t spent = p_urgent ? urgent_spent_us : regular_spent_us;
	return int(allowance > spent ? allowance - spent : 0);
}

bool EnvironmentQueryTickBudget::try_admit_step(bool p_urgent) {
	// Game script steps are synchronous; this protects misbehaving clients
	// from opening multiple debits for a single query grant.
	if (tick < 0 || pending || get_remaining_us(p_urgent) <= 0) {
		denied++;
		return false;
	}
	pending = true;
	pending_urgent = p_urgent;
	return true;
}

bool EnvironmentQueryTickBudget::record_step(int64_t p_actual_us) {
	ERR_FAIL_COND_V_MSG(!pending || p_actual_us < 0 || p_actual_us > 1000000000LL, false,
			"EQS work debit needs one pending admission and 0..1000000000 measured microseconds.");
	// Sub-microsecond steps round up to a 1us debit, guaranteeing quota
	// exhaustion even if the native clock rounds a cheap step to zero.
	const int64_t charged_us = p_actual_us > 0 ? p_actual_us : 1;
	if (pending_urgent) {
		urgent_spent_us += charged_us;
		urgent_completed++;
	} else {
		regular_spent_us += charged_us;
		regular_completed++;
	}
	pending = false;
	pending_urgent = false;
	return true;
}

void EnvironmentQueryTickBudget::cancel_pending_step() {
	pending = false;
	pending_urgent = false;
}
