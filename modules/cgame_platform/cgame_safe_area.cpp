/**************************************************************************/
/*  cgame_safe_area.cpp                                                   */
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

#include "cgame_safe_area.h"

#include "core/object/class_db.h"
#include "scene/gui/margin_container.h"
#include "scene/main/viewport.h"
#include "servers/display/display_server.h"

static Dictionary _make_insets(int p_left, int p_top, int p_right, int p_bottom) {
	Dictionary d;
	d["left"] = p_left;
	d["top"] = p_top;
	d["right"] = p_right;
	d["bottom"] = p_bottom;
	return d;
}

Dictionary CgameSafeArea::insets(const Vector2i &p_window_size, const Rect2i &p_safe_rect) {
	if (p_window_size.x <= 0 || p_window_size.y <= 0 || p_safe_rect.size.x <= 0 || p_safe_rect.size.y <= 0) {
		return _make_insets(0, 0, 0, 0);
	}
	const Rect2i safe = p_safe_rect.intersection(Rect2i(Vector2i(), p_window_size));
	const Vector2i end = safe.get_end();
	return _make_insets(
			MAX(0, safe.position.x),
			MAX(0, safe.position.y),
			MAX(0, p_window_size.x - end.x),
			MAX(0, p_window_size.y - end.y));
}

Dictionary CgameSafeArea::from_display(const Vector2i &p_window_position, const Vector2i &p_window_size, const Rect2i &p_screen_safe_rect, const Vector2 &p_canvas_size) {
	const Rect2i local_safe(p_screen_safe_rect.position - p_window_position, p_screen_safe_rect.size);
	const Dictionary raw = insets(p_window_size, local_safe);
	// Stretch modes scale the 2D canvas: convert window pixels to canvas units.
	const Vector2 scale(p_canvas_size.x / MAX(1.0f, (float)p_window_size.x), p_canvas_size.y / MAX(1.0f, (float)p_window_size.y));
	return _make_insets(
			(int)Math::round((float)(int)raw["left"] * scale.x),
			(int)Math::round((float)(int)raw["top"] * scale.y),
			(int)Math::round((float)(int)raw["right"] * scale.x),
			(int)Math::round((float)(int)raw["bottom"] * scale.y));
}

Dictionary CgameSafeArea::current(Viewport *p_viewport) {
	DisplayServer *ds = DisplayServer::get_singleton();
	if (p_viewport == nullptr || ds == nullptr || ds->get_name() == "headless") {
		return insets(Vector2i(1, 1), Rect2i(Vector2i(), Vector2i(1, 1)));
	}
	return from_display(ds->window_get_position(), ds->window_get_size(), ds->get_display_safe_area(), p_viewport->get_visible_rect().size);
}

void CgameSafeArea::apply(MarginContainer *p_margin, const Dictionary &p_insets, int p_base) {
	if (p_margin == nullptr) {
		return;
	}
	static const char *sides[4] = { "left", "top", "right", "bottom" };
	for (int i = 0; i < 4; i++) {
		const String side = sides[i];
		const int inset = p_insets.has(side) ? (int)p_insets[side] : 0;
		p_margin->add_theme_constant_override("margin_" + side, p_base + inset);
	}
}

void CgameSafeArea::_bind_methods() {
	ClassDB::bind_static_method("CgameSafeArea", D_METHOD("insets", "window_size", "safe_rect"), &CgameSafeArea::insets);
	ClassDB::bind_static_method("CgameSafeArea", D_METHOD("from_display", "window_position", "window_size", "screen_safe_rect", "canvas_size"), &CgameSafeArea::from_display);
	ClassDB::bind_static_method("CgameSafeArea", D_METHOD("current", "viewport"), &CgameSafeArea::current);
	ClassDB::bind_static_method("CgameSafeArea", D_METHOD("apply", "margin", "insets", "base"), &CgameSafeArea::apply, DEFVAL((int)BASE_MARGIN));

	BIND_CONSTANT(BASE_MARGIN);
}
