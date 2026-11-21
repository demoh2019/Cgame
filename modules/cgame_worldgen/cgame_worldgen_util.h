/**************************************************************************/
/*  cgame_worldgen_util.h                                                 */
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

#include "core/object/worker_thread_pool.h"
#include "core/variant/dictionary.h"

namespace CgameWorldgen {

template <typename F>
void _parallel_trampoline(void *p_userdata, uint32_t p_index) {
	(*static_cast<F *>(p_userdata))((int)p_index);
}

// Runs p_fn(i) for i in [0, p_count). When p_threaded is true and the worker pool is available the
// iterations are distributed over the WorkerThreadPool. p_fn must only write to memory owned by
// iteration i (for example one row of an output buffer) so that the result is independent of
// scheduling and therefore deterministic.
template <typename F>
void parallel_for(int p_count, bool p_threaded, F p_fn) {
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	if (!p_threaded || pool == nullptr || p_count < 2) {
		for (int i = 0; i < p_count; i++) {
			p_fn(i);
		}
		return;
	}
	WorkerThreadPool::GroupID group = pool->add_native_group_task(&_parallel_trampoline<F>, &p_fn, p_count, -1, false, "CgameWorldgen");
	pool->wait_for_group_task_completion(group);
}

// Cells above which row loops are worth distributing over threads.
constexpr int64_t PARALLEL_CELL_THRESHOLD = 16384;

inline double dict_float(const Dictionary &p_dict, const StringName &p_key, double p_default) {
	return p_dict.has(p_key) ? (double)p_dict[p_key] : p_default;
}

} // namespace CgameWorldgen
