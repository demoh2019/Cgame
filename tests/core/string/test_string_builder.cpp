/**************************************************************************/
/*  test_string_builder.cpp                                               */
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

TEST_FORCE_LINK(test_string_builder)

#include "core/string/string_builder.h"

namespace TestStringBuilder {

TEST_CASE("[StringBuilder] Return a single existing String without copying its buffer") {
	const String original = U"res://длинный/путь/сцена.tscn";
	StringBuilder builder;
	builder.append(original);

	CHECK(builder.num_strings_appended() == 1);
	CHECK(builder.get_string_length() == uint32_t(original.length()));

	String result = builder.as_string();
	CHECK(result == original);
	CHECK(result.ptr() == original.ptr());
	CHECK(builder.as_string().ptr() == original.ptr());
}

TEST_CASE("[StringBuilder] Preserve order and content of mixed strings") {
	const String middle = U"テスト";
	StringBuilder builder;
	builder.append("prefix/");
	builder.append(middle);
	builder.append("/suffix");

	CHECK(builder.num_strings_appended() == 3);
	CHECK(builder.as_string() == String("prefix/") + middle + "/suffix");
}

TEST_CASE("[StringBuilder] Empty segments remain empty") {
	StringBuilder builder;
	CHECK(builder.as_string().is_empty());
	builder.append(String());
	builder.append("");
	CHECK(builder.get_string_length() == 0);
	CHECK(builder.as_string().is_empty());
}

TEST_CASE("[StringBuilder] Empty C-string fragments do not allocate fragment metadata") {
	StringBuilder builder;
	for (int i = 0; i < 1024; i++) {
		builder.append("");
	}
	CHECK(builder.num_strings_appended() == 0);
	CHECK(builder.get_string_length() == 0);
	CHECK(builder.as_string().is_empty());

	const String original = U"scene/テスト";
	builder.append(original);
	for (int i = 0; i < 1024; i++) {
		builder.append("");
	}
	CHECK(builder.num_strings_appended() == 1);
	CHECK(builder.get_string_length() == uint32_t(original.length()));
	CHECK(builder.as_string().ptr() == original.ptr());

	builder.append("/end");
	CHECK(builder.num_strings_appended() == 2);
	CHECK(builder.as_string() == original + "/end");
}

} // namespace TestStringBuilder
