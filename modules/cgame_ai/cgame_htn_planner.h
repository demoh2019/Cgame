/**************************************************************************/
/*  cgame_htn_planner.h                                                   */
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

#include "cgame_ai_common.h"

#include "core/object/ref_counted.h"

// Hierarchical Task Network planner. Domain layout (plain data):
//   compound task  -> Array of methods, tried in order:
//                     { "preconditions": {key: value}, "subtasks": ["a", "b"] }
//   primitive task -> { "preconditions": {key: value}, "effects": {key: value} }
// A task is primitive when its entry is a Dictionary. Planning decomposes depth
// first on a copy of the world state and backtracks when a branch dead-ends.
class CgameHTNPlanner : public RefCounted {
	GDCLASS(CgameHTNPlanner, RefCounted);

	static bool _solve(const Dictionary &p_domain, const Vector<String> &p_tasks, const Dictionary &p_state, int &r_budget, Vector<String> &r_plan);

protected:
	static void _bind_methods();

public:
	static PackedStringArray plan(const Dictionary &p_domain, const String &p_root_task, const Dictionary &p_state, int p_max_steps = 256);
};
