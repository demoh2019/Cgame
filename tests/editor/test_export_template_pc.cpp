/**************************************************************************/
/*  test_export_template_pc.cpp                                           */
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

TEST_FORCE_LINK(test_export_template_pc)

#ifdef TOOLS_ENABLED

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "editor/export/editor_export_platform_pc.h"
#include "editor/export/editor_export_preset.h"
#include "tests/test_utils.h"

namespace TestExportTemplatePC {

// The real preset stores values via EditorExport::singleton, which may not
// exist in a headless unit-test run. Use the same Object::get() interface,
// overriding only the values required by the resolver under test.
class TestPreset : public EditorExportPreset {
	GDCLASS(TestPreset, EditorExportPreset);

	HashMap<StringName, Variant> options;

protected:
	static void _bind_methods() {}

	bool _get(const StringName &p_name, Variant &r_ret) const {
		const Variant *value = options.getptr(p_name);
		if (value) {
			r_ret = *value;
			return true;
		}
		return EditorExportPreset::_get(p_name, r_ret);
	}

public:
	void put(const StringName &p_name, const Variant &p_value) {
		options[p_name] = p_value;
	}
};

class TestPCPlatform : public EditorExportPlatformPC {
public:
	virtual List<String> get_binary_extensions(const Ref<EditorExportPreset> &p_preset) const override {
		return List<String>();
	}

	virtual String get_template_file_name(const String &p_target, const String &p_arch) const override {
		return "cgame_test_missing_template_" + p_target + "_" + p_arch + ".bin";
	}
};

class Fixture {
public:
	Ref<TestPreset> preset_impl;
	Ref<EditorExportPreset> preset;
	Ref<TestPCPlatform> platform;
	String dir;
	String debug_path;
	String release_path;

	Fixture() {
		preset_impl.instantiate();
		preset = preset_impl;
		preset_impl->put("binary_format/architecture", "x86_64");
		preset_impl->put("custom_template/debug", "");
		preset_impl->put("custom_template/release", "");
		platform.instantiate();

		dir = TestUtils::get_temp_path("export_template_pc");
		DirAccess::make_dir_recursive_absolute(dir);
		debug_path = dir.path_join("custom_debug.exe");
		release_path = dir.path_join("custom_release.exe");

		Ref<FileAccess> debug_file = FileAccess::open(debug_path, FileAccess::WRITE);
		if (debug_file.is_valid()) {
			debug_file->store_string("debug template");
			debug_file->flush();
		}
		Ref<FileAccess> release_file = FileAccess::open(release_path, FileAccess::WRITE);
		if (release_file.is_valid()) {
			release_file->store_string("release template");
			release_file->flush();
		}
	}

	~Fixture() {
		DirAccess::remove_absolute(debug_path);
		DirAccess::remove_absolute(release_path);
	}

	bool has_files() const {
		return FileAccess::exists(debug_path) && FileAccess::exists(release_path);
	}
};

TEST_CASE("[Editor][ExportTemplatePC] Custom debug template is preferred when it exists") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/debug", f.debug_path);
	String error;
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "debug", &error), f.debug_path);
	CHECK(error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Custom release template is preferred when it exists") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/release", f.release_path);
	String error;
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "release", &error), f.release_path);
	CHECK(error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Surrounding whitespace is trimmed from custom paths") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/debug", "  \t" + f.debug_path + "\n  ");
	String error;
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "debug", &error), f.debug_path);
	CHECK(error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Missing debug custom template is reported") {
	Fixture f;
	f.preset_impl->put("custom_template/debug", f.dir.path_join("missing_debug.exe"));
	String error;
	CHECK(f.platform->get_export_template_to_use(f.preset, "debug", &error).is_empty());
	CHECK_FALSE(error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Missing release custom template is reported") {
	Fixture f;
	f.preset_impl->put("custom_template/release", f.dir.path_join("missing_release.exe"));
	String error;
	CHECK(f.platform->get_export_template_to_use(f.preset, "release", &error).is_empty());
	CHECK_FALSE(error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Missing custom template is not silently replaced with official template") {
	Fixture f;
	f.preset_impl->put("custom_template/debug", f.dir.path_join("explicitly_missing_debug.exe"));
	String error = "existing warning\n";
	CHECK(f.platform->get_export_template_to_use(f.preset, "debug", &error).is_empty());
	CHECK(error.begins_with("existing warning\n"));
	CHECK(error.length() > String("existing warning\n").length());
}

TEST_CASE("[Editor][ExportTemplatePC] Debug and release settings are independent") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/debug", f.debug_path);
	f.preset_impl->put("custom_template/release", f.release_path);
	String debug_error, release_error;
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "debug", &debug_error), f.debug_path);
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "release", &release_error), f.release_path);
	CHECK(debug_error.is_empty());
	CHECK(release_error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Missing debug custom template does not prevent valid release") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/debug", f.dir.path_join("missing_debug.exe"));
	f.preset_impl->put("custom_template/release", f.release_path);
	String debug_error, release_error;
	CHECK(f.platform->get_export_template_to_use(f.preset, "debug", &debug_error).is_empty());
	CHECK_FALSE(debug_error.is_empty());
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "release", &release_error), f.release_path);
	CHECK(release_error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Missing release custom template does not prevent valid debug") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/debug", f.debug_path);
	f.preset_impl->put("custom_template/release", f.dir.path_join("missing_release.exe"));
	String debug_error, release_error;
	CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "debug", &debug_error), f.debug_path);
	CHECK(debug_error.is_empty());
	CHECK(f.platform->get_export_template_to_use(f.preset, "release", &release_error).is_empty());
	CHECK_FALSE(release_error.is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Error message pointer is optional") {
	Fixture f;
	f.preset_impl->put("custom_template/debug", f.dir.path_join("missing_debug.exe"));
	CHECK(f.platform->get_export_template_to_use(f.preset, "debug").is_empty());
}

TEST_CASE("[Editor][ExportTemplatePC] Custom path resolution is stable across repeated calls") {
	Fixture f;
	REQUIRE(f.has_files());
	f.preset_impl->put("custom_template/debug", f.debug_path);
	for (int i = 0; i < 10; i++) {
		String error;
		CHECK_EQ(f.platform->get_export_template_to_use(f.preset, "debug", &error), f.debug_path);
		CHECK(error.is_empty());
	}
}

TEST_CASE("[Editor][ExportTemplatePC] Empty custom path uses official-template lookup") {
	Fixture f;
	f.preset_impl->put("custom_template/debug", "  \n\t ");
	// The dummy platform returns a deliberately nonexistent official template name.
	String error;
	CHECK(f.platform->get_export_template_to_use(f.preset, "debug", &error).is_empty());
}

} // namespace TestExportTemplatePC

#endif // TOOLS_ENABLED
