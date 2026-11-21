/**************************************************************************/
/*  environment_query_tick_budget.h                                      */
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

#pragma once

#include "core/object/ref_counted.h"

// A shared main-thread ledger for measured EQS work over one server tick.
// Its two pools deliberately never borrow from each other: urgent ownership
// recovery cannot starve routine tactical decisions, nor vice versa.
// Budgeting is soft because a single source candidate is not preemptible.
class EnvironmentQueryTickBudget : public RefCounted {
	GDCLASS(EnvironmentQueryTickBudget, RefCounted);

	int64_t tick = -1;
	int regular_quota_us = 0;
	int urgent_quota_us = 0;
	int64_t regular_spent_us = 0;
	int64_t urgent_spent_us = 0;
	int regular_completed = 0;
	int urgent_completed = 0;
	int denied = 0;
	bool pending = false;
	bool pending_urgent = false;

protected:
	static void _bind_methods();

public:
	bool begin_tick(int64_t p_tick, int p_regular_quota_us, int p_urgent_quota_us = 0);
	bool try_admit_step(bool p_urgent = false);
	bool record_step(int64_t p_actual_us);
	void cancel_pending_step();
	int get_remaining_us(bool p_urgent = false) const;
	int64_t get_tick() const { return tick; }
	int64_t get_regular_spent_us() const { return regular_spent_us; }
	int64_t get_urgent_spent_us() const { return urgent_spent_us; }
	int get_regular_completed() const { return regular_completed; }
	int get_urgent_completed() const { return urgent_completed; }
	int get_denied_count() const { return denied; }
	bool is_pending() const { return pending; }
};
