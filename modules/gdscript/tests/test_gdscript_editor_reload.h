/**************************************************************************/
/*  test_gdscript_editor_reload.h                                         */
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

#ifdef TOOLS_ENABLED

#include "core/config/engine.h"
#include "core/object/callable_mp.h"
#include "modules/gdscript/gdscript.h"
#include "scene/main/node.h"
#include "tests/test_macros.h"

namespace TestGDScriptEditorReload {

class PropertyListProbe : public Object {
	GDCLASS(PropertyListProbe, Object);

	int notifications = 0;

protected:
	static void _bind_methods() {}

public:
	void changed() { notifications++; }
	int get_count() const { return notifications; }
};

static bool has_property(Object *p_owner, const StringName &p_property) {
	List<PropertyInfo> properties;
	p_owner->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (property.name == p_property) {
			return true;
		}
	}
	return false;
}

static String get_property_hint(Object *p_owner, const StringName &p_property) {
	List<PropertyInfo> properties;
	p_owner->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (property.name == p_property) {
			return property.hint_string;
		}
	}
	return String();
}

TEST_CASE("[Editor][GDScriptReload] Script reload notifies a live owner of export changes") {
	CHECK(Engine::get_singleton()->is_editor_hint());

	Ref<GDScript> script;
	script.instantiate();
	script->set_source_code("@tool\nextends Node\n@export_range(1, 10) var speed: int = 5\n");
	REQUIRE_EQ(script->reload(), OK);

	Node *owner = memnew(Node);
	owner->set_script(script);
	REQUIRE(owner->get_script_instance() != nullptr);
	PropertyListProbe *probe = memnew(PropertyListProbe);
	owner->connect(SNAME("property_list_changed"), callable_mp(probe, &PropertyListProbe::changed));

	const String previous_hint = get_property_hint(owner, SNAME("speed"));
	CHECK(previous_hint.contains("10"));
	script->set_source_code("@tool\nextends Node\n@export_range(2, 20) var speed: int = 5\n");
	CHECK_EQ(script->reload(true), OK);
	CHECK(probe->get_count() >= 1);
	CHECK(get_property_hint(owner, SNAME("speed")).contains("20"));

	memdelete(owner);
	memdelete(probe);
}

TEST_CASE("[Editor][GDScriptReload] Notifies every live instance owner") {
	Ref<GDScript> script;
	script.instantiate();
	script->set_source_code("@tool\nextends Node\n@export var level: int = 1\n");
	REQUIRE_EQ(script->reload(), OK);

	Node *first = memnew(Node);
	Node *second = memnew(Node);
	first->set_script(script);
	second->set_script(script);
	PropertyListProbe *a = memnew(PropertyListProbe);
	PropertyListProbe *b = memnew(PropertyListProbe);
	first->connect(SNAME("property_list_changed"), callable_mp(a, &PropertyListProbe::changed));
	second->connect(SNAME("property_list_changed"), callable_mp(b, &PropertyListProbe::changed));

	script->set_source_code("@tool\nextends Node\n@export_range(1, 100) var level: int = 1\n");
	CHECK_EQ(script->reload(true), OK);
	CHECK(a->get_count() >= 1);
	CHECK(b->get_count() >= 1);

	memdelete(first);
	memdelete(second);
	memdelete(a);
	memdelete(b);
}

TEST_CASE("[Editor][GDScriptReload] Remains safe after an owner is destroyed") {
	Ref<GDScript> script;
	script.instantiate();
	script->set_source_code("@tool\nextends Node\n@export var item: String = \"A\"\n");
	REQUIRE_EQ(script->reload(), OK);

	Node *released = memnew(Node);
	Node *remaining = memnew(Node);
	released->set_script(script);
	remaining->set_script(script);
	memdelete(released);

	PropertyListProbe *probe = memnew(PropertyListProbe);
	remaining->connect(SNAME("property_list_changed"), callable_mp(probe, &PropertyListProbe::changed));
	script->set_source_code("@tool\nextends Node\n@export var item: String = \"B\"\n@export var count: int = 1\n");
	CHECK_EQ(script->reload(true), OK);
	CHECK(probe->get_count() >= 1);
	CHECK(has_property(remaining, SNAME("count")));

	memdelete(remaining);
	memdelete(probe);
}

TEST_CASE("[Editor][GDScriptReload] Keeps the editor stable with no live owners") {
	Ref<GDScript> script;
	script.instantiate();
	script->set_source_code("@tool\nextends Node\n@export var score: int = 0\n");
	REQUIRE_EQ(script->reload(), OK);
	script->set_source_code("@tool\nextends Node\n@export_range(0, 100) var score: int = 0\n");
	CHECK_EQ(script->reload(true), OK);
	CHECK(script->can_instantiate());
}

TEST_CASE("[Editor][GDScriptReload] Skips owner refresh outside editor mode") {
	Ref<GDScript> script;
	script.instantiate();
	script->set_source_code("@tool\nextends Node\n@export var count: int = 1\n");
	REQUIRE_EQ(script->reload(), OK);
	Node *owner = memnew(Node);
	owner->set_script(script);
	PropertyListProbe *probe = memnew(PropertyListProbe);
	owner->connect(SNAME("property_list_changed"), callable_mp(probe, &PropertyListProbe::changed));

	Engine::get_singleton()->set_editor_hint(false);
	script->set_source_code("@tool\nextends Node\n@export var count: int = 2\n");
	const Error err = script->reload(true);
	Engine::get_singleton()->set_editor_hint(true);
	CHECK_EQ(err, OK);
	CHECK_EQ(probe->get_count(), 0);

	memdelete(owner);
	memdelete(probe);
}

} // namespace TestGDScriptEditorReload

#endif // TOOLS_ENABLED
