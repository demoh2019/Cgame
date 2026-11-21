/**************************************************************************/
/*  content_drawer.h                                                      */
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

#include "scene/animation/tween.h"
#include "scene/gui/control.h"

class Button;
class EditorDock;
class Label;
class MarginContainer;
class PanelContainer;

// UE-style Content Drawer: a transient slide-up overlay that hosts the FileSystem dock.
// Ctrl+Space toggles it, Esc or a click outside closes it, and "Dock in Layout" pins the
// FileSystem dock into the regular dock layout (bottom-left slot).
class ContentDrawer : public Control {
	GDCLASS(ContentDrawer, Control);

	static ContentDrawer *singleton;

	PanelContainer *panel = nullptr;
	Label *title_label = nullptr;
	Button *pin_button = nullptr;
	Button *close_button = nullptr;
	MarginContainer *host = nullptr;

	EditorDock *hosted_dock = nullptr;
	Control *bottom_anchor = nullptr;
	Ref<Tween> tween;

	bool drawer_open = false;
	bool animating_close = false;
	bool drag_collapsed = false;

	void _update_geometry();
	void _kill_tween();
	void _open_finished();
	void _close_finished();
	void _pin_pressed();
	void _hosted_dock_left();
	int _get_drawer_height() const;
	int _get_bottom_inset() const;

protected:
	void _notification(int p_what);
	static void _bind_methods();

	virtual void gui_input(const Ref<InputEvent> &p_event) override;
	virtual void shortcut_input(const Ref<InputEvent> &p_event) override;
	virtual void unhandled_key_input(const Ref<InputEvent> &p_event) override;

public:
	static ContentDrawer *get_singleton() { return singleton; }

	void setup(EditorDock *p_dock, Control *p_bottom_anchor);

	void open_drawer(bool p_animate = true);
	void close_drawer(bool p_animate = true);
	void toggle_drawer();
	bool is_drawer_open() const { return drawer_open; }

	// Pins the FileSystem dock into the layout, or removes it from the layout so the drawer hosts it again.
	void pin_to_layout();
	void unpin_from_layout();

	ContentDrawer();
	~ContentDrawer();
};
