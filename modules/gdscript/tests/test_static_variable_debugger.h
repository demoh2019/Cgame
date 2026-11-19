/**************************************************************************/
/*  test_static_variable_debugger.h                                       */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, ARISING FROM, OUT OF OR IN CONNECTION */
/* WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.         */
/**************************************************************************/

#pragma once

#include "core/object/script_backtrace.h"
#include "modules/gdscript/gdscript.h"
#include "modules/gdscript/gdscript_cache.h"
#include "tests/test_macros.h"

namespace TestGDScriptStaticDebugger {

TEST_CASE("[GDScriptStaticDebugger] ScriptBacktrace binds all three static variable accessors") {
	Ref<ScriptBacktrace> trace;
	trace.instantiate();
	REQUIRE(trace.is_valid());
	CHECK(trace->has_method(SNAME("get_static_variable_count")));
	CHECK(trace->has_method(SNAME("get_static_variable_name")));
	CHECK(trace->has_method(SNAME("get_static_variable_value")));
	CHECK_EQ(trace->get_static_variable_count(), 0);
}

TEST_CASE("[GDScriptStaticDebugger] Empty backtrace returns safe out of range values") {
	Ref<ScriptBacktrace> trace;
	trace.instantiate();
	ERR_PRINT_OFF;
	CHECK(trace->get_static_variable_name(-1).is_empty());
	CHECK(trace->get_static_variable_name(0).is_empty());
	CHECK_EQ(trace->get_static_variable_value(-1), Variant(String()));
	CHECK_EQ(trace->get_static_variable_value(0), Variant(String()));
	ERR_PRINT_ON;
}

TEST_CASE("[GDScriptStaticDebugger] Static script cache exposes only valid Ref objects") {
	List<Ref<GDScript>> scripts;
	GDScriptCache::get_static_scripts(&scripts);
	for (const Ref<GDScript> &script : scripts) {
		CHECK(script.is_valid());
	}
}

TEST_CASE("[GDScriptStaticDebugger] Static variable names and values stay aligned") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();
	REQUIRE(lang != nullptr);
	List<String> names;
	List<Variant> values;
	lang->debug_get_static_variables(&names, &values);
	CHECK_EQ(names.size(), values.size());
	for (const String &name : names) {
		CHECK_FALSE(name.is_empty());
		CHECK(name.contains("/"));
	}
}

TEST_CASE("[GDScriptStaticDebugger] Backtrace includes statics only when capture requests variables") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();
	REQUIRE(lang != nullptr);
	List<String> names;
	List<Variant> values;
	lang->debug_get_static_variables(&names, &values);

	ScriptBacktrace excluded(lang, false);
	ScriptBacktrace included(lang, true);
	CHECK_EQ(excluded.get_static_variable_count(), 0);
	CHECK_EQ(included.get_static_variable_count(), names.size());
	for (int i = 0; i < included.get_static_variable_count(); i++) {
		const String result_name = included.get_static_variable_name(i);
		CHECK_FALSE(result_name.is_empty());
		CHECK(result_name.contains("/"));
	}
}

} // namespace TestGDScriptStaticDebugger
