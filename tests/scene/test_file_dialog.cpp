/**************************************************************************/
/*  test_file_dialog.cpp                                                  */
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
/* distribute, sublicense, and sell copies of the Software, and to        */
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

TEST_FORCE_LINK(test_file_dialog)

#include "core/string/translation.h"
#include "core/string/translation_server.h"
#include "scene/gui/file_dialog.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "tests/display_server_mock.h"

namespace TestFileDialog {

struct NativeDialogFixture {
	DisplayServerMock *server = static_cast<DisplayServerMock *>(DisplayServer::get_singleton());
	TranslationServer *translation_server = TranslationServer::get_singleton();
	String original_locale = translation_server->get_locale();
	Ref<Translation> translation;
	FileDialog *dialog = nullptr;

	NativeDialogFixture() {
		server->set_native_dialog_extra_enabled(true);
		dialog = memnew(FileDialog);
		SceneTree::get_singleton()->get_root()->add_child(dialog);
		dialog->set_use_native_dialog(true);
	}

	~NativeDialogFixture() {
		memdelete(dialog);
		translation_server->set_locale(original_locale);
		if (translation.is_valid()) {
			translation_server->remove_translation(translation);
		}
		server->set_native_dialog_extra_enabled(false);
	}

	void install_translation() {
		translation.instantiate();
		translation->set_locale("es");
		translation->add_message("Quality", "Calidad");
		translation->add_message("Low", "Baja");
		translation->add_message("High", "Alta");
		translation->add_message("Include metadata", "Incluir metadatos");
		translation->add_message("Resolution", "Resolución");
		translation->add_message("Small", "Pequeña");
		translation->add_message("Large", "Grande");
		translation_server->add_translation(translation);
	}

	TypedArray<Dictionary> show_native_dialog() {
		dialog->set_visible(true);
		return server->get_captured_native_dialog_options();
	}
};

TEST_CASE("[SceneTree][FileDialog] Native options translate names, values and checkboxes") {
	NativeDialogFixture fixture;
	fixture.install_translation();
	fixture.translation_server->set_locale("es");
	fixture.dialog->add_option("Quality", { "Low", "High" }, 1);
	fixture.dialog->add_option("Include metadata", {}, 1);

	TypedArray<Dictionary> native_options = fixture.show_native_dialog();
	REQUIRE(native_options.size() == 2);
	Dictionary quality = native_options[0];
	Dictionary checkbox = native_options[1];
	PackedStringArray values = quality["values"];
	CHECK(String(quality["name"]) == "Calidad");
	REQUIRE(values.size() == 2);
	CHECK(values[0] == "Baja");
	CHECK(values[1] == "Alta");
	CHECK(int(quality["default"]) == 1);
	CHECK(String(checkbox["name"]) == "Incluir metadatos");
	CHECK(PackedStringArray(checkbox["values"]).is_empty());
	CHECK(int(checkbox["default"]) == 1);

	// The public API and selection keys must continue to use untranslated names.
	CHECK(fixture.dialog->get_option_name(0) == "Quality");
	CHECK(fixture.dialog->get_option_values(0)[0] == "Low");
	CHECK(fixture.dialog->get_selected_options().has("Quality"));
	CHECK(fixture.dialog->get_selected_options().has("Include metadata"));
}

TEST_CASE("[SceneTree][FileDialog] Native options respond to locale and option changes") {
	NativeDialogFixture fixture;
	fixture.install_translation();
	fixture.translation_server->set_locale("en");
	fixture.dialog->add_option("Quality", { "Low", "High" }, 0);

	TypedArray<Dictionary> native_options = fixture.show_native_dialog();
	REQUIRE(native_options.size() == 1);
	CHECK(String(Dictionary(native_options[0])["name"]) == "Quality");

	fixture.translation_server->set_locale("es");
	SceneTree::get_singleton()->process(0);
	native_options = fixture.show_native_dialog();
	REQUIRE(native_options.size() == 1);
	CHECK(String(Dictionary(native_options[0])["name"]) == "Calidad");

	fixture.dialog->set_option_name(0, "Resolution");
	fixture.dialog->set_option_values(0, { "Small", "Large" });
	fixture.dialog->set_option_default(0, 1);
	native_options = fixture.show_native_dialog();
	REQUIRE(native_options.size() == 1);
	Dictionary option = native_options[0];
	PackedStringArray values = option["values"];
	CHECK(String(option["name"]) == "Resolución");
	REQUIRE(values.size() == 2);
	CHECK(values[0] == "Pequeña");
	CHECK(values[1] == "Grande");
	CHECK(int(option["default"]) == 1);

	// Switching back to the project locale should not retain translated labels.
	fixture.translation_server->set_locale("en");
	SceneTree::get_singleton()->process(0);
	native_options = fixture.show_native_dialog();
	REQUIRE(native_options.size() == 1);
	CHECK(String(Dictionary(native_options[0])["name"]) == "Resolution");
}

TEST_CASE("[SceneTree][FileDialog] Native callbacks retain untranslated option keys and selections") {
	NativeDialogFixture fixture;
	fixture.install_translation();
	fixture.translation_server->set_locale("es");
	fixture.dialog->set_file_mode(FileDialog::FILE_MODE_OPEN_ANY);
	fixture.dialog->add_option("Quality", { "Low", "High" }, 1);
	fixture.dialog->add_option("Include metadata", {}, 0);
	fixture.show_native_dialog();

	Dictionary chosen;
	chosen["Calidad"] = 0;
	chosen["Incluir metadatos"] = true;
	Vector<String> files;
	files.push_back("res://native-file-dialog-regression.txt");
	fixture.server->get_captured_native_dialog_callback().call(true, files, 0, chosen);

	Dictionary selection = fixture.dialog->get_selected_options();
	CHECK(selection.has("Quality"));
	CHECK(selection.has("Include metadata"));
	CHECK_FALSE(selection.has("Calidad"));
	CHECK(int(selection["Quality"]) == 0);
	CHECK(bool(selection["Include metadata"]));

	// The subsequent native dialog must show the user's selection, not the defaults.
	TypedArray<Dictionary> native_options = fixture.show_native_dialog();
	REQUIRE(native_options.size() == 2);
	CHECK(int(Dictionary(native_options[0])["default"]) == 0);
	CHECK(int(Dictionary(native_options[1])["default"]) == 1);
}

TEST_CASE("[SceneTree][FileDialog] Native callbacks accept untranslated option keys") {
	NativeDialogFixture fixture;
	fixture.install_translation();
	fixture.translation_server->set_locale("es");
	fixture.dialog->set_file_mode(FileDialog::FILE_MODE_OPEN_ANY);
	fixture.dialog->add_option("Quality", { "Low", "High" }, 1);
	fixture.show_native_dialog();

	// A platform backend may return the original option key instead of its label.
	Dictionary chosen;
	chosen["Quality"] = 0;
	chosen["Unknown option"] = 1;
	Vector<String> files;
	files.push_back("res://native-dialog-original-key.txt");
	fixture.server->get_captured_native_dialog_callback().call(true, files, 0, chosen);

	Dictionary selection = fixture.dialog->get_selected_options();
	CHECK(selection.has("Quality"));
	CHECK_FALSE(selection.has("Calidad"));
	CHECK_FALSE(selection.has("Unknown option"));
	CHECK(int(selection["Quality"]) == 0);

	TypedArray<Dictionary> next_options = fixture.show_native_dialog();
	REQUIRE(next_options.size() == 1);
	CHECK(String(Dictionary(next_options[0])["name"]) == "Calidad");
	CHECK(int(Dictionary(next_options[0])["default"]) == 0);
}

TEST_CASE("[SceneTree][FileDialog] Cancelling the native dialog leaves the selection intact") {
	NativeDialogFixture fixture;
	fixture.install_translation();
	fixture.translation_server->set_locale("es");
	fixture.dialog->add_option("Quality", { "Low", "High" }, 1);
	fixture.show_native_dialog();

	// A cancelled OS dialog must not overwrite the previous selection.
	Dictionary selected;
	selected["Calidad"] = 0;
	fixture.server->get_captured_native_dialog_callback().call(false, Vector<String>(), 0, selected);

	Dictionary after_cancel = fixture.dialog->get_selected_options();
	CHECK(after_cancel.has("Quality"));
	CHECK(int(after_cancel["Quality"]) == 1);
	CHECK_FALSE(after_cancel.has("Calidad"));

	TypedArray<Dictionary> reopened = fixture.show_native_dialog();
	REQUIRE(reopened.size() == 1);
	CHECK(String(Dictionary(reopened[0])["name"]) == "Calidad");
	CHECK(int(Dictionary(reopened[0])["default"]) == 1);
}

} // namespace TestFileDialog
