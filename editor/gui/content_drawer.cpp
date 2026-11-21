/**************************************************************************/
/*  content_drawer.cpp                                                    */
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

#include "content_drawer.h"

#include "core/input/input_event.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "editor/docks/editor_dock.h"
#include "editor/docks/editor_dock_manager.h"
#include "editor/docks/filesystem_dock.h"
#include "editor/editor_string_names.h"
#include "editor/settings/editor_command_palette.h"
#include "editor/settings/editor_settings.h"
#include "editor/themes/editor_scale.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"
#include "scene/gui/label.h"
#include "scene/gui/margin_container.h"
#include "scene/gui/panel_container.h"
#include "scene/main/viewport.h"

ContentDrawer *ContentDrawer::singleton = nullptr;

int ContentDrawer::_get_bottom_inset() const {
	if (!bottom_anchor || !bottom_anchor->is_inside_tree() || !bottom_anchor->is_visible_in_tree()) {
		return 0;
	}
	const real_t anchor_top = bottom_anchor->get_global_position().y - get_global_position().y;
	return MAX(0, (int)(get_size().y - anchor_top));
}

int ContentDrawer::_get_drawer_height() const {
	const real_t ratio = CLAMP((real_t)EDITOR_GET("interface/cgame_ux/content_drawer_height"), (real_t)0.2, (real_t)0.9);
	const int available = (int)get_size().y - _get_bottom_inset();
	const int min_height = (int)(220 * EDSCALE);
	const int max_height = MAX(min_height, available - (int)(80 * EDSCALE));
	return CLAMP((int)(get_size().y * ratio), min_height, max_height);
}

void ContentDrawer::_update_geometry() {
	const int margin = (int)(8 * EDSCALE);
	const int height = _get_drawer_height();
	const Size2 base_size = get_size();

	panel->set_size(Size2(MAX(0, base_size.x - margin * 2), height));
	panel->set_position(Point2(margin, base_size.y - _get_bottom_inset() - height));
}

void ContentDrawer::_kill_tween() {
	if (tween.is_valid()) {
		tween->kill();
		tween.unref();
	}
}

void ContentDrawer::setup(EditorDock *p_dock, Control *p_bottom_anchor) {
	hosted_dock = p_dock;
	bottom_anchor = p_bottom_anchor;
	// Requests to focus the (closed) FileSystem dock open the drawer instead of docking it into the layout.
	EditorDockManager::get_singleton()->set_focus_override(p_dock, callable_mp(this, &ContentDrawer::open_drawer).bind(true));

	EditorCommandPalette *palette = EditorCommandPalette::get_singleton();
	if (!palette->has_command("editor/content_drawer_pin")) {
		palette->add_command(TTR("Content Drawer: Dock in Layout"), "editor/content_drawer_pin", callable_mp(this, &ContentDrawer::pin_to_layout));
		palette->add_command(TTR("Content Drawer: Remove from Layout"), "editor/content_drawer_unpin", callable_mp(this, &ContentDrawer::unpin_from_layout));
	}
}

void ContentDrawer::_hosted_dock_left() {
	// The dock was moved elsewhere (pinned, or a layout was loaded). Hide the overlay without touching the dock.
	_kill_tween();
	drawer_open = false;
	animating_close = false;
	drag_collapsed = false;
	panel->hide();
	set_mouse_filter(MOUSE_FILTER_IGNORE);
	set_process_internal(false);
}

void ContentDrawer::open_drawer(bool p_animate) {
	ERR_FAIL_NULL(hosted_dock);

	if (hosted_dock->is_dock_open()) {
		// The dock is part of the layout (pinned): just bring it to the front.
		EditorDockManager::get_singleton()->focus_dock(hosted_dock);
		return;
	}

	if (drawer_open) {
		return;
	}

	_kill_tween();
	animating_close = false;
	drag_collapsed = false;
	drawer_open = true;

	if (hosted_dock->get_parent() != host) {
		EditorDockManager::get_singleton()->host_dock(hosted_dock, host);
	}

	set_mouse_filter(MOUSE_FILTER_STOP);
	set_process_internal(true);
	panel->show();
	_update_geometry();

	const real_t target_y = panel->get_position().y;
	if (p_animate && bool(EDITOR_GET("interface/cgame_ux/content_drawer_animation"))) {
		panel->set_position(Point2(panel->get_position().x, get_size().y));
		tween = create_tween();
		tween->tween_property(panel, NodePath("position:y"), target_y, 0.18)->set_trans(Tween::TRANS_CUBIC)->set_ease(Tween::EASE_OUT);
		tween->tween_callback(callable_mp(this, &ContentDrawer::_open_finished));
	} else {
		_open_finished();
	}

	// The search box only becomes focusable once the dock is visible in the tree.
	callable_mp(FileSystemDock::get_singleton(), &FileSystemDock::focus_on_filter).call_deferred();
}

void ContentDrawer::_open_finished() {
	tween.unref();
	if (drawer_open && !drag_collapsed) {
		FileSystemDock::get_singleton()->focus_on_filter();
	}
}

void ContentDrawer::close_drawer(bool p_animate) {
	if (!drawer_open) {
		return;
	}

	drawer_open = false;
	drag_collapsed = false;
	set_mouse_filter(MOUSE_FILTER_IGNORE);
	_kill_tween();

	if (p_animate && bool(EDITOR_GET("interface/cgame_ux/content_drawer_animation"))) {
		animating_close = true;
		tween = create_tween();
		tween->tween_property(panel, NodePath("position:y"), get_size().y, 0.14)->set_trans(Tween::TRANS_CUBIC)->set_ease(Tween::EASE_IN);
		tween->tween_callback(callable_mp(this, &ContentDrawer::_close_finished));
	} else {
		_close_finished();
	}
}

void ContentDrawer::_close_finished() {
	tween.unref();
	animating_close = false;
	panel->hide();
	set_process_internal(false);

	if (!drawer_open && hosted_dock) {
		EditorDockManager::get_singleton()->unhost_dock(hosted_dock);
	}
}

void ContentDrawer::toggle_drawer() {
	if (drawer_open) {
		close_drawer();
	} else {
		open_drawer();
	}
}

void ContentDrawer::pin_to_layout() {
	ERR_FAIL_NULL(hosted_dock);
	if (hosted_dock->is_dock_open()) {
		return;
	}
	// Hide the overlay first; the dock leaving the host is handled in _hosted_dock_exiting().
	_hosted_dock_left();
	EditorDockManager::get_singleton()->pin_dock(hosted_dock, EditorDock::DOCK_SLOT_BOTTOM_L);
}

void ContentDrawer::unpin_from_layout() {
	ERR_FAIL_NULL(hosted_dock);
	if (hosted_dock->is_dock_open()) {
		EditorDockManager::get_singleton()->close_dock(hosted_dock);
	}
}

void ContentDrawer::_pin_pressed() {
	pin_to_layout();
}

void ContentDrawer::gui_input(const Ref<InputEvent> &p_event) {
	// Only events outside of the panel reach this control, because the panel stops mouse events.
	Ref<InputEventMouseButton> mb = p_event;
	if (drawer_open && mb.is_valid() && mb->is_pressed()) {
		close_drawer();
		accept_event();
	}
}

void ContentDrawer::shortcut_input(const Ref<InputEvent> &p_event) {
	if (p_event.is_null() || !p_event->is_pressed() || p_event->is_echo()) {
		return;
	}
	if (ED_IS_SHORTCUT("editor/content_drawer", p_event)) {
		toggle_drawer();
		get_viewport()->set_input_as_handled();
	}
}

void ContentDrawer::unhandled_key_input(const Ref<InputEvent> &p_event) {
	if (!drawer_open || p_event.is_null() || !p_event->is_pressed() || p_event->is_echo()) {
		return;
	}
	if (p_event->is_action_pressed(SNAME("ui_cancel"), false, true)) {
		close_drawer();
		get_viewport()->set_input_as_handled();
	}
}

void ContentDrawer::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_THEME_CHANGED: {
			pin_button->set_button_icon(get_editor_theme_icon(SNAME("Pin")));
			close_button->set_button_icon(get_editor_theme_icon(SNAME("Close")));
		} break;

		case NOTIFICATION_RESIZED: {
			if (drawer_open && tween.is_null()) {
				_update_geometry();
			}
		} break;

		case NOTIFICATION_INTERNAL_PROCESS: {
			// The dock manager blocks signals while moving docks, so detect a dock that left the host by polling.
			if (drawer_open && hosted_dock && hosted_dock->get_parent() != host) {
				_hosted_dock_left();
				break;
			}

			// While a drag is in progress the overlay must not swallow the drop target below it.
			const bool dragging = get_viewport() && get_viewport()->gui_is_dragging();
			if (drawer_open && dragging && !drag_collapsed) {
				drag_collapsed = true;
				set_mouse_filter(MOUSE_FILTER_IGNORE);
			} else if (drawer_open && !dragging && drag_collapsed) {
				// The drag ended (drop or cancel): dismiss the drawer, like UE does after dragging an asset out.
				close_drawer();
			}
		} break;
	}
}

void ContentDrawer::_bind_methods() {
}

ContentDrawer::ContentDrawer() {
	singleton = this;

	set_anchors_and_offsets_preset(PRESET_FULL_RECT);
	set_mouse_filter(MOUSE_FILTER_IGNORE);
	set_process_shortcut_input(true);
	set_process_unhandled_key_input(true);
	set_name("ContentDrawer");

	ED_SHORTCUT_AND_COMMAND("editor/content_drawer", TTRC("Toggle Content Drawer"), KeyModifierMask::CMD_OR_CTRL | Key::SPACE);
	// Cmd+Space is Spotlight on macOS.
	ED_SHORTCUT_OVERRIDE("editor/content_drawer", "macos", KeyModifierMask::META | KeyModifierMask::SHIFT | Key::SPACE);

	EDITOR_DEF("interface/cgame_ux/content_drawer_height", 0.42);
	EDITOR_DEF("interface/cgame_ux/content_drawer_animation", true);

	panel = memnew(PanelContainer);
	panel->set_theme_type_variation("PanelForeground");
	panel->set_mouse_filter(MOUSE_FILTER_STOP);
	panel->hide();
	add_child(panel);

	VBoxContainer *vbox = memnew(VBoxContainer);
	panel->add_child(vbox);

	HBoxContainer *header = memnew(HBoxContainer);
	vbox->add_child(header);

	title_label = memnew(Label);
	title_label->set_text(TTRC("Content Drawer"));
	title_label->set_theme_type_variation("HeaderSmall");
	title_label->set_h_size_flags(SIZE_EXPAND_FILL);
	header->add_child(title_label);

	pin_button = memnew(Button);
	pin_button->set_text(TTRC("Dock in Layout"));
	pin_button->set_flat(true);
	pin_button->set_tooltip_text(TTRC("Dock the FileSystem into the bottom of the editor layout so it stays open."));
	pin_button->connect(SceneStringName(pressed), callable_mp(this, &ContentDrawer::_pin_pressed));
	header->add_child(pin_button);

	close_button = memnew(Button);
	close_button->set_flat(true);
	close_button->set_tooltip_text(TTRC("Close the Content Drawer (Esc)."));
	close_button->set_accessibility_name(TTRC("Close"));
	close_button->connect(SceneStringName(pressed), callable_mp(this, &ContentDrawer::close_drawer).bind(true));
	header->add_child(close_button);

	host = memnew(MarginContainer);
	host->set_v_size_flags(SIZE_EXPAND_FILL);
	vbox->add_child(host);
}

ContentDrawer::~ContentDrawer() {
	if (singleton == this) {
		singleton = nullptr;
	}
}
