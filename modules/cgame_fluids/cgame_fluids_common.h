/**************************************************************************/
/*  cgame_fluids_common.h                                                 */
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

#include "core/math/math_defs.h"
#include "core/object/class_db.h"
#include "core/object/worker_thread_pool.h"

// Shared helpers for the Cgame fluid solvers.

// Declares a plain setter/getter pair for a member called `m_name`.
#define CGF_ACCESSOR(m_type, m_name)                        \
	void set_##m_name(m_type p_value) { m_name = p_value; } \
	m_type get_##m_name() const { return m_name; }

// Same as CGF_ACCESSOR for value types that are cheaper to pass by const reference.
#define CGF_ACCESSOR_REF(m_type, m_name)                           \
	void set_##m_name(const m_type &p_value) { m_name = p_value; } \
	m_type get_##m_name() const { return m_name; }

// Declares a getter only (read-only property).
#define CGF_GETTER(m_type, m_name) \
	m_type get_##m_name() const { return m_name; }

// Binds a read/write property through its set_/get_ pair.
#define CGF_BIND_PROPERTY(m_class, m_variant, m_name)                                \
	ClassDB::bind_method(D_METHOD("set_" #m_name, "value"), &m_class::set_##m_name); \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &m_class::get_##m_name);          \
	ADD_PROPERTY(PropertyInfo(m_variant, #m_name), "set_" #m_name, "get_" #m_name);

// Binds a read-only property (getter only, no setter exposed).
#define CGF_BIND_READONLY_PROPERTY(m_class, m_variant, m_name)              \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &m_class::get_##m_name); \
	ADD_PROPERTY(PropertyInfo(m_variant, #m_name, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY), "", "get_" #m_name);

namespace CgameFluids {

// Splits [0, p_count) into contiguous chunks and runs p_fn(from, to) on the
// WorkerThreadPool. Callers must guarantee that every chunk only writes
// elements inside its own range (or other chunk-private memory) so the
// result is bit-identical to a serial run regardless of thread scheduling.
// Falls back to a serial call when the work is too small or threads are off.
template <typename F>
void parallel_for(int p_count, int p_min_chunk, const F &p_fn) {
	if (p_count <= 0) {
		return;
	}
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	int tasks = 1;
	if (pool && p_min_chunk > 0) {
		tasks = MIN(pool->get_thread_count(), p_count / p_min_chunk);
	}
	if (tasks <= 1) {
		p_fn(0, p_count);
		return;
	}
	struct Context {
		const F *fn;
		int count;
		int tasks;
	} ctx = { &p_fn, p_count, tasks };
	WorkerThreadPool::GroupID group = pool->add_native_group_task(
			[](void *p_userdata, uint32_t p_index) {
				const Context *c = static_cast<const Context *>(p_userdata);
				int from = int(int64_t(c->count) * int64_t(p_index) / c->tasks);
				int to = int(int64_t(c->count) * int64_t(p_index + 1) / c->tasks);
				(*c->fn)(from, to);
			},
			&ctx, tasks, tasks, false, "CgameFluids");
	pool->wait_for_group_task_completion(group);
}

} // namespace CgameFluids
