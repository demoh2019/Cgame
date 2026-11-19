/**************************************************************************/
/*  debug_draw_geometry.h                                             */
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

#include "core/math/aabb.h"
#include "core/math/color.h"
#include "core/math/rect2.h"
#include "core/math/transform_3d.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "core/templates/local_vector.h"

// Line segments produced by the debug shapes. Pure data and math (no rendering), so the shapes
// are unit-testable and shared by the 2D and 3D debug drawing.
struct DebugSegment3D {
	Vector3 a;
	Vector3 b;
	Color color;
};

struct DebugSegment2D {
	Vector2 a;
	Vector2 b;
	Color color;
};

namespace DebugDrawGeometry {

// Any ring, circle or sphere is approximated with at least this many segments.
inline constexpr int MIN_SEGMENTS = 3;
inline constexpr int MAX_SEGMENTS = 256;

int clamp_segments(int p_segments);

void circle_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_center, const Vector3 &p_normal, real_t p_radius, const Color &p_color, int p_segments);
// Three orthogonal great circles; `p_segments` per circle.
void sphere_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_center, real_t p_radius, const Color &p_color, int p_segments);
void box_3d(LocalVector<DebugSegment3D> &r_out, const Transform3D &p_transform, const Vector3 &p_size, const Color &p_color);
void aabb_3d(LocalVector<DebugSegment3D> &r_out, const AABB &p_aabb, const Color &p_color);
// Shaft plus four head lines. `p_head_size` is the head length (absolute); it is capped to the arrow length.
void arrow_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_from, const Vector3 &p_to, const Color &p_color, real_t p_head_size);
// Three axis-aligned lines through the point, `p_size` long in total.
void cross_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_position, real_t p_size, const Color &p_color);
// Red/green/blue X/Y/Z axes of a transform, like the editor gizmo.
void axes_3d(LocalVector<DebugSegment3D> &r_out, const Transform3D &p_transform, real_t p_size);
void path_3d(LocalVector<DebugSegment3D> &r_out, const Vector<Vector3> &p_points, const Color &p_color, bool p_closed);

void circle_2d(LocalVector<DebugSegment2D> &r_out, const Vector2 &p_center, real_t p_radius, const Color &p_color, int p_segments);
void rect_2d(LocalVector<DebugSegment2D> &r_out, const Rect2 &p_rect, const Color &p_color);
void arrow_2d(LocalVector<DebugSegment2D> &r_out, const Vector2 &p_from, const Vector2 &p_to, const Color &p_color, real_t p_head_size);
void cross_2d(LocalVector<DebugSegment2D> &r_out, const Vector2 &p_position, real_t p_size, const Color &p_color);
void path_2d(LocalVector<DebugSegment2D> &r_out, const Vector<Vector2> &p_points, const Color &p_color, bool p_closed);

} // namespace DebugDrawGeometry
