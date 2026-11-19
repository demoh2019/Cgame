/**************************************************************************/
/*  test_ai_game_builder.cpp                                              */
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

TEST_FORCE_LINK(test_ai_game_builder)

#ifdef TOOLS_ENABLED

#include "core/variant/dictionary.h"
#include "core/io/json.h"
#include "editor/plugins/ai_game_builder_plugin.h"

namespace TestAIGameBuilder {

TEST_CASE("[AIGameBuilder] Portable project paths") {
	const char *safe_paths[] = {
		"scenes/main.tscn",
		"scripts/player.gd",
		"scenes/levels/level_01.tscn",
		"resources/player.tres",
		"shaders/water.gdshader",
		"shaders/shared.gdshaderinc",
		"assets/icon.svg",
		"data/levels.json",
		"data/score.csv",
		"docs/README.md",
		"docs/help.txt",
		"A-B_C.gd",
	};
	for (const char *path : safe_paths) {
		INFO("Path: ", path);
		CHECK(AIGameBuilderPlugin::is_safe_project_path(path));
	}

	const char *unsafe_paths[] = {
		"",
		"/absolute/file.gd",
		"res://scripts/main.gd",
		"C:/outside/file.gd",
		"../secrets.gd",
		"scenes/../../outside.gd",
		"scenes/../main.gd",
		"scenes//main.gd",
		"scripts/",
		"scripts\\player.gd",
		".godot/editor/cache.gd",
		"addons/.hidden.gd",
		"scenes/.hidden.gd",
		"scenes/main.",
		"scripts/a..gd",
		"scripts/has space.gd",
		"scripts/new\nline.gd",
		"scripts/tab\tname.gd",
		"scripts/semicolon;.gd",
		"scenes/main.tscn?x=1",
		"main.exe",
		"scripts/malware.py",
		"addons/plugin.cfg",
		"project.godot",
		"assets/image.png",
		"textures/sprite.webp",
		"scripts/other.dll",
		"ресурсы/тест.gd",
		"scripts/com'quote.gd",
		"scripts/a@b.gd",
		"scripts/a#b.gd",
		"scripts/a%20b.gd",
		"scripts/a|b.gd",
		"CON.gd",
		"nul.tscn",
		"data/PRN.csv",
		"COM1.gd",
		"lpt9.tres",
		"folder/AUX/main.gd",
		"data/CON.backup.gd",
		"lpt1.test.tscn",
	};
	for (const char *path : unsafe_paths) {
		INFO("Path: ", path);
		CHECK_FALSE(AIGameBuilderPlugin::is_safe_project_path(path));
	}

	CHECK_FALSE(AIGameBuilderPlugin::is_safe_project_path(String("level/").repeat(9) + "main.gd"));
	CHECK_FALSE(AIGameBuilderPlugin::is_safe_project_path(String("a").repeat(181) + ".gd"));
	CHECK_FALSE(AIGameBuilderPlugin::is_safe_project_path(String("a").repeat(81) + ".gd"));
}

TEST_CASE("[AIGameBuilder] Accepts a minimal playable resource plan") {
	Array files;
	String summary;
	String error;
	const String response = R"json({
		"summary":"A playable scene, with a movement script.",
		"files":[
			{"path":"scenes/main.tscn","content":"[gd_scene format=3]\\n[node name=\\\"Main\\\" type=\\\"Node2D\\\"]"},
			{"path":"scripts/main.gd","content":"extends Node2D\\nfunc _ready():\\n  print(\\\"hi\\\")"}
		]
	})json";
	const Error result = AIGameBuilderPlugin::parse_plan(response, files, summary, error);
	CHECK_EQ(result, OK);
	REQUIRE_EQ(files.size(), 2);
	CHECK_EQ(summary, "A playable scene, with a movement script.");
	CHECK(error.is_empty());
	const Dictionary first = files[0];
	const Dictionary second = files[1];
	CHECK_EQ(String(first["path"]), "scenes/main.tscn");
	CHECK_EQ(String(second["path"]), "scripts/main.gd");
	CHECK(String(second["content"]).contains("extends Node2D"));
}

TEST_CASE("[AIGameBuilder] Accepts Markdown JSON fences") {
	Array files;
	String summary;
	String error;
	const String response = "```json\n{\"summary\":\"OK\",\"files\":[{\"path\":\"main.gd\",\"content\":\"extends Node\"}]}\n```";
	CHECK_EQ(AIGameBuilderPlugin::parse_plan(response, files, summary, error), OK);
	REQUIRE_EQ(files.size(), 1);
	CHECK_EQ(summary, "OK");
}

TEST_CASE("[AIGameBuilder] Rejects malformed and incomplete JSON") {
	const char *invalid[] = {
		"",
		"hello world",
		"null",
		"true",
		"[]",
		"{",
		"{\"files\":",
		"{\"files\":null}",
		"{\"files\":\"not-an-array\"}",
		"{\"files\":[]}",
		"{\"files\":[true]}",
		"{\"files\":[null]}",
		"{\"files\":[2]}",
		"{\"files\":[{}]}",
		"{\"files\":[{\"path\":10,\"content\":\"code\"}]}",
		"{\"files\":[{\"path\":\"main.gd\",\"content\":10}]}",
		"{\"files\":[{\"path\":\"main.gd\"}]}",
		"{\"files\":[{\"content\":\"ok\"}]}",
		"{\"files\":[{\"path\":\"main.gd\",\"content\":\"\"}]}",
		"```json\n{}",
		"```json```",
	};
	for (const char *json : invalid) {
		INFO("Invalid response: ", json);
		Array files;
		String summary;
		String error;
		CHECK_NE(AIGameBuilderPlugin::parse_plan(json, files, summary, error), OK);
		CHECK(files.is_empty());
		CHECK_FALSE(error.is_empty());
	}
}

TEST_CASE("[AIGameBuilder] Rejects unsafe file paths from a valid JSON response") {
	const char *invalid_paths[] = {
		"../evil.gd",
		"res://main.gd",
		"/tmp/game.gd",
		"C:/games/test.gd",
		"project.godot",
		".godot/secret.gd",
		"main.py",
		"addons/plugin.cfg",
		"scripts/foo\\bar.gd",
	};
	for (const char *path : invalid_paths) {
		INFO("Unsafe path: ", path);
		Dictionary file;
		file["path"] = path;
		file["content"] = "extends Node";
		Array files_to_encode;
		files_to_encode.push_back(file);
		Dictionary plan;
		plan["files"] = files_to_encode;

		Array decoded_files;
		String summary;
		String error;
		CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), decoded_files, summary, error), ERR_INVALID_DATA);
		CHECK(decoded_files.is_empty());
	}
}

TEST_CASE("[AIGameBuilder] Rejects duplicate file names, including casing aliases") {
	const char *duplicates[][2] = {
		{ "scripts/actor.gd", "scripts/actor.gd" },
		{ "scripts/actor.gd", "Scripts/actor.gd" },
		{ "Main.tscn", "main.tscn" },
	};
	for (const auto &pair : duplicates) {
		Array input_files;
		for (const char *path : pair) {
			Dictionary file;
			file["path"] = path;
			file["content"] = "extends Node";
			input_files.push_back(file);
		}
		Dictionary plan;
		plan["files"] = input_files;
		Array decoded_files;
		String summary;
		String error;
		CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), decoded_files, summary, error), ERR_INVALID_DATA);
		CHECK(decoded_files.is_empty());
	}
}

TEST_CASE("[AIGameBuilder] Enforces file count boundaries") {
	for (int count : { 1, 64, 65 }) {
		Array input_files;
		for (int i = 0; i < count; i++) {
			Dictionary file;
			file["path"] = "scripts/script_" + itos(i) + ".gd";
			file["content"] = "extends Node";
			input_files.push_back(file);
		}
		Dictionary plan;
		plan["files"] = input_files;
		Array files;
		String summary;
		String error;
		CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), files, summary, error), count <= 64 ? OK : ERR_INVALID_DATA);
		CHECK_EQ(files.size(), count <= 64 ? count : 0);
	}
}

TEST_CASE("[AIGameBuilder] Enforces 256 KiB per file and 1 MiB total") {
	for (int bytes : { 1, 256 * 1024, 256 * 1024 + 1 }) {
		Dictionary file;
		file["path"] = "scripts/main.gd";
		file["content"] = String("x").repeat(bytes);
		Array encoded_files;
		encoded_files.push_back(file);
		Dictionary plan;
		plan["files"] = encoded_files;
		Array files;
		String summary;
		String error;
		CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), files, summary, error),
				bytes <= 256 * 1024 ? OK : ERR_INVALID_DATA);
	}

	Array input_files;
	for (int i = 0; i < 5; i++) {
		Dictionary file;
		file["path"] = "scripts/large_" + itos(i) + ".gd";
		file["content"] = String("x").repeat(220 * 1024);
		input_files.push_back(file);
	}
	Dictionary plan;
	plan["files"] = input_files;
	Array files;
	String summary;
	String error;
	CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), files, summary, error), ERR_INVALID_DATA);
	CHECK(files.is_empty());
}

TEST_CASE("[AIGameBuilder] Rejects editor-executed tool scripts and NUL bytes") {
	Array files;
	String summary;
	String error;
	const char *unsafe_code[] = {
		"@tool\\nextends Node",
		"extends Node\\n@tool",
		"# @tool\\nextends Node",
	};
	for (const char *code : unsafe_code) {
		Dictionary file;
		file["path"] = "scripts/main.gd";
		file["content"] = code;
		Array input;
		input.push_back(file);
		Dictionary plan;
		plan["files"] = input;
		CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), files, summary, error), ERR_INVALID_DATA);
		CHECK(files.is_empty());
	}
	Dictionary file;
	file["path"] = "scripts/main.gd";
	file["content"] = String("extends Node") + String::chr(0) + "danger";
	Array input;
	input.push_back(file);
	Dictionary plan;
	plan["files"] = input;
	CHECK_EQ(AIGameBuilderPlugin::parse_plan(JSON::stringify(plan), files, summary, error), ERR_INVALID_DATA);
	CHECK(files.is_empty());
}

TEST_CASE("[AIGameBuilder] Failed parsing clears a previous valid plan") {
	Array files;
	String summary;
	String error;
	CHECK_EQ(AIGameBuilderPlugin::parse_plan(
						"{\"summary\":\"test\",\"files\":[{\"path\":\"main.gd\",\"content\":\"extends Node\"}]}",
						files, summary, error),
			OK);
	REQUIRE_EQ(files.size(), 1);
	CHECK_EQ(AIGameBuilderPlugin::parse_plan("{\"files\":[]}", files, summary, error), ERR_INVALID_DATA);
	CHECK(files.is_empty());
	CHECK(summary.is_empty());
	CHECK_FALSE(error.is_empty());
}

} // namespace TestAIGameBuilder

#endif // TOOLS_ENABLED
