/**************************************************************************/
/*  test_array_filter_lazy.cpp                                            */
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
/*                                                                        */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_array_filter_lazy)

#include "core/object/callable_mp.h"
#include "core/variant/array.h"
#include "core/variant/typed_array.h"

namespace TestArrayFilterLazy {

static int filter_calls = 0;
static Array *filter_source = nullptr;
static bool source_extended = false;

static bool reject_all(int p_number) {
	(void)p_number;
	filter_calls++;
	return false;
}

static bool accept_all(int p_number) {
	(void)p_number;
	filter_calls++;
	return true;
}

static bool accept_even(int p_number) {
	filter_calls++;
	return (p_number % 2) == 0;
}

static bool accept_last(int p_number) {
	filter_calls++;
	return p_number == 4095;
}

static bool mutate_following_value(int p_number) {
	filter_calls++;
	if (p_number == 1 && filter_source) {
		(*filter_source)[1] = 200;
	}
	return true;
}

static bool append_to_source_late(int p_number) {
	filter_calls++;
	if (p_number == 2 && filter_source && !source_extended) {
		source_extended = true;
		filter_source->append(3);
	}
	return true;
}

TEST_CASE("[ArrayFilterLazy] All rejected leaves an empty result and evaluates every predicate") {
	Array source;
	for (int i = 0; i < 2048; i++) {
		source.append(i);
	}
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(reject_all));
	CHECK(result.is_empty());
	CHECK_EQ(result.size(), 0);
	CHECK_EQ(filter_calls, 2048);
	CHECK_EQ(source.size(), 2048);
}

TEST_CASE("[ArrayFilterLazy] All accepted retains source order") {
	Array source = { 4, 2, 8, 6, 0 };
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(accept_all));
	CHECK_EQ(result, source);
	CHECK_EQ(filter_calls, 5);
}

TEST_CASE("[ArrayFilterLazy] Partial acceptance keeps ordering after delayed first match") {
	Array source = { 1, 3, 5, 2, 7, 4, 9, 6 };
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(accept_even));
	Array expected = { 2, 4, 6 };
	CHECK_EQ(result, expected);
	CHECK_EQ(filter_calls, 8);
	CHECK_EQ(source.size(), 8);
}

TEST_CASE("[ArrayFilterLazy] Late first match allocates only the remaining suffix") {
	Array source;
	for (int i = 0; i < 4096; i++) {
		source.append(i);
	}
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(accept_last));
	REQUIRE_EQ(result.size(), 1);
	CHECK_EQ(result[0], Variant(4095));
	CHECK_EQ(filter_calls, 4096);
}

TEST_CASE("[ArrayFilterLazy] Empty typed results preserve the typed element constraint") {
	TypedArray<int> source = { 1, 2, 3 };
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(reject_all));
	CHECK(result.is_typed());
	CHECK_EQ(result.get_typed_builtin(), uint32_t(Variant::INT));
	CHECK(result.is_empty());
	CHECK_EQ(filter_calls, 3);
}

TEST_CASE("[ArrayFilterLazy] Nonempty typed results preserve the typed element constraint") {
	TypedArray<int> source = { 1, 2, 3, 4 };
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(accept_even));
	Array expected = { 2, 4 };
	CHECK_EQ(result, expected);
	CHECK(result.is_typed());
	CHECK_EQ(result.get_typed_builtin(), uint32_t(Variant::INT));
	CHECK_EQ(filter_calls, 4);
}

TEST_CASE("[ArrayFilterLazy] Empty input does not invoke the callable") {
	Array source;
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(reject_all));
	CHECK(result.is_empty());
	CHECK_EQ(filter_calls, 0);
}

TEST_CASE("[ArrayFilterLazy] Source mutations from callbacks preserve observed values") {
	Array source = { 1, 2, 3 };
	filter_source = &source;
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(mutate_following_value));
	filter_source = nullptr;
	Array expected = { 1, 200, 3 };
	CHECK_EQ(result, expected);
	CHECK_EQ(source, expected);
	CHECK_EQ(filter_calls, 3);
}

TEST_CASE("[ArrayFilterLazy] Growing the source from callbacks never overruns result storage") {
	Array source = { 1, 2 };
	filter_source = &source;
	source_extended = false;
	filter_calls = 0;
	Array result = source.filter(callable_mp_static(append_to_source_late));
	filter_source = nullptr;
	Array expected = { 1, 2, 3 };
	CHECK_EQ(result, expected);
	CHECK_EQ(filter_calls, 3);
}

TEST_CASE("[ArrayFilterLazy] Repeated empty-filter queries do not change input") {
	Array source = { 10, 20, 30, 40 };
	filter_calls = 0;
	for (int i = 0; i < 128; i++) {
		Array result = source.filter(callable_mp_static(reject_all));
		CHECK(result.is_empty());
	}
	CHECK_EQ(filter_calls, 4 * 128);
	CHECK_EQ(source, Array({ 10, 20, 30, 40 }));
}

} // namespace TestArrayFilterLazy
