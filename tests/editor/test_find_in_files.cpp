/**************************************************************************/
/*  test_find_in_files.cpp                                                */
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

TEST_FORCE_LINK(test_find_in_files)

#ifdef TOOLS_ENABLED

#include "editor/script/find_in_files.h"
#include "editor/settings/editor_settings.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

namespace TestFindInFiles {

TEST_CASE("[Editor][FindInFiles] Search panel synchronizes extension filters") {
	EditorSettings *settings = EditorSettings::get_singleton();
	REQUIRE(settings != nullptr);
	const String setting = "text_editor/behavior/general/find_in_file_extensions";
	const PackedStringArray previous_extensions = settings->get_setting(setting);

	PackedStringArray extensions;
	extensions.push_back("gd");
	extensions.push_back("tscn");
	settings->set_setting(setting, extensions);

	FindInFilesSearch *finder = memnew(FindInFilesSearch);
	FindInFilesSearchPanel *panel = memnew(FindInFilesSearchPanel);
	SceneTree::get_singleton()->get_root()->add_child(panel);

	// Newly-created search tabs must include their selected extensions.
	panel->set_finder(finder, true);
	CHECK(finder->get_filter()->has("gd"));
	CHECK(finder->get_filter()->has("tscn"));
	CHECK_EQ(finder->get_filter()->size(), 2);

	// Switching to a search tab must preserve its own selected extensions.
	HashSet<String> only_gd;
	only_gd.insert("gd");
	finder->set_filter(only_gd);
	panel->set_finder(finder, false);
	CHECK(finder->get_filter()->has("gd"));
	CHECK_FALSE(finder->get_filter()->has("tscn"));
	CHECK_EQ(finder->get_filter()->size(), 1);

	// Switching to an intentionally empty filter must not restore old filters.
	finder->set_filter(HashSet<String>());
	panel->set_finder(finder, false);
	CHECK(finder->get_filter()->is_empty());

	// Switching between search tabs must retain each tab's independent filter.
	FindInFilesSearch *other_finder = memnew(FindInFilesSearch);
	other_finder->set_filter(only_gd);
	panel->set_finder(other_finder, false);
	CHECK(other_finder->get_filter()->has("gd"));
	CHECK_FALSE(other_finder->get_filter()->has("tscn"));
	panel->set_finder(finder, false);
	CHECK(finder->get_filter()->is_empty());
	panel->set_finder(other_finder, false);
	CHECK_EQ(other_finder->get_filter()->size(), 1);
	CHECK(other_finder->get_filter()->has("gd"));

	memdelete(panel);
	memdelete(other_finder);
	memdelete(finder);
	settings->set_setting(setting, previous_extensions);
}

} // namespace TestFindInFiles

#endif // TOOLS_ENABLED
