/**************************************************************************/
/*  cgame_foveated_shading.h                                              */
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

#include "core/io/image.h"
#include "core/object/ref_counted.h"
#include "scene/resources/image_texture.h"

class Viewport;

// Variable Rate Shading / foveated rendering (UE5 VRS, Unity foveation, Metal rasterization rate
// maps). The top-down camera keeps the player at screen center, so edges are shaded at coarser
// rates on low presets. Unsupported GPUs ignore the texture; High/Ultra always shade full rate.
class CgameFoveatedShading : public RefCounted {
	GDCLASS(CgameFoveatedShading, RefCounted);

public:
	// Godot VRS density colors: R = horizontal, G = vertical (0 -> 1x, 85 -> 2x, 170 -> 4x).
	struct Rate {
		uint8_t r = 0;
		uint8_t g = 0;
	};
	static constexpr Rate RATE_1X1 = { 0, 0 };
	static constexpr Rate RATE_2X2 = { 85, 85 };
	static constexpr Rate RATE_4X4 = { 170, 170 };
	static constexpr Rate RATE_2X1 = { 85, 0 };
	static constexpr int TILE = 16; // Common shading-rate tile; Godot rescales anyway.

	struct Profile {
		bool enabled = false;
		float inner = 0.0f;
		float outer = 0.0f;
	};

private:
	static Ref<ImageTexture> cached;
	static String cached_key;

protected:
	static void _bind_methods();

public:
	// Pure parts (no engine singletons): used by tests.
	static Profile compute_profile(int p_level, const String &p_rendering_method);
	// Rate of one normalized screen position (u, v in -1..1).
	static Rate rate_at(float p_u, float p_v, float p_inner, float p_outer);
	// Tightly packed RGB8 rows.
	static Vector<uint8_t> build_map_data(const Vector2i &p_size, float p_inner, float p_outer);

	static Dictionary settings(int p_level, const String &p_rendering_method);
	// Elliptical rate map: full rate around the player, 2x2 ring, 4x4 corners.
	static Ref<Image> build_map(const Vector2i &p_size, float p_inner, float p_outer);
	static bool apply(Viewport *p_viewport, int p_level, const String &p_rendering_method);
};
