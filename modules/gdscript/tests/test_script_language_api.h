/**************************************************************************/
/*  test_script_language_api.h                                            */
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

#include "modules/gdscript/gdscript.h"
#include "tests/test_macros.h"

namespace GDScriptTests {

TEST_CASE("[GDScript] Script exposes its owning language directly") {
	Ref<GDScript> first;
	first.instantiate();
	REQUIRE(first.is_valid());

	ScriptLanguage *language = first->get_language();
	REQUIRE(language != nullptr);
	CHECK_EQ(language, GDScriptLanguage::get_singleton());
	CHECK_EQ(language->get_type(), first->get_class());
	CHECK(language->can_inherit_from_file());

	Ref<GDScript> second;
	second.instantiate();
	REQUIRE(second.is_valid());
	CHECK_EQ(second->get_language(), language);
}

TEST_CASE("[GDScript] Script language remains available with valid and malformed source") {
	Ref<GDScript> script;
	script.instantiate();
	REQUIRE(script.is_valid());

	ScriptLanguage *language = script->get_language();
	REQUIRE(language != nullptr);

	// The editor must be able to identify a script's language even while
	// its source is incomplete or contains an error.
	script->set_source_code("extends Node\n");
	CHECK_EQ(script->get_language(), language);

	script->set_source_code("extends ???\n");
	CHECK_EQ(script->get_language(), language);

	script->set_source_code("");
	CHECK_EQ(script->get_language(), language);
}

} // namespace GDScriptTests
