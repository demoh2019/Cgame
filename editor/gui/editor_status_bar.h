/**************************************************************************/
/*  editor_status_bar.h                                                   */
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

class BackgroundProgress;
class Button;

// Persistent bottom bar: Content Drawer / Output / History buttons on the left, background task
// progress and the source-control branch on the right.
class EditorStatusBar : public PanelContainer {
	GDCLASS(EditorStatusBar, PanelContainer);

	Button *drawer_button = nullptr;
	Button *log_button = nullptr;
	Button *history_button = nullptr;
	Button *vcs_button = nullptr;
	BackgroundProgress *tasks = nullptr;

	double poll_timer = 0.0;
	String current_branch;

	void _refresh_vcs();
	static String _find_git_branch();
	void _update_icons();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	Button *get_drawer_button() const { return drawer_button; }
	Button *get_log_button() const { return log_button; }
	Button *get_history_button() const { return history_button; }
	BackgroundProgress *get_tasks() const { return tasks; }

	String get_current_branch() const { return current_branch; }

	EditorStatusBar();
};
