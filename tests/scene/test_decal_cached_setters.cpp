/**************************************************************************/
/*  test_decal_cached_setters.cpp                                          */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_decal_cached_setters)

#ifndef _3D_DISABLED

#include "scene/3d/decal.h"

namespace TestDecalCachedSetters {

TEST_CASE("[SceneTree][Decal] Repeated pooled fade values preserve state") {
	Decal *decal = memnew(Decal);
	const Color damp(0.34, 0.24, 0.17, 0.50);

	decal->set_modulate(damp);
	CHECK(decal->get_modulate() == damp);
	// The second call must preserve the value without resubmitting it.
	decal->set_modulate(damp);
	CHECK(decal->get_modulate() == damp);

	decal->set_enable_distance_fade(true);
	CHECK(decal->is_distance_fade_enabled());
	decal->set_enable_distance_fade(true);
	CHECK(decal->is_distance_fade_enabled());

	decal->set_distance_fade_begin(23.0);
	decal->set_distance_fade_length(9.0);
	decal->set_distance_fade_begin(23.0);
	decal->set_distance_fade_length(9.0);
	CHECK(decal->get_distance_fade_begin() == 23.0);
	CHECK(decal->get_distance_fade_length() == 9.0);

	decal->set_modulate(Color(0.34, 0.24, 0.17, 0.0));
	CHECK(decal->get_modulate().a == 0.0);
	decal->set_modulate(damp);
	CHECK(decal->get_modulate() == damp);

	decal->set_enable_distance_fade(false);
	CHECK_FALSE(decal->is_distance_fade_enabled());
	memdelete(decal);
}

} // namespace TestDecalCachedSetters

#endif // _3D_DISABLED
