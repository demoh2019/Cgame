/**************************************************************************/
/*  editor_ue_toolbar.h                                                   */
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

#include "scene/gui/panel_container.h"

class Button;
class EditorRunBar;
class HBoxContainer;
class MenuButton;

// Unreal-style main toolbar: Save / Add on the left, a prominent centered play group, and
// Platforms / Quick Settings on the right. It only mirrors and forwards existing editor
// actions; the run bar in the title bar keeps working as before.
class EditorUEToolbar : public PanelContainer {
	GDCLASS(EditorUEToolbar, PanelContainer);

public:
	enum AddMenuItem {
		ADD_NODE,
		ADD_INSTANCE_SCENE,
	};

private:
	Button *save_button = nullptr;
	MenuButton *add_button = nullptr;
	MenuButton *platforms_button = nullptr;
	MenuButton *quick_settings_button = nullptr;

	Button *play_button = nullptr;
	Button *play_scene_button = nullptr;
	Button *pause_button = nullptr;
	Button *stop_button = nullptr;

	EditorRunBar *run_bar = nullptr;
	double sync_timer = 0.0;

	void _sync_play_state();
	void _play_pressed();
	void _play_scene_pressed();
	void _pause_pressed();
	void _stop_pressed();
	void _update_icons();

	Button *_create_play_button(HBoxContainer *p_parent, const String &p_tooltip, bool p_toggle);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void setup(EditorRunBar *p_run_bar);

	Button *get_save_button() const { return save_button; }
	MenuButton *get_add_button() const { return add_button; }
	MenuButton *get_platforms_button() const { return platforms_button; }
	MenuButton *get_quick_settings_button() const { return quick_settings_button; }

	EditorUEToolbar();
};
