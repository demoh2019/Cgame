/**************************************************************************/
/*  editor_status_bar.cpp                                                 */
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

#include "editor_status_bar.h"

#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/object/class_db.h"
#include "editor/editor_string_names.h"
#include "editor/gui/progress_dialog.h"
#include "editor/version_control/editor_vcs_interface.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"

String EditorStatusBar::_find_git_branch() {
	// Without a VCS plugin the branch is read straight from `.git/HEAD`, walking up from the project folder.
	String dir = ProjectSettings::get_singleton()->get_resource_path();
	for (int depth = 0; depth < 6 && !dir.is_empty(); depth++) {
		const String head_path = dir.path_join(".git").path_join("HEAD");
		if (FileAccess::exists(head_path)) {
			const String head = FileAccess::get_file_as_string(head_path).strip_edges();
			if (head.begins_with("ref: refs/heads/")) {
				return head.trim_prefix("ref: refs/heads/");
			}
			// Detached HEAD: show an abbreviated commit id.
			return head.length() >= 7 ? head.substr(0, 7) : head;
		}
		const String parent = dir.get_base_dir();
		if (parent == dir) {
			break;
		}
		dir = parent;
	}
	return String();
}

void EditorStatusBar::_refresh_vcs() {
	String branch;
	EditorVCSInterface *vcs = EditorVCSInterface::get_singleton();
	if (vcs) {
		branch = vcs->get_current_branch_name();
	}
	if (branch.is_empty()) {
		branch = _find_git_branch();
	}

	if (branch == current_branch) {
		return;
	}
	current_branch = branch;
	vcs_button->set_visible(!branch.is_empty());
	vcs_button->set_text(branch);
	vcs_button->set_tooltip_text(vformat(TTR("Source control branch: %s"), branch));
}

void EditorStatusBar::_update_icons() {
	drawer_button->set_button_icon(get_editor_theme_icon(SNAME("Folder")));
	log_button->set_button_icon(get_editor_theme_icon(SNAME("Edit")));
	history_button->set_button_icon(get_editor_theme_icon(SNAME("History")));
	vcs_button->set_button_icon(get_editor_theme_icon(SNAME("VcsBranches")));
}

void EditorStatusBar::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			_refresh_vcs();
			set_process_internal(true);
		} break;

		case NOTIFICATION_EXIT_TREE: {
			set_process_internal(false);
		} break;

		case NOTIFICATION_THEME_CHANGED: {
			_update_icons();
		} break;

		case NOTIFICATION_INTERNAL_PROCESS: {
			poll_timer += get_process_delta_time();
			if (poll_timer >= 5.0) {
				poll_timer = 0.0;
				_refresh_vcs();
			}
		} break;
	}
}

void EditorStatusBar::_bind_methods() {
}

EditorStatusBar::EditorStatusBar() {
	set_theme_type_variation("PanelForeground");

	HBoxContainer *hbox = memnew(HBoxContainer);
	add_child(hbox);

	drawer_button = memnew(Button);
	drawer_button->set_flat(true);
	drawer_button->set_text(TTRC("Content Drawer"));
	drawer_button->set_tooltip_text(TTRC("Open the Content Drawer (FileSystem)."));
	hbox->add_child(drawer_button);

	log_button = memnew(Button);
	log_button->set_flat(true);
	log_button->set_text(TTRC("Output Log"));
	log_button->set_tooltip_text(TTRC("Show the Output panel."));
	hbox->add_child(log_button);

	history_button = memnew(Button);
	history_button->set_flat(true);
	history_button->set_text(TTRC("Undo History"));
	history_button->set_tooltip_text(TTRC("Show the undo history. Click an entry to jump to that state."));
	hbox->add_child(history_button);

	Control *spacer = memnew(Control);
	spacer->set_h_size_flags(SIZE_EXPAND_FILL);
	hbox->add_child(spacer);

	tasks = memnew(BackgroundProgress);
	hbox->add_child(tasks);

	vcs_button = memnew(Button);
	vcs_button->set_flat(true);
	vcs_button->set_visible(false);
	vcs_button->set_focus_mode(Control::FOCUS_ACCESSIBILITY);
	hbox->add_child(vcs_button);
}
