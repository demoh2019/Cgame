/**************************************************************************/
/*  ai_behavior_trace.h                                                 */
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
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

// Opt-in per-agent execution timeline, bounded to one simulation tick.
// A trace records task entry order, path, status and inclusive CPU time.
// It owns no task references and must never be sent to untrusted game clients.
class AIBehaviorTrace : public RefCounted {
	GDCLASS(AIBehaviorTrace, RefCounted);

	int max_steps = 128;
	int64_t tick_index = 0;
	int truncated = 0;
	Array steps;
	Vector<int64_t> started_usec;
	Vector<uint8_t> completed;

protected:
	static void _bind_methods();

public:
	void set_max_steps(int p_max_steps);
	int get_max_steps() const { return max_steps; }

	// Clear the previous tick's timeline; no background collection.
	void begin_tick();

	// Returns a step token or -1 when the current tick is at capacity.
	int begin_step(const String &p_path, const String &p_task_class);

	// Status codes agree with BehaviorTreeTask::Status (SUCCESS=0 etc).
	bool end_step(int p_token, int p_status);

	Dictionary get_snapshot() const;
	void reset();
};
