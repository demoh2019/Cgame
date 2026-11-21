/**************************************************************************/
/*  editor_ue_toolbar.cpp                                                 */
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

#include "editor_ue_toolbar.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "editor/editor_node.h"
#include "editor/editor_string_names.h"
#include "editor/run/editor_run_bar.h"
#include "editor/themes/editor_scale.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"
#include "scene/gui/menu_button.h"
#include "scene/gui/popup_menu.h"
#include "scene/gui/separator.h"

Button *EditorUEToolbar::_create_play_button(HBoxContainer *p_parent, const String &p_tooltip, bool p_toggle) {
	Button *button = memnew(Button);
	button->set_theme_type_variation("RunBarButton");
	button->set_toggle_mode(p_toggle);
	button->set_focus_mode(Control::FOCUS_ACCESSIBILITY);
	button->set_tooltip_text(p_tooltip);
	p_parent->add_child(button);
	return button;
}

void EditorUEToolbar::setup(EditorRunBar *p_run_bar) {
	run_bar = p_run_bar;
	set_process_internal(run_bar != nullptr);
}

void EditorUEToolbar::_sync_play_state() {
	if (!run_bar) {
		return;
	}
	const bool playing = run_bar->is_playing();
	play_button->set_pressed_no_signal(playing);
	stop_button->set_disabled(!playing);

	Button *source_pause = run_bar->get_pause_button();
	if (source_pause) {
		pause_button->set_disabled(source_pause->is_disabled());
		pause_button->set_pressed_no_signal(source_pause->is_pressed());
	}
}

void EditorUEToolbar::_play_pressed() {
	if (run_bar) {
		run_bar->play_main_scene();
	}
	_sync_play_state();
}

void EditorUEToolbar::_play_scene_pressed() {
	if (run_bar) {
		run_bar->play_current_scene();
	}
	_sync_play_state();
}

void EditorUEToolbar::_pause_pressed() {
	if (run_bar) {
		Button *source_pause = run_bar->get_pause_button();
		if (source_pause && !source_pause->is_disabled()) {
			source_pause->set_pressed(!source_pause->is_pressed());
		}
	}
	_sync_play_state();
}

void EditorUEToolbar::_stop_pressed() {
	if (run_bar) {
		run_bar->stop_playing();
	}
	_sync_play_state();
}

void EditorUEToolbar::_update_icons() {
	save_button->set_button_icon(get_editor_theme_icon(SNAME("Save")));
	add_button->set_button_icon(get_editor_theme_icon(SNAME("Add")));
	platforms_button->set_button_icon(get_editor_theme_icon(SNAME("ResourcePreloader")));
	quick_settings_button->set_button_icon(get_editor_theme_icon(SNAME("Tools")));

	play_button->set_button_icon(get_editor_theme_icon(SNAME("MainPlay")));
	play_scene_button->set_button_icon(get_editor_theme_icon(SNAME("PlayScene")));
	pause_button->set_button_icon(get_editor_theme_icon(SNAME("Pause")));
	stop_button->set_button_icon(get_editor_theme_icon(SNAME("Stop")));
}

void EditorUEToolbar::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE:
		case NOTIFICATION_THEME_CHANGED: {
			_update_icons();
		} break;

		case NOTIFICATION_INTERNAL_PROCESS: {
			// The play state lives in the run bar; polling a few times per second keeps both in sync cheaply.
			sync_timer += get_process_delta_time();
			if (sync_timer >= 0.1) {
				sync_timer = 0.0;
				if (is_visible_in_tree()) {
					_sync_play_state();
				}
			}
		} break;
	}
}

void EditorUEToolbar::_bind_methods() {
}

EditorUEToolbar::EditorUEToolbar() {
	set_theme_type_variation("PanelForeground");

	HBoxContainer *main_hbox = memnew(HBoxContainer);
	add_child(main_hbox);

	// Left: Save and Add.
	HBoxContainer *left = memnew(HBoxContainer);
	main_hbox->add_child(left);

	save_button = memnew(Button);
	save_button->set_flat(true);
	save_button->set_tooltip_text(TTRC("Save the current scene."));
	save_button->set_accessibility_name(TTRC("Save Scene"));
	left->add_child(save_button);

	add_button = memnew(MenuButton);
	add_button->set_flat(true);
	add_button->set_text(TTRC("Add"));
	add_button->set_tooltip_text(TTRC("Add a node or an instanced scene to the current scene."));
	add_button->set_switch_on_hover(true);
	add_button->get_popup()->add_item(TTRC("Node..."), ADD_NODE);
	add_button->get_popup()->add_item(TTRC("Instantiate Scene..."), ADD_INSTANCE_SCENE);
	left->add_child(add_button);

	Control *left_spacer = memnew(Control);
	left_spacer->set_h_size_flags(SIZE_EXPAND_FILL);
	main_hbox->add_child(left_spacer);

	// Center: play group.
	HBoxContainer *play_group = memnew(HBoxContainer);
	main_hbox->add_child(play_group);

	play_button = _create_play_button(play_group, TTRC("Play the project's main scene."), true);
	play_button->connect(SceneStringName(pressed), callable_mp(this, &EditorUEToolbar::_play_pressed));
	play_scene_button = _create_play_button(play_group, TTRC("Play the currently edited scene."), false);
	play_scene_button->connect(SceneStringName(pressed), callable_mp(this, &EditorUEToolbar::_play_scene_pressed));
	pause_button = _create_play_button(play_group, TTRC("Pause the running project."), true);
	pause_button->set_disabled(true);
	pause_button->connect(SceneStringName(pressed), callable_mp(this, &EditorUEToolbar::_pause_pressed));
	stop_button = _create_play_button(play_group, TTRC("Stop the running project."), false);
	stop_button->set_disabled(true);
	stop_button->connect(SceneStringName(pressed), callable_mp(this, &EditorUEToolbar::_stop_pressed));

	Control *right_spacer = memnew(Control);
	right_spacer->set_h_size_flags(SIZE_EXPAND_FILL);
	main_hbox->add_child(right_spacer);

	// Right: Platforms and Quick Settings.
	HBoxContainer *right = memnew(HBoxContainer);
	main_hbox->add_child(right);

	platforms_button = memnew(MenuButton);
	platforms_button->set_flat(true);
	platforms_button->set_text(TTRC("Platforms"));
	platforms_button->set_tooltip_text(TTRC("Export the project to a platform."));
	platforms_button->get_popup()->add_item(TTRC("Export..."), EditorNode::PROJECT_EXPORT);
	platforms_button->get_popup()->add_item(TTRC("Manage Export Templates..."), EditorNode::EDITOR_MANAGE_EXPORT_TEMPLATES);
	right->add_child(platforms_button);

	quick_settings_button = memnew(MenuButton);
	quick_settings_button->set_flat(true);
	quick_settings_button->set_text(TTRC("Quick Settings"));
	quick_settings_button->set_tooltip_text(TTRC("Frequently used editor and debug toggles."));
	right->add_child(quick_settings_button);
}
