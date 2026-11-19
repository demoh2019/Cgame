/**************************************************************************/
/*  ai_game_builder_plugin.cpp                                            */
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

#include "ai_game_builder_plugin.h"

#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/http_client.h"
#include "core/object/callable_mp.h"
#include "core/os/os.h"
#include "core/string/ustring.h"
#include "core/templates/hash_set.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "core/io/json.h"
#include "editor/docks/editor_dock.h"
#include "editor/file_system/editor_file_system.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"
#include "scene/gui/label.h"
#include "scene/gui/line_edit.h"
#include "scene/gui/text_edit.h"
#include "scene/main/http_request.h"

namespace {

constexpr int MAX_FILES = 64;
constexpr int MAX_FILE_BYTES = 256 * 1024;
constexpr int MAX_TOTAL_BYTES = 1024 * 1024;

String get_env_default(const String &p_name, const String &p_default) {
	const String value = OS::get_singleton()->get_environment(p_name);
	return value.is_empty() ? p_default : value;
}

bool is_local_endpoint(const String &p_url) {
	return p_url.begins_with("http://127.0.0.1/") || p_url.begins_with("http://127.0.0.1:") ||
			p_url.begins_with("http://localhost/") || p_url.begins_with("http://localhost:");
}

} // namespace

bool AIGameBuilderPlugin::is_safe_project_path(const String &p_path) {
	if (p_path.is_empty() || p_path.length() > 180 || p_path.begins_with("/") || p_path.ends_with("/") ||
			p_path.contains("..") || p_path.contains("//")) {
		return false;
	}

	// Only portable ASCII paths and text-based game assets are accepted.
	// This also excludes absolute paths, URL schemes, drive letters and escapes.
	for (int i = 0; i < p_path.length(); i++) {
		const char32_t c = p_path[i];
		const bool alphanumeric = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
		if (!alphanumeric && c != '_' && c != '-' && c != '.' && c != '/') {
			return false;
		}
	}

	const PackedStringArray components = p_path.split("/");
	if (components.size() > 8) {
		return false;
	}
	for (const String &component : components) {
		if (component.is_empty() || component.begins_with(".") || component.ends_with(".") || component.length() > 80) {
			return false;
		}
		// Reserved Windows device names are invalid even with a file extension.
		const String stem = component.get_slice(".", 0).to_upper();
		if (stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" ||
				(stem.length() == 4 && (stem.begins_with("COM") || stem.begins_with("LPT")) && stem[3] >= '1' && stem[3] <= '9')) {
			return false;
		}
	}

	const String extension = p_path.get_extension().to_lower();
	return extension == "gd" || extension == "tscn" || extension == "tres" ||
			extension == "gdshader" || extension == "gdshaderinc" || extension == "json" ||
			extension == "txt" || extension == "md" || extension == "svg" || extension == "csv";
}

Error AIGameBuilderPlugin::parse_plan(const String &p_json, Array &r_files, String &r_summary, String &r_error) {
	r_files.clear();
	r_summary = "";
	r_error = "";

	String source = p_json.strip_edges();
	if (source.begins_with("```")) {
		const int newline = source.find("\n");
		if (newline < 0 || !source.ends_with("```")) {
			r_error = "Incomplete JSON code fence.";
			return ERR_PARSE_ERROR;
		}
		source = source.substr(newline + 1, source.length() - newline - 4).strip_edges();
	}

	const Variant decoded = JSON::parse_string(source);
	if (decoded.get_type() != Variant::DICTIONARY) {
		r_error = "The AI response must be a JSON object.";
		return ERR_PARSE_ERROR;
	}

	const Dictionary plan = decoded;
	const Variant files_variant = plan.get("files", Variant());
	if (files_variant.get_type() != Variant::ARRAY) {
		r_error = "The AI response must contain a files array.";
		return ERR_INVALID_DATA;
	}

	const Array files = files_variant;
	if (files.is_empty() || files.size() > MAX_FILES) {
		r_error = "The plan must contain 1 to 64 files.";
		return ERR_INVALID_DATA;
	}

	HashSet<String> paths;
	int total_bytes = 0;
	for (int i = 0; i < files.size(); i++) {
		if (files[i].get_type() != Variant::DICTIONARY) {
			r_error = "Every file must be an object.";
			return ERR_INVALID_DATA;
		}
		const Dictionary file = files[i];
		const Variant path_variant = file.get("path", Variant());
		const Variant content_variant = file.get("content", Variant());
		if (path_variant.get_type() != Variant::STRING || content_variant.get_type() != Variant::STRING) {
			r_error = "Every file requires string path and content fields.";
			return ERR_INVALID_DATA;
		}
		const String path = path_variant;
		const String contents = content_variant;
		if (!is_safe_project_path(path)) {
			r_error = vformat("Unsafe or unsupported project path: %s", path);
			return ERR_INVALID_DATA;
		}
		if (paths.has(path.to_lower())) {
			r_error = vformat("Duplicate project path: %s", path);
			return ERR_INVALID_DATA;
		}
		paths.insert(path.to_lower());

		const int bytes = contents.utf8().length();
		// Tool scripts may execute editor-side code on import. Disallow them in generated assets.
		if (contents.contains("@tool")) {
			r_error = "Editor-executed @tool scripts are not allowed in generated assets.";
			return ERR_INVALID_DATA;
		}
		if (contents.contains_char(0) || bytes == 0 || bytes > MAX_FILE_BYTES || total_bytes > MAX_TOTAL_BYTES - bytes) {
			r_error = "A file is empty or the plan exceeds the file-size limits.";
			return ERR_INVALID_DATA;
		}
		total_bytes += bytes;
	}

	const Variant summary_variant = plan.get("summary", Variant());
	if (summary_variant.get_type() == Variant::STRING) {
		r_summary = summary_variant;
	}
	r_files = files;
	return OK;
}

void AIGameBuilderPlugin::_set_busy(bool p_busy) {
	request_in_progress = p_busy;
	generate_button->set_disabled(p_busy);
	cancel_button->set_disabled(!p_busy);
	apply_button->set_disabled(p_busy || pending_files.is_empty());
}

void AIGameBuilderPlugin::_generate_pressed() {
	if (request_in_progress) {
		return;
	}

	const String prompt = prompt_edit->get_text().strip_edges();
	if (prompt.is_empty()) {
		status_label->set_text("Describe the game you want to create first.");
		return;
	}

	const String endpoint = endpoint_edit->get_text().strip_edges();
	const bool is_https = endpoint.begins_with("https://");
	if ((!is_https && !is_local_endpoint(endpoint)) || endpoint.contains("@") || endpoint.contains("#") ||
			endpoint.contains("\n") || endpoint.contains("\r")) {
		status_label->set_text("Use HTTPS, or HTTP on localhost / 127.0.0.1 only.");
		return;
	}

	const String model = model_edit->get_text().strip_edges();
	if (model.is_empty()) {
		status_label->set_text("Enter a model identifier.");
		return;
	}

	const String api_key = OS::get_singleton()->get_environment("GODOT_AI_API_KEY");
	if (is_https && api_key.is_empty()) {
		status_label->set_text("Set GODOT_AI_API_KEY in the editor's environment.");
		return;
	}

	// Clear the previous plan before requesting a new one, to avoid applying stale files.
	pending_files.clear();
	apply_button->set_disabled(true);
	preview_edit->set_text("");
	_set_busy(true);
	status_label->set_text("Generating a multi-file game plan...");

	const String system_instructions =
			"You are a senior Godot 4 game developer. Create a playable Godot game from the request. "
			"Return ONLY one JSON object with exactly this structure: "
			"{\"summary\":\"Short description and setup instructions\","
			"\"files\":[{\"path\":\"scenes/main.tscn\",\"content\":\"Complete Godot scene text\"},"
			"{\"path\":\"scripts/main.gd\",\"content\":\"Complete GDScript\"}]}. "
			"Generate complete compatible resources, connected scenes, valid GDScript, and no placeholders. "
			"Use relative forward-slash paths under res://, never include res:// in the path. "
			"Only generate new text assets with these extensions: gd, tscn, tres, gdshader, gdshaderinc, "
			"json, txt, md, svg, csv. Do not create project.godot, plugins, binaries or hidden files. Do not use @tool scripts or run commands. "
			"Prefer a simple, self-contained game that is playable without downloaded assets. "
			"Limit to 64 files and 1 MiB total content. Never put explanations outside the JSON.";

	Dictionary system_message;
	system_message["role"] = "system";
	system_message["content"] = system_instructions;
	Dictionary user_message;
	user_message["role"] = "user";
	user_message["content"] = prompt;
	Array messages;
	messages.push_back(system_message);
	messages.push_back(user_message);
	Dictionary request;
	request["model"] = model;
	request["messages"] = messages;

	Vector<String> headers;
	headers.push_back("Content-Type: application/json");
	if (!api_key.is_empty()) {
		headers.push_back("Authorization: Bearer " + api_key);
	}
	const Error error = http_request->request(endpoint, headers, HTTPClient::METHOD_POST, JSON::stringify(request));
	if (error != OK) {
		_set_busy(false);
		status_label->set_text(vformat("Unable to start request (error %d).", error));
	}
}

void AIGameBuilderPlugin::_cancel_pressed() {
	if (!request_in_progress) {
		return;
	}
	http_request->cancel_request();
	_set_busy(false);
	status_label->set_text("Request canceled. No project files were changed.");
}

void AIGameBuilderPlugin::_request_completed(int p_result, int p_response_code, const PackedStringArray &p_headers, const PackedByteArray &p_body) {
	(void)p_headers;
	if (!request_in_progress) {
		return;
	}
	_set_busy(false);
	if (p_result != HTTPRequest::RESULT_SUCCESS || p_response_code != HTTPClient::RESPONSE_OK) {
		status_label->set_text(vformat("AI request failed (network %d, HTTP %d).", p_result, p_response_code));
		return;
	}

	const String body_text = String::utf8(reinterpret_cast<const char *>(p_body.ptr()), p_body.size());
	const Variant response_variant = JSON::parse_string(body_text);
	if (response_variant.get_type() != Variant::DICTIONARY) {
		status_label->set_text("The AI provider returned invalid JSON.");
		return;
	}
	const Dictionary response = response_variant;
	const Variant choices_variant = response.get("choices", Variant());
	if (choices_variant.get_type() != Variant::ARRAY) {
		status_label->set_text("No response choices were returned by the AI provider.");
		return;
	}
	const Array choices = choices_variant;
	if (choices.is_empty()) {
		status_label->set_text("No response choices were returned by the AI provider.");
		return;
	}
	if (choices[0].get_type() != Variant::DICTIONARY) {
		status_label->set_text("Unexpected AI response format.");
		return;
	}
	const Dictionary choice = choices[0];
	const Variant message_variant = choice.get("message", Variant());
	if (message_variant.get_type() != Variant::DICTIONARY) {
		status_label->set_text("The AI response has no message.");
		return;
	}
	const Dictionary message = message_variant;
	const Variant content_variant = message.get("content", Variant());
	if (content_variant.get_type() != Variant::STRING) {
		status_label->set_text("The AI response has no text content.");
		return;
	}

	String summary;
	String parse_error;
	Array files;
	if (parse_plan(content_variant, files, summary, parse_error) != OK) {
		status_label->set_text(parse_error);
		return;
	}

	pending_files = files;
	String preview = summary + "\n\n";
	for (int i = 0; i < files.size(); i++) {
		const Dictionary file = files[i];
		const String path = file["path"];
		const String contents = file["content"];
		preview += vformat("===== res://%s =====\n%s\n\n", path, contents);
	}
	preview_edit->set_text(preview);
	apply_button->set_disabled(false);
	status_label->set_text(vformat("Review %d generated files; click Create Files to apply.", files.size()));
}

void AIGameBuilderPlugin::_apply_pressed() {
	if (request_in_progress || pending_files.is_empty()) {
		return;
	}
	const String root = ProjectSettings::get_singleton()->get_resource_path();
	if (root.is_empty()) {
		status_label->set_text("The project directory is unavailable.");
		return;
	}
	const Ref<DirAccess> filesystem = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
	if (filesystem.is_null()) {
		status_label->set_text("Could not access the filesystem.");
		return;
	}

	// Preflight everything before writing: no replacement, duplicates or symlink escapes.
	for (int i = 0; i < pending_files.size(); i++) {
		const Dictionary file = pending_files[i];
		const String path = file["path"];
		if (!is_safe_project_path(path)) {
			status_label->set_text("Rejected an unsafe generated path.");
			return;
		}
		const String full_path = root.path_join(path);
		if (filesystem->is_link(full_path) || FileAccess::exists(full_path) ||
				DirAccess::dir_exists_absolute(full_path)) {
			status_label->set_text(vformat("File already exists; no files created: res://%s", path));
			return;
		}

		String dir = root;
		for (const String &segment : path.get_base_dir().split("/")) {
			if (segment == ".") {
				continue;
			}
			dir = dir.path_join(segment);
			if (filesystem->is_link(dir)) {
				status_label->set_text(vformat("Refusing to follow a project symlink: res://%s", path));
				return;
			}
		}
	}

	Vector<String> created_files;
	for (int i = 0; i < pending_files.size(); i++) {
		const Dictionary file = pending_files[i];
		const String path = file["path"];
		const String contents = file["content"];
		const String full_path = root.path_join(path);

		Error err = DirAccess::make_dir_recursive_absolute(full_path.get_base_dir());
		if (err == OK && !FileAccess::exists(full_path) && !filesystem->is_link(full_path)) {
			Ref<FileAccess> output = FileAccess::open(full_path, FileAccess::WRITE, &err);
			if (output.is_valid()) {
				created_files.push_back(full_path);
				output->store_string(contents);
				output->flush();
				err = output->get_error();
				if (err == OK) {
					continue;
				}
			}
		}

		if (err == OK) {
			err = ERR_FILE_CANT_WRITE;
		}
		// This operation only creates new files, so rollback never deletes user files.
		for (const String &created : created_files) {
			DirAccess::remove_absolute(created);
		}
		status_label->set_text(vformat("File creation failed (%d); generated files rolled back.", err));
		return;
	}

	const int count = pending_files.size();
	pending_files.clear();
	apply_button->set_disabled(true);
	preview_edit->set_text("");
	status_label->set_text(vformat("Created %d files. Open the generated main scene to play.", count));
	if (EditorFileSystem::get_singleton()) {
		EditorFileSystem::get_singleton()->scan();
	}
}

AIGameBuilderPlugin::AIGameBuilderPlugin() {
	http_request = memnew(HTTPRequest);
	http_request->set_timeout(90.0);
	http_request->set_body_size_limit(2 * 1024 * 1024);
	add_child(http_request);
	http_request->connect("request_completed", callable_mp(this, &AIGameBuilderPlugin::_request_completed));

	dock = memnew(EditorDock);
	dock->set_title("AI Game Builder");
	dock->set_layout_key("ai_game_builder");
	dock->set_default_slot(EditorDock::DOCK_SLOT_RIGHT_BR);

	VBoxContainer *layout = memnew(VBoxContainer);
	layout->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	dock->add_child(layout);

	Label *heading = memnew(Label);
	heading->set_text("Describe a game, tool or scene to generate.");
	layout->add_child(heading);

	prompt_edit = memnew(TextEdit);
	prompt_edit->set_custom_minimum_size(Size2(240, 115));
	prompt_edit->set_text("Create a small playable 2D arcade game with keyboard controls, a score, and a restart button.");
	layout->add_child(prompt_edit);

	Label *endpoint_label = memnew(Label);
	endpoint_label->set_text("Chat completions endpoint:");
	layout->add_child(endpoint_label);
	endpoint_edit = memnew(LineEdit);
	endpoint_edit->set_text(get_env_default("GODOT_AI_ENDPOINT", "https://api.openai.com/v1/chat/completions"));
	layout->add_child(endpoint_edit);

	Label *model_label = memnew(Label);
	model_label->set_text("Model:");
	layout->add_child(model_label);
	model_edit = memnew(LineEdit);
	model_edit->set_text(get_env_default("GODOT_AI_MODEL", "gpt-4o-mini"));
	layout->add_child(model_edit);

	Label *key_help = memnew(Label);
	key_help->set_text("API key: GODOT_AI_API_KEY environment variable.\nOnly your written prompt is transmitted.");
	layout->add_child(key_help);

	HBoxContainer *actions = memnew(HBoxContainer);
	layout->add_child(actions);
	generate_button = memnew(Button);
	generate_button->set_text("Generate Plan");
	actions->add_child(generate_button);
	generate_button->connect("pressed", callable_mp(this, &AIGameBuilderPlugin::_generate_pressed));

	cancel_button = memnew(Button);
	cancel_button->set_text("Cancel");
	cancel_button->set_disabled(true);
	actions->add_child(cancel_button);
	cancel_button->connect("pressed", callable_mp(this, &AIGameBuilderPlugin::_cancel_pressed));

	Label *preview_label = memnew(Label);
	preview_label->set_text("Review generated code and scene files before creating them:");
	layout->add_child(preview_label);
	preview_edit = memnew(TextEdit);
	preview_edit->set_editable(false);
	preview_edit->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	preview_edit->set_custom_minimum_size(Size2(240, 150));
	layout->add_child(preview_edit);

	apply_button = memnew(Button);
	apply_button->set_text("Create Files (No Overwrite)");
	apply_button->set_disabled(true);
	layout->add_child(apply_button);
	apply_button->connect("pressed", callable_mp(this, &AIGameBuilderPlugin::_apply_pressed));

	status_label = memnew(Label);
	status_label->set_text("Ready. Generated code is never executed automatically.");
	layout->add_child(status_label);

	add_dock(dock);
}

AIGameBuilderPlugin::~AIGameBuilderPlugin() {
	if (http_request && request_in_progress) {
		http_request->cancel_request();
	}
	if (dock) {
		remove_dock(dock);
		memdelete(dock);
	}
}
