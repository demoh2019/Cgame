/**************************************************************************/
/*  editor_cgame_ux.cpp                                                   */
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

#include "editor_cgame_ux.h"

#include "core/input/input_event.h"
#include "core/input/shortcut.h"
#include "core/os/keyboard.h"
#include "editor/settings/editor_settings.h"

void CgameEditorUX::register_settings() {
	EditorSettings *settings = EditorSettings::get_singleton();
	ERR_FAIL_NULL(settings);

	EDITOR_DEF_RST("interface/cgame_ux/shortcut_preset", (int)SHORTCUT_PRESET_GODOT);
	settings->add_property_hint(PropertyInfo(Variant::INT, "interface/cgame_ux/shortcut_preset", PROPERTY_HINT_ENUM, "Godot,Unreal-style"));

	EDITOR_DEF_RST("interface/cgame_ux/show_main_toolbar", true);
	EDITOR_DEF_RST("interface/cgame_ux/show_status_bar", true);

	EDITOR_DEF("interface/cgame_ux/content_drawer_height", 0.42);
	settings->add_property_hint(PropertyInfo(Variant::FLOAT, "interface/cgame_ux/content_drawer_height", PROPERTY_HINT_RANGE, "0.2,0.9,0.01"));
	EDITOR_DEF("interface/cgame_ux/content_drawer_animation", true);
}

CgameEditorUX::ShortcutPreset CgameEditorUX::get_shortcut_preset() {
	if (!EditorSettings::get_singleton() || !EditorSettings::get_singleton()->has_setting("interface/cgame_ux/shortcut_preset")) {
		return SHORTCUT_PRESET_GODOT;
	}
	return (ShortcutPreset)(int)EDITOR_GET("interface/cgame_ux/shortcut_preset");
}

namespace {

// A binding that the preset wants to change. `append` keeps the existing events and adds one more.
struct PresetBinding {
	const char *path;
	Key keycode;
	bool physical;
	bool append;
};

Array _make_events(const Vector<Key> &p_keys, bool p_physical) {
	Array events;
	for (const Key key : p_keys) {
		if (key != Key::NONE) {
			events.push_back(InputEventKey::create_reference(key, p_physical));
		}
	}
	return events;
}

bool _events_contain(const Array &p_events, const Ref<InputEventKey> &p_key) {
	for (int i = 0; i < p_events.size(); i++) {
		Ref<InputEventKey> existing = p_events[i];
		if (existing.is_valid() && existing->is_match(p_key, true) && existing->get_modifiers_mask() == p_key->get_modifiers_mask()) {
			return true;
		}
	}
	return false;
}

} // namespace

void CgameEditorUX::apply_shortcut_preset() {
	if (!is_unreal_shortcut_preset_enabled()) {
		return;
	}

	// Q/W/E/R/F are already Unreal-compatible in Godot (W/E/R move/rotate/scale, F frames the selection),
	// so only the differing bindings are listed here.
	static const PresetBinding bindings[] = {
		// Q is "Select" in Unreal. Godot's Q is the combined transform tool, which moves to Shift+Q.
		{ "spatial_editor/tool_select", Key::Q, true, false },
		{ "spatial_editor/tool_transform", KeyModifierMask::SHIFT | Key::Q, true, false },
		// G toggles Game View; 2D pan mode uses H instead.
		{ "spatial_editor/game_view", Key::G, false, false },
		{ "canvas_item_editor/pan_mode", Key::H, false, false },
		// End snaps the selection to the floor.
		{ "spatial_editor/snap_to_floor", Key::END, false, false },
		// F11 toggles immersive mode (hides the docks).
		{ "editor/distraction_free_mode", Key::F11, false, false },
		// Alt+P plays in the editor, in addition to the default Run binding.
		{ "editor/run_project", KeyModifierMask::ALT | Key::P, false, true },
		// Ctrl+B browses to the asset of the current selection (Control key on every platform).
		{ "editor/browse_to_asset", KeyModifierMask::CTRL | Key::B, false, false },
		{ "scene_tree/show_in_file_system", KeyModifierMask::CTRL | Key::B, false, false },
		// Ctrl+Shift+S saves all, Save As moves to Ctrl+Alt+Shift+S (swapped with Godot's layout).
		{ "editor/save_all_scenes", KeyModifierMask::CMD_OR_CTRL | KeyModifierMask::SHIFT | Key::S, false, false },
		{ "editor/save_scene_as", KeyModifierMask::CMD_OR_CTRL | KeyModifierMask::SHIFT | KeyModifierMask::ALT | Key::S, false, false },
	};

	EditorSettings *settings = EditorSettings::get_singleton();
	for (const PresetBinding &binding : bindings) {
		Ref<Shortcut> shortcut = settings->get_shortcut(binding.path);
		if (shortcut.is_null()) {
			continue;
		}

		const Array current = shortcut->get_events();
		const Variant original = shortcut->get_meta("original", current);
		// Never override a shortcut the user customized.
		if (!Shortcut::is_event_array_equal(current, original)) {
			continue;
		}

		Vector<Key> keys;
		keys.push_back(binding.keycode);
		Array new_events = _make_events(keys, binding.physical);

		if (binding.append) {
			Array merged = current.duplicate(true);
			Ref<InputEventKey> added = new_events.is_empty() ? Ref<InputEventKey>() : Ref<InputEventKey>(new_events[0]);
			if (added.is_valid() && !_events_contain(merged, added)) {
				merged.push_back(added);
			}
			new_events = merged;
		}

		shortcut->set_events(new_events);
		// Keep the preset as the baseline, so it is not persisted as a user customization.
		shortcut->set_meta("original", new_events.duplicate(true));
	}
}
