/**************************************************************************/
/*  debug_draw_geometry.cpp                                             */
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

#include "debug_draw_geometry.h"

namespace DebugDrawGeometry {

int clamp_segments(int p_segments) {
	return CLAMP(p_segments, MIN_SEGMENTS, MAX_SEGMENTS);
}

void circle_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_center, const Vector3 &p_normal, real_t p_radius, const Color &p_color, int p_segments) {
	const int segments = clamp_segments(p_segments);
	Vector3 normal = p_normal.is_zero_approx() ? Vector3(0, 1, 0) : p_normal.normalized();
	// Any vector not parallel to the normal gives a stable tangent frame.
	const Vector3 helper = Math::abs(normal.y) < real_t(0.99) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
	const Vector3 u = normal.cross(helper).normalized();
	const Vector3 v = normal.cross(u);
	Vector3 previous = p_center + u * p_radius;
	for (int i = 1; i <= segments; i++) {
		const real_t angle = real_t(Math::TAU) * real_t(i) / real_t(segments);
		const Vector3 point = p_center + (u * Math::cos(angle) + v * Math::sin(angle)) * p_radius;
		r_out.push_back({ previous, point, p_color });
		previous = point;
	}
}

void sphere_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_center, real_t p_radius, const Color &p_color, int p_segments) {
	circle_3d(r_out, p_center, Vector3(1, 0, 0), p_radius, p_color, p_segments);
	circle_3d(r_out, p_center, Vector3(0, 1, 0), p_radius, p_color, p_segments);
	circle_3d(r_out, p_center, Vector3(0, 0, 1), p_radius, p_color, p_segments);
}

void box_3d(LocalVector<DebugSegment3D> &r_out, const Transform3D &p_transform, const Vector3 &p_size, const Color &p_color) {
	const Vector3 h = p_size * real_t(0.5);
	Vector3 corners[8];
	for (int i = 0; i < 8; i++) {
		corners[i] = p_transform.xform(Vector3((i & 1) ? h.x : -h.x, (i & 2) ? h.y : -h.y, (i & 4) ? h.z : -h.z));
	}
	// Each corner connects to its three neighbors that differ in one axis bit (12 unique edges).
	for (int i = 0; i < 8; i++) {
		for (int bit = 1; bit <= 4; bit <<= 1) {
			if (!(i & bit)) {
				r_out.push_back({ corners[i], corners[i | bit], p_color });
			}
		}
	}
}

void aabb_3d(LocalVector<DebugSegment3D> &r_out, const AABB &p_aabb, const Color &p_color) {
	const AABB box = p_aabb.abs();
	box_3d(r_out, Transform3D(Basis(), box.get_center()), box.size, p_color);
}

void arrow_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_from, const Vector3 &p_to, const Color &p_color, real_t p_head_size) {
	r_out.push_back({ p_from, p_to, p_color });
	const Vector3 shaft = p_to - p_from;
	const real_t length = shaft.length();
	if (length < real_t(CMP_EPSILON) || !(p_head_size > 0.0)) {
		return;
	}
	const Vector3 direction = shaft / length;
	const real_t head = MIN(p_head_size, length);
	const Vector3 helper = Math::abs(direction.y) < real_t(0.99) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
	const Vector3 u = direction.cross(helper).normalized();
	const Vector3 v = direction.cross(u);
	const Vector3 base = p_to - direction * head;
	const real_t spread = head * real_t(0.35);
	r_out.push_back({ p_to, base + u * spread, p_color });
	r_out.push_back({ p_to, base - u * spread, p_color });
	r_out.push_back({ p_to, base + v * spread, p_color });
	r_out.push_back({ p_to, base - v * spread, p_color });
}

void cross_3d(LocalVector<DebugSegment3D> &r_out, const Vector3 &p_position, real_t p_size, const Color &p_color) {
	const real_t h = p_size * real_t(0.5);
	r_out.push_back({ p_position - Vector3(h, 0, 0), p_position + Vector3(h, 0, 0), p_color });
	r_out.push_back({ p_position - Vector3(0, h, 0), p_position + Vector3(0, h, 0), p_color });
	r_out.push_back({ p_position - Vector3(0, 0, h), p_position + Vector3(0, 0, h), p_color });
}

void axes_3d(LocalVector<DebugSegment3D> &r_out, const Transform3D &p_transform, real_t p_size) {
	const Vector3 origin = p_transform.origin;
	r_out.push_back({ origin, origin + p_transform.basis.get_column(0).normalized() * p_size, Color(1, 0, 0) });
	r_out.push_back({ origin, origin + p_transform.basis.get_column(1).normalized() * p_size, Color(0, 1, 0) });
	r_out.push_back({ origin, origin + p_transform.basis.get_column(2).normalized() * p_size, Color(0.1, 0.4, 1) });
}

void path_3d(LocalVector<DebugSegment3D> &r_out, const Vector<Vector3> &p_points, const Color &p_color, bool p_closed) {
	const int count = p_points.size();
	for (int i = 0; i + 1 < count; i++) {
		r_out.push_back({ p_points[i], p_points[i + 1], p_color });
	}
	if (p_closed && count > 2) {
		r_out.push_back({ p_points[count - 1], p_points[0], p_color });
	}
}

void circle_2d(LocalVector<DebugSegment2D> &r_out, const Vector2 &p_center, real_t p_radius, const Color &p_color, int p_segments) {
	const int segments = clamp_segments(p_segments);
	Vector2 previous = p_center + Vector2(p_radius, 0);
	for (int i = 1; i <= segments; i++) {
		const real_t angle = real_t(Math::TAU) * real_t(i) / real_t(segments);
		const Vector2 point = p_center + Vector2(Math::cos(angle), Math::sin(angle)) * p_radius;
		r_out.push_back({ previous, point, p_color });
		previous = point;
	}
}

void rect_2d(LocalVector<DebugSegment2D> &r_out, const Rect2 &p_rect, const Color &p_color) {
	const Rect2 rect = p_rect.abs();
	const Vector2 a = rect.position;
	const Vector2 b = Vector2(rect.position.x + rect.size.x, rect.position.y);
	const Vector2 c = rect.position + rect.size;
	const Vector2 d = Vector2(rect.position.x, rect.position.y + rect.size.y);
	r_out.push_back({ a, b, p_color });
	r_out.push_back({ b, c, p_color });
	r_out.push_back({ c, d, p_color });
	r_out.push_back({ d, a, p_color });
}

void arrow_2d(LocalVector<DebugSegment2D> &r_out, const Vector2 &p_from, const Vector2 &p_to, const Color &p_color, real_t p_head_size) {
	r_out.push_back({ p_from, p_to, p_color });
	const Vector2 shaft = p_to - p_from;
	const real_t length = shaft.length();
	if (length < real_t(CMP_EPSILON) || !(p_head_size > 0.0)) {
		return;
	}
	const Vector2 direction = shaft / length;
	const real_t head = MIN(p_head_size, length);
	const Vector2 base = p_to - direction * head;
	const Vector2 side = direction.orthogonal() * head * real_t(0.35);
	r_out.push_back({ p_to, base + side, p_color });
	r_out.push_back({ p_to, base - side, p_color });
}

void cross_2d(LocalVector<DebugSegment2D> &r_out, const Vector2 &p_position, real_t p_size, const Color &p_color) {
	const real_t h = p_size * real_t(0.5);
	r_out.push_back({ p_position - Vector2(h, 0), p_position + Vector2(h, 0), p_color });
	r_out.push_back({ p_position - Vector2(0, h), p_position + Vector2(0, h), p_color });
}

void path_2d(LocalVector<DebugSegment2D> &r_out, const Vector<Vector2> &p_points, const Color &p_color, bool p_closed) {
	const int count = p_points.size();
	for (int i = 0; i + 1 < count; i++) {
		r_out.push_back({ p_points[i], p_points[i + 1], p_color });
	}
	if (p_closed && count > 2) {
		r_out.push_back({ p_points[count - 1], p_points[0], p_color });
	}
}

} // namespace DebugDrawGeometry
