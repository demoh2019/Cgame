/**************************************************************************/
/*  test_string_name.cpp                                                  */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_string_name)

#include "core/string/string_name.h"

namespace TestStringName {

// These constructors execute before register_core_types() sets up the
// StringName table. Empty values must not require a configured table.
static StringName early_empty_c_string("");
static StringName early_null_c_string((const char *)nullptr);

TEST_CASE("[StringName] Empty names during static initialization") {
	CHECK(early_empty_c_string.is_empty());
	CHECK(early_null_c_string.is_empty());
	CHECK(early_empty_c_string == early_null_c_string);
	CHECK(early_empty_c_string == StringName());
	CHECK(early_null_c_string == StringName());
}

TEST_CASE("[StringName] Empty C-string construction") {
	const StringName from_null((const char *)nullptr);
	const StringName from_empty("");
	const StringName static_empty("", true);
	CHECK(from_null.is_empty());
	CHECK(from_empty.is_empty());
	CHECK(static_empty.is_empty());
	CHECK(from_null == from_empty);
	CHECK(from_empty == static_empty);
	CHECK(from_null.length() == 0);
	CHECK(from_empty.string().is_empty());
}

TEST_CASE("[StringName] Empty String construction") {
	const StringName from_string{ String() };
	const StringName from_static_string{ String(), true };
	const StringName from_c_string("");
	CHECK(from_string.is_empty());
	CHECK(from_static_string.is_empty());
	CHECK(from_string == from_c_string);
	CHECK(from_static_string == from_c_string);
	CHECK(from_string.length() == 0);
}

TEST_CASE("[StringName] Non-empty C-string and String constructors intern equally") {
	const StringName from_c_string("early-empty-regression");
	const StringName from_string(String("early-empty-regression"));
	const StringName from_static_c_string("early-empty-regression", true);
	CHECK_FALSE(from_c_string.is_empty());
	CHECK_FALSE(from_string.is_empty());
	CHECK(from_c_string == from_string);
	CHECK(from_string == from_static_c_string);
	CHECK(from_c_string.length() == 22);
	CHECK(from_c_string.string() == "early-empty-regression");
}

TEST_CASE("[StringName] Empty names stay empty after copying and assignment") {
	StringName source("");
	StringName copy(source);
	StringName target("temporary");
	target = source;
	CHECK(source.is_empty());
	CHECK(copy.is_empty());
	CHECK(target.is_empty());
	CHECK(copy == target);
	CHECK(copy == StringName((const char *)nullptr));
}

} // namespace TestStringName
