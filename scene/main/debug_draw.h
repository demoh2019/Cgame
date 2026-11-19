/**************************************************************************/
/*  debug_draw.h                                             */
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

#include "scene/main/debug_draw_buffer.h"
#include "scene/main/debug_draw_geometry.h"

#include "core/object/object.h"
#include "core/object/ref_counted.h"

class StandardMaterial3D;

// Immediate-mode debug drawing for running games (Unity's Debug.DrawLine / DrawRay and Gizmos).
// Call from any script at any time; shapes appear in the main viewport for the given duration.
class DebugDraw : public Object {
	GDCLASS(DebugDraw, Object);

	static DebugDraw *singleton;

	DebugDrawBuffer<DebugSegment3D> buffer_3d;
	DebugDrawBuffer<DebugSegment2D> buffer_2d;

	bool enabled = true;
	bool depth_test = true;
	bool connected = false;
	uint64_t frame = 0;

	// Rendering resources, created on first use.
	RID mesh_3d;
	RID instance_3d;
	RID canvas_item_2d;
	Ref<StandardMaterial3D> material_3d;
	bool has_3d_surface = false;

	double _now() const;
	void _ensure_connected();
	void _ensure_3d_resources();
	void _ensure_2d_resources();
	void _on_process_frame();
	void _on_pre_draw();
	void _free_resources();

	void _add_3d(const LocalVector<DebugSegment3D> &p_segments, double p_duration);
	void _add_2d(const LocalVector<DebugSegment2D> &p_segments, double p_duration);

protected:
	static void _bind_methods();

public:
	static DebugDraw *get_singleton() { return singleton; }

	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }
	void set_depth_test(bool p_enabled);
	bool is_depth_test_enabled() const { return depth_test; }

	void line(const Vector3 &p_from, const Vector3 &p_to, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0);
	void ray(const Vector3 &p_origin, const Vector3 &p_direction, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0);
	void arrow(const Vector3 &p_from, const Vector3 &p_to, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, real_t p_head_size = 0.25);
	void point(const Vector3 &p_position, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, real_t p_size = 0.2);
	void sphere(const Vector3 &p_center, real_t p_radius = 0.5, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, int p_segments = 24);
	void circle(const Vector3 &p_center, const Vector3 &p_normal, real_t p_radius = 0.5, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, int p_segments = 32);
	void box(const Transform3D &p_transform, const Vector3 &p_size, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0);
	void aabb(const AABB &p_aabb, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0);
	void axes(const Transform3D &p_transform, real_t p_size = 1.0, double p_duration = 0.0);
	void path(const Vector<Vector3> &p_points, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, bool p_closed = false);

	void line_2d(const Vector2 &p_from, const Vector2 &p_to, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0);
	void arrow_2d(const Vector2 &p_from, const Vector2 &p_to, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, real_t p_head_size = 12.0);
	void point_2d(const Vector2 &p_position, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, real_t p_size = 8.0);
	void circle_2d(const Vector2 &p_center, real_t p_radius = 16.0, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, int p_segments = 32);
	void rect_2d(const Rect2 &p_rect, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0);
	void path_2d(const Vector<Vector2> &p_points, const Color &p_color = Color(1, 1, 1), double p_duration = 0.0, bool p_closed = false);

	void clear();
	int get_segment_count_3d() const { return buffer_3d.size(); }
	int get_segment_count_2d() const { return buffer_2d.size(); }

	DebugDraw();
	~DebugDraw();
};
