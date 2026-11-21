/**************************************************************************/
/*  ai_execution_profiler.h                                                 */
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

// Opt-in microsecond-level timing counters for NPCs, BehaviorTree runners,
// perception, navigation and server-side AI phases. No global mutable state.
class AIExecutionProfiler : public RefCounted {
	GDCLASS(AIExecutionProfiler, RefCounted);

	static constexpr int MAX_CATEGORIES = 32;
	static constexpr int64_t MAX_SAMPLE_USEC = 1000000000000LL;

	bool enabled = false;
	int64_t budget_usec = 2000;
	int64_t total_samples = 0;
	Dictionary samples;
	Dictionary active_starts;

protected:
	static void _bind_methods();

public:
	void set_enabled(bool p_enabled);
	bool is_enabled() const;

	void set_budget_usec(int64_t p_budget_usec);
	int64_t get_budget_usec() const;

	// Returns false when disabled, invalid, or category limit is reached.
	bool record_sample(const StringName &p_category, int64_t p_duration_usec);
	// A category can have only one open span at a time.
	bool begin_sample(const StringName &p_category);
	// Returns -1 on disabled/missing spans; otherwise elapsed microseconds.
	int64_t end_sample(const StringName &p_category);

	// Deep-copied nested Dictionaries; no handles to live counters are exposed.
	Dictionary get_snapshot() const;
	void reset();
};
