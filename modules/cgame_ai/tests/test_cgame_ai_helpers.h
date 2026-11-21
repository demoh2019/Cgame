/**************************************************************************/
/*  test_cgame_ai_helpers.h                                               */
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

#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

#include <initializer_list>
#include <utility>

// Terse literal builders so the doctests can mirror the GDScript data 1:1.
namespace CgameAITestUtil {

inline Dictionary dict(std::initializer_list<std::pair<const char *, Variant>> p_items) {
	Dictionary d;
	for (const std::pair<const char *, Variant> &kv : p_items) {
		d[String(kv.first)] = kv.second;
	}
	return d;
}

inline Array arr(std::initializer_list<Variant> p_items) {
	Array a;
	for (const Variant &v : p_items) {
		a.push_back(v);
	}
	return a;
}

inline PackedStringArray psa(std::initializer_list<const char *> p_items) {
	PackedStringArray a;
	for (const char *s : p_items) {
		a.push_back(String(s));
	}
	return a;
}

} // namespace CgameAITestUtil
