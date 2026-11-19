/**************************************************************************/
/*  ai_game_builder_plugin.h                                              */
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

#include "editor/plugins/editor_plugin.h"

#include "core/variant/array.h"

class Button;
class EditorDock;
class HTTPRequest;
class Label;
class LineEdit;
class TextEdit;

// A built-in editor assistant that generates a reviewable collection of text assets.
// It never executes model-generated code or writes to the project without a click.
class AIGameBuilderPlugin : public EditorPlugin {
	GDCLASS(AIGameBuilderPlugin, EditorPlugin);

	EditorDock *dock = nullptr;
	HTTPRequest *http_request = nullptr;
	TextEdit *prompt_edit = nullptr;
	TextEdit *preview_edit = nullptr;
	LineEdit *endpoint_edit = nullptr;
	LineEdit *model_edit = nullptr;
	Label *status_label = nullptr;
	Button *generate_button = nullptr;
	Button *cancel_button = nullptr;
	Button *apply_button = nullptr;

	Array pending_files;
	bool request_in_progress = false;

	void _set_busy(bool p_busy);
	void _generate_pressed();
	void _cancel_pressed();
	void _apply_pressed();
	void _request_completed(int p_result, int p_response_code, const PackedStringArray &p_headers, const PackedByteArray &p_body);

protected:
	static void _bind_methods() {}

public:
	// Exposed to C++ regression tests without constructing the editor UI.
	static bool is_safe_project_path(const String &p_path);
	static Error parse_plan(const String &p_json, Array &r_files, String &r_summary, String &r_error);

	AIGameBuilderPlugin();
	~AIGameBuilderPlugin();
};
