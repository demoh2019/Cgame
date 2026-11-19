/**************************************************************************/
/*  rope_geometry.h                                             */
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

#include "core/math/vector3.h"
#include "core/variant/variant.h"

// Layout and mesh math of Rope3D, without any scene or physics code so it can be unit tested.
namespace RopeGeometry {

// Points of a rope hanging between `p_start` and `p_end` with the given arc length, as p_segments + 1
// points joined by segments of equal length. A rope longer than the distance sags toward
// `p_down` (a parabola; the sag is found so the arc length matches). A rope that is not longer than
// the distance is a straight line. Returns false for invalid input.
bool layout_points(const Vector3 &p_start, const Vector3 &p_end, real_t p_length, int p_segments, const Vector3 &p_down, Vector<Vector3> &r_points);

// Total length of the polyline through the points.
real_t polyline_length(const Vector<Vector3> &p_points);

struct TubeMesh {
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedInt32Array indices;
};

// Tube of radius `p_radius` with `p_radial` sides around the polyline. Uses a parallel transported
// frame so the tube does not twist, closes the ends with caps and sets u around, v along the rope
// (one unit per `p_uv_length` meters). Returns false for fewer than two points or a degenerate rope.
bool build_tube(const Vector<Vector3> &p_points, real_t p_radius, int p_radial, real_t p_uv_length, TubeMesh &r_mesh);

} // namespace RopeGeometry
