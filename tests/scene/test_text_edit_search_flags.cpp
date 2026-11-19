/**************************************************************************/
/*  test_text_edit_search_flags.cpp                                       */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_text_edit_search_flags)

#include "scene/gui/text_edit.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

namespace TestTextEditSearchFlags {

TEST_CASE("[SceneTree][TextEditSearchFlags] Add next occurrence is case insensitive when configured") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat CAT catalog cat");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(0);
	edit->add_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 2);
	CHECK_EQ(edit->get_selection_from_column(1), 4);
	CHECK_EQ(edit->get_selection_to_column(1), 7);
	CHECK_EQ(edit->get_selected_text(1), "CAT");
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] Add next occurrence honors whole word matching") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat catalog cat");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(TextEdit::SEARCH_MATCH_CASE | TextEdit::SEARCH_WHOLE_WORDS);
	edit->add_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 2);
	CHECK_EQ(edit->get_selection_from_column(1), 12);
	CHECK_EQ(edit->get_selection_to_column(1), 15);
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] Add next occurrence remains case sensitive when requested") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat CAT cat");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(TextEdit::SEARCH_MATCH_CASE);
	edit->add_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 2);
	CHECK_EQ(edit->get_selection_from_column(1), 8);
	CHECK_EQ(edit->get_selected_text(1), "cat");
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] Skip to next occurrence honors case insensitive search") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat CAT catalog cat");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(0);
	edit->skip_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 1);
	CHECK(edit->has_selection(0));
	CHECK_EQ(edit->get_selection_from_column(0), 4);
	CHECK_EQ(edit->get_selected_text(0), "CAT");
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] Skip to next occurrence honors whole word matching") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat catalog cat");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(TextEdit::SEARCH_WHOLE_WORDS | TextEdit::SEARCH_MATCH_CASE);
	edit->skip_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 1);
	CHECK_EQ(edit->get_selection_from_column(0), 12);
	CHECK_EQ(edit->get_selected_text(0), "cat");
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] Next occurrence follows case insensitive matching across lines") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat\nCAT");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(0);
	edit->add_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 2);
	CHECK_EQ(edit->get_selection_from_line(1), 1);
	CHECK_EQ(edit->get_selection_from_column(1), 0);
	CHECK_EQ(edit->get_selected_text(1), "CAT");
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] Whole words and case insensitive search combine") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat catalog CAT");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(TextEdit::SEARCH_WHOLE_WORDS);
	edit->add_selection_for_next_occurrence();
	REQUIRE_EQ(edit->get_caret_count(), 2);
	CHECK_EQ(edit->get_selection_from_column(1), 12);
	CHECK_EQ(edit->get_selected_text(1), "CAT");
	memdelete(edit);
}

TEST_CASE("[SceneTree][TextEditSearchFlags] No extra caret for a missing whole word match") {
	TextEdit *edit = memnew(TextEdit);
	SceneTree::get_singleton()->get_root()->add_child(edit);
	edit->set_text("cat catalog");
	edit->select(0, 0, 0, 3);
	edit->set_search_flags(TextEdit::SEARCH_MATCH_CASE | TextEdit::SEARCH_WHOLE_WORDS);
	edit->add_selection_for_next_occurrence();
	CHECK_EQ(edit->get_caret_count(), 1);
	CHECK_EQ(edit->get_selected_text(), "cat");
	memdelete(edit);
}

} // namespace TestTextEditSearchFlags
