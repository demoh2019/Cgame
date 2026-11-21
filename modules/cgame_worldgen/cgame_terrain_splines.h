/**************************************************************************/
/*  cgame_terrain_splines.h                                               */
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
#include "core/variant/typed_array.h"

class CgameTerrainSplines : public RefCounted {
	GDCLASS(CgameTerrainSplines, RefCounted);

	static double _sample_height(const float *p_heights, int p_width, int p_height, double p_cell_size, double p_wx, double p_wz);
	static Vector2 _nearest(const Vector2 &p_point, const Vector3 *p_spline, int p_count);

protected:
	static void _bind_methods();

public:
	static PackedVector3Array catmull_rom(const PackedVector3Array &p_points, int p_samples_per_segment);
	static double distance_to_polyline(const Vector2 &p_point, const PackedVector2Array &p_polyline);
	static PackedFloat32Array deform(const PackedFloat32Array &p_heights, int p_width, int p_height, double p_cell_size, const PackedVector3Array &p_spline, double p_half_width, double p_falloff, const String &p_mode);
	static TypedArray<Dictionary> bridge_spans(const PackedFloat32Array &p_heights, int p_width, int p_height, double p_cell_size, const PackedVector3Array &p_spline, double p_clearance = 2.0);
};
