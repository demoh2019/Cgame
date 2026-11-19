/**************************************************************************/
/*  test_x11_input.cpp                                                    */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_x11_input)

#if defined(LINUXBSD_ENABLED) && defined(X11_ENABLED)

#include "platform/linuxbsd/x11/display_server_x11.h"

// The X11 driver can be tested without opening a display connection.
class TestX11InputAccess {
public:
	static bool suppress_text(unsigned int p_flags) {
		return DisplayServerX11::_is_text_suppressed(p_flags);
	}

	static bool track_double_click(MouseButton p_button) {
		return DisplayServerX11::_tracks_double_click(p_button);
	}
};

namespace TestX11Input {

TEST_CASE("[X11] Ctrl, Alt, Meta and AltGr modifiers suppress only shortcut text") {
	struct ModifierCase {
		unsigned int flags;
		bool suppress;
	};
	const ModifierCase cases[] = {
		{ 0, false },
		{ ShiftMask, false },
		{ ControlMask, true },
		{ ControlMask | ShiftMask, true },
		{ Mod1Mask, true },
		{ Mod1Mask | ShiftMask, true },
		{ Mod4Mask, true },
		{ Mod4Mask | ShiftMask, true },
		{ ControlMask | Mod1Mask, false }, // AltGr
		{ ControlMask | Mod1Mask | ShiftMask, false }, // AltGr + Shift
		{ ControlMask | Mod4Mask, true },
		{ Mod1Mask | Mod4Mask, true },
		{ ControlMask | Mod1Mask | Mod4Mask, true },
		{ ControlMask | Mod1Mask | Mod4Mask | ShiftMask, true },
		{ ControlMask | Mod2Mask, true },
		{ Mod2Mask, false }, // NumLock
		{ LockMask, false }, // CapsLock
		{ ControlMask | LockMask, true },
	};
	for (const ModifierCase &test : cases) {
		CHECK(TestX11InputAccess::suppress_text(test.flags) == test.suppress);
	}
}

TEST_CASE("[X11] Wheel events never affect double-click tracking") {
	const MouseButton buttons_to_track[] = {
		MouseButton::LEFT,
		MouseButton::RIGHT,
		MouseButton::MIDDLE,
		MouseButton::MB_XBUTTON1,
		MouseButton::MB_XBUTTON2,
	};
	for (MouseButton button : buttons_to_track) {
		CHECK(TestX11InputAccess::track_double_click(button));
	}
	const MouseButton wheel_buttons[] = {
		MouseButton::WHEEL_UP,
		MouseButton::WHEEL_DOWN,
		MouseButton::WHEEL_LEFT,
		MouseButton::WHEEL_RIGHT,
	};
	for (MouseButton button : wheel_buttons) {
		CHECK_FALSE(TestX11InputAccess::track_double_click(button));
	}
}

} // namespace TestX11Input

#endif // LINUXBSD_ENABLED && X11_ENABLED
