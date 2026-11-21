/**************************************************************************/
/*  cgame_server_macros.h                                                 */
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

#include "core/object/class_db.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"

#include <algorithm>

// Helpers that keep the many plain data properties of the server classes short. Every property
// has a `set_<name>` / `get_<name>` pair, matching the engine's naming convention.

#define CGAME_ACCESSORS(m_type, m_name) \
	void set_##m_name(const m_type &p_value) { m_name = p_value; } \
	m_type get_##m_name() const { return m_name; }

#define CGAME_BIND_PROPERTY(m_class, m_variant_type, m_name) \
	ClassDB::bind_method(D_METHOD("set_" #m_name, "value"), &m_class::set_##m_name); \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &m_class::get_##m_name); \
	ADD_PROPERTY(PropertyInfo(m_variant_type, #m_name), "set_" #m_name, "get_" #m_name);

// Sorts an Array in place with a strict weak ordering over its elements. The orderings used by the
// server classes are total (they end in a unique key), so the result is deterministic.
template <typename Compare>
inline void cgame_sort_array(Array &r_array, Compare p_less) {
	Vector<Variant> items;
	items.resize(r_array.size());
	for (int i = 0; i < r_array.size(); i++) {
		items.write[i] = r_array[i];
	}
	std::sort(items.ptrw(), items.ptrw() + items.size(), p_less);
	for (int i = 0; i < items.size(); i++) {
		r_array[i] = items[i];
	}
}
