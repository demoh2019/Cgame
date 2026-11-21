/**************************************************************************/
/*  cgame_safe_area.h                                                     */
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

#include "core/object/ref_counted.h"

class MarginContainer;
class Viewport;

// Safe-area insets (notches, rounded corners, TV overscan, handheld bezels). HUD margins grow by the part of the
// window the display reports as unsafe, so nothing important is drawn under a cut-out.
class CgameSafeArea : public RefCounted {
	GDCLASS(CgameSafeArea, RefCounted);

public:
	enum {
		BASE_MARGIN = 14,
	};

protected:
	static void _bind_methods();

public:
	static Dictionary insets(const Vector2i &p_window_size, const Rect2i &p_safe_rect);
	static Dictionary from_display(const Vector2i &p_window_position, const Vector2i &p_window_size, const Rect2i &p_screen_safe_rect, const Vector2 &p_canvas_size);
	static Dictionary current(Viewport *p_viewport);
	static void apply(MarginContainer *p_margin, const Dictionary &p_insets, int p_base = BASE_MARGIN);
};
