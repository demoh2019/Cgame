/**************************************************************************/
/*  test_gdscript_constants.h                                             */
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

#include "../gdscript.h"
#include "../gdscript_constants.h"

#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestGDScriptConstants {

TEST_CASE("[GDScript] Built-in constant names and values") {
	const char *names[] = { "PI", "TAU", "INF", "NAN" };
	REQUIRE_EQ(GDScriptConstants::get_constant_count(), 4);
	for (int i = 0; i < 4; i++) {
		INFO("Constant index: ", i);
		CHECK_EQ(String(GDScriptConstants::get_constant_name(i)), String(names[i]));
		CHECK_EQ(GDScriptConstants::get_constant_index(StringName(names[i])), i);
		CHECK(GDScriptConstants::is_constant(StringName(names[i])));
		CHECK_EQ(GDScriptConstants::get_constant_value(i).get_type(), Variant::FLOAT);
	}
	CHECK(Math::is_equal_approx(double(GDScriptConstants::get_constant_value(0)), double(Math::PI)));
	CHECK(Math::is_equal_approx(double(GDScriptConstants::get_constant_value(1)), double(Math::TAU)));
	CHECK(Math::is_inf(double(GDScriptConstants::get_constant_value(2))));
	CHECK(Math::is_nan(double(GDScriptConstants::get_constant_value(3))));
}

TEST_CASE("[GDScript] Built-in constant names are case-sensitive") {
	for (const char *invalid : { "", "pi", "tau", "inf", "nan", "Pi", "TRUE", "true", "false", "null", "self", "super", "random" }) {
		INFO("Invalid constant: ", invalid);
		CHECK_FALSE(GDScriptConstants::is_constant(StringName(invalid)));
		CHECK_EQ(GDScriptConstants::get_constant_index(StringName(invalid)), -1);
	}
}

#ifdef TOOLS_ENABLED
TEST_CASE("[GDScript] Public documented constants match runtime definitions") {
	GDScriptLanguage *language = GDScriptLanguage::get_singleton();
	REQUIRE(language != nullptr);
	List<Pair<String, Variant>> documented;
	language->get_public_constants(&documented);
	REQUIRE_EQ(documented.size(), GDScriptConstants::get_constant_count());
	int index = 0;
	for (const Pair<String, Variant> &entry : documented) {
		INFO("Constant index: ", index);
		CHECK_EQ(entry.first, String(GDScriptConstants::get_constant_name(index)));
		CHECK_EQ(entry.second.get_type(), Variant::FLOAT);
		if (index == 3) {
			CHECK(Math::is_nan(double(entry.second)));
		} else {
			CHECK_EQ(double(entry.second), double(GDScriptConstants::get_constant_value(index)));
		}
		index++;
	}
}
#endif // TOOLS_ENABLED

} // namespace TestGDScriptConstants
