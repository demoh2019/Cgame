/**************************************************************************/
/*  cgame_early_reflections.h                                             */
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

// Early reflection simulation for shoebox rooms plus IR synthesis.
//
// Method references (algorithms only, no code copied):
//  - J. B. Allen and D. A. Berkley, "Image method for efficiently simulating small-room
//    acoustics", JASA 65(4), 1979 (image-source method).
//  - Krokstad, Strom and Sorsdal, "Calculating the acoustical room response by the use of a
//    ray tracing technique", J. Sound Vib. 8(1), 1968 (echogram histogram conversion).
// The API mirrors the project's GDScript early_reflections.gd / acoustic_rooms.gd helpers.

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class CgameEarlyReflections : public RefCounted {
	GDCLASS(CgameEarlyReflections, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr double MIN_DISTANCE = 0.1;

	static TypedArray<Dictionary> image_sources_box(const Vector3 &p_room_size, const Vector3 &p_source, const Vector3 &p_listener, int p_order, float p_absorption, float p_speed = 343.0f);
	static TypedArray<Dictionary> echogram_to_reflections(const PackedFloat32Array &p_echogram, float p_bin_s);
	static PackedFloat32Array impulse_response(const Vector3 &p_rt60, int p_sample_rate, float p_seconds, int64_t p_seed);
	static PackedFloat32Array to_ir(const TypedArray<Dictionary> &p_reflections, int p_sample_rate, float p_length_s, const Vector3 &p_rt60 = Vector3(0.7, 0.6, 0.4), float p_late_start_s = 0.04f, float p_late_gain = 0.25f, int64_t p_seed = 1);

	// Number of image sources (including the direct path) for a shoebox up to p_order bounces.
	static int image_source_count(int p_order);
};
