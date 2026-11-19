/**************************************************************************/
/*  debug_draw.cpp                                             */
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

#include "debug_draw.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/os/time.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/world_3d.h"
#include "scene/resources/material.h"
#include "scene/resources/world_2d.h"
#include "servers/rendering/rendering_server.h"

DebugDraw *DebugDraw::singleton = nullptr;

double DebugDraw::_now() const {
	return double(Time::get_singleton()->get_ticks_usec()) / 1000000.0;
}

void DebugDraw::_ensure_connected() {
	if (connected) {
		return;
	}
	SceneTree *tree = SceneTree::get_singleton();
	if (!tree || !RenderingServer::get_singleton()) {
		return;
	}
	tree->connect("process_frame", callable_mp(this, &DebugDraw::_on_process_frame));
	RenderingServer::get_singleton()->connect("frame_pre_draw", callable_mp(this, &DebugDraw::_on_pre_draw));
	connected = true;
}

void DebugDraw::_ensure_3d_resources() {
	RenderingServer *rs = RenderingServer::get_singleton();
	SceneTree *tree = SceneTree::get_singleton();
	if (!rs || !tree || !tree->get_root() || tree->get_root()->get_world_3d().is_null()) {
		return;
	}
	if (!mesh_3d.is_valid()) {
		mesh_3d = rs->mesh_create();
		material_3d.instantiate();
		material_3d->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
		material_3d->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
		material_3d->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
		material_3d->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, !depth_test);
	}
	if (!instance_3d.is_valid()) {
		instance_3d = rs->instance_create2(mesh_3d, tree->get_root()->get_world_3d()->get_scenario());
		// The geometry is rebuilt every frame and spans the whole world: never cull it.
		rs->instance_set_custom_aabb(instance_3d, AABB(Vector3(-1e7, -1e7, -1e7), Vector3(2e7, 2e7, 2e7)));
		rs->instance_geometry_set_flag(instance_3d, RSE::INSTANCE_FLAG_USE_BAKED_LIGHT, false);
		rs->instance_geometry_set_cast_shadows_setting(instance_3d, RSE::SHADOW_CASTING_SETTING_OFF);
	}
}

void DebugDraw::_ensure_2d_resources() {
	RenderingServer *rs = RenderingServer::get_singleton();
	SceneTree *tree = SceneTree::get_singleton();
	if (!rs || !tree || !tree->get_root() || tree->get_root()->get_world_2d().is_null()) {
		return;
	}
	if (!canvas_item_2d.is_valid()) {
		canvas_item_2d = rs->canvas_item_create();
		rs->canvas_item_set_parent(canvas_item_2d, tree->get_root()->get_world_2d()->get_canvas());
		rs->canvas_item_set_z_index(canvas_item_2d, RSE::CANVAS_ITEM_Z_MAX);
	}
}

void DebugDraw::_on_process_frame() {
	frame++;
	const double now = _now();
	buffer_3d.begin_frame(now, frame);
	buffer_2d.begin_frame(now, frame);
}

void DebugDraw::_on_pre_draw() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs) {
		return;
	}

	if (!buffer_3d.is_empty()) {
		_ensure_3d_resources();
	}
	if (mesh_3d.is_valid()) {
		rs->mesh_clear(mesh_3d);
		has_3d_surface = false;
		if (!buffer_3d.is_empty()) {
			PackedVector3Array vertices;
			PackedColorArray colors;
			vertices.resize(buffer_3d.size() * 2);
			colors.resize(buffer_3d.size() * 2);
			Vector3 *vertex_write = vertices.ptrw();
			Color *color_write = colors.ptrw();
			uint32_t index = 0;
			for (const DebugDrawBuffer<DebugSegment3D>::Entry &entry : buffer_3d.get_entries()) {
				vertex_write[index] = entry.segment.a;
				color_write[index++] = entry.segment.color;
				vertex_write[index] = entry.segment.b;
				color_write[index++] = entry.segment.color;
			}
			Array arrays;
			arrays.resize(RSE::ARRAY_MAX);
			arrays[RSE::ARRAY_VERTEX] = vertices;
			arrays[RSE::ARRAY_COLOR] = colors;
			rs->mesh_add_surface_from_arrays(mesh_3d, RSE::PRIMITIVE_LINES, arrays);
			rs->mesh_surface_set_material(mesh_3d, 0, material_3d->get_rid());
			has_3d_surface = true;
		}
		rs->instance_set_visible(instance_3d, has_3d_surface);
	}

	if (!buffer_2d.is_empty()) {
		_ensure_2d_resources();
	}
	if (canvas_item_2d.is_valid()) {
		rs->canvas_item_clear(canvas_item_2d);
		if (!buffer_2d.is_empty()) {
			Vector<Point2> points;
			Vector<Color> colors;
			points.resize(buffer_2d.size() * 2);
			colors.resize(buffer_2d.size());
			Point2 *point_write = points.ptrw();
			Color *color_write = colors.ptrw();
			uint32_t index = 0;
			for (const DebugDrawBuffer<DebugSegment2D>::Entry &entry : buffer_2d.get_entries()) {
				point_write[index * 2] = entry.segment.a;
				point_write[index * 2 + 1] = entry.segment.b;
				color_write[index] = entry.segment.color;
				index++;
			}
			rs->canvas_item_add_multiline(canvas_item_2d, points, colors, -1.0);
		}
	}

	// Everything currently in the buffers has now been handed to the renderer.
	buffer_3d.mark_drawn();
	buffer_2d.mark_drawn();
}

void DebugDraw::_free_resources() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs) {
		return;
	}
	if (instance_3d.is_valid()) {
		rs->free_rid(instance_3d);
		instance_3d = RID();
	}
	if (mesh_3d.is_valid()) {
		rs->free_rid(mesh_3d);
		mesh_3d = RID();
	}
	if (canvas_item_2d.is_valid()) {
		rs->free_rid(canvas_item_2d);
		canvas_item_2d = RID();
	}
	material_3d.unref();
}

void DebugDraw::_add_3d(const LocalVector<DebugSegment3D> &p_segments, double p_duration) {
	if (!enabled) {
		return;
	}
	_ensure_connected();
	const double now = _now();
	for (const DebugSegment3D &segment : p_segments) {
		buffer_3d.add(segment, now, p_duration, frame);
	}
}

void DebugDraw::_add_2d(const LocalVector<DebugSegment2D> &p_segments, double p_duration) {
	if (!enabled) {
		return;
	}
	_ensure_connected();
	const double now = _now();
	for (const DebugSegment2D &segment : p_segments) {
		buffer_2d.add(segment, now, p_duration, frame);
	}
}

void DebugDraw::set_enabled(bool p_enabled) {
	enabled = p_enabled;
	if (!enabled) {
		clear();
	}
}

void DebugDraw::set_depth_test(bool p_enabled) {
	depth_test = p_enabled;
	if (material_3d.is_valid()) {
		material_3d->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, !depth_test);
	}
}

void DebugDraw::line(const Vector3 &p_from, const Vector3 &p_to, const Color &p_color, double p_duration) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	out.push_back({ p_from, p_to, p_color });
	_add_3d(out, p_duration);
}

void DebugDraw::ray(const Vector3 &p_origin, const Vector3 &p_direction, const Color &p_color, double p_duration) {
	line(p_origin, p_origin + p_direction, p_color, p_duration);
}

void DebugDraw::arrow(const Vector3 &p_from, const Vector3 &p_to, const Color &p_color, double p_duration, real_t p_head_size) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::arrow_3d(out, p_from, p_to, p_color, p_head_size);
	_add_3d(out, p_duration);
}

void DebugDraw::point(const Vector3 &p_position, const Color &p_color, double p_duration, real_t p_size) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::cross_3d(out, p_position, p_size, p_color);
	_add_3d(out, p_duration);
}

void DebugDraw::sphere(const Vector3 &p_center, real_t p_radius, const Color &p_color, double p_duration, int p_segments) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::sphere_3d(out, p_center, p_radius, p_color, p_segments);
	_add_3d(out, p_duration);
}

void DebugDraw::circle(const Vector3 &p_center, const Vector3 &p_normal, real_t p_radius, const Color &p_color, double p_duration, int p_segments) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::circle_3d(out, p_center, p_normal, p_radius, p_color, p_segments);
	_add_3d(out, p_duration);
}

void DebugDraw::box(const Transform3D &p_transform, const Vector3 &p_size, const Color &p_color, double p_duration) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::box_3d(out, p_transform, p_size, p_color);
	_add_3d(out, p_duration);
}

void DebugDraw::aabb(const AABB &p_aabb, const Color &p_color, double p_duration) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::aabb_3d(out, p_aabb, p_color);
	_add_3d(out, p_duration);
}

void DebugDraw::axes(const Transform3D &p_transform, real_t p_size, double p_duration) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::axes_3d(out, p_transform, p_size);
	_add_3d(out, p_duration);
}

void DebugDraw::path(const Vector<Vector3> &p_points, const Color &p_color, double p_duration, bool p_closed) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment3D> out;
	DebugDrawGeometry::path_3d(out, p_points, p_color, p_closed);
	_add_3d(out, p_duration);
}

void DebugDraw::line_2d(const Vector2 &p_from, const Vector2 &p_to, const Color &p_color, double p_duration) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment2D> out;
	out.push_back({ p_from, p_to, p_color });
	_add_2d(out, p_duration);
}

void DebugDraw::arrow_2d(const Vector2 &p_from, const Vector2 &p_to, const Color &p_color, double p_duration, real_t p_head_size) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment2D> out;
	DebugDrawGeometry::arrow_2d(out, p_from, p_to, p_color, p_head_size);
	_add_2d(out, p_duration);
}

void DebugDraw::point_2d(const Vector2 &p_position, const Color &p_color, double p_duration, real_t p_size) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment2D> out;
	DebugDrawGeometry::cross_2d(out, p_position, p_size, p_color);
	_add_2d(out, p_duration);
}

void DebugDraw::circle_2d(const Vector2 &p_center, real_t p_radius, const Color &p_color, double p_duration, int p_segments) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment2D> out;
	DebugDrawGeometry::circle_2d(out, p_center, p_radius, p_color, p_segments);
	_add_2d(out, p_duration);
}

void DebugDraw::rect_2d(const Rect2 &p_rect, const Color &p_color, double p_duration) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment2D> out;
	DebugDrawGeometry::rect_2d(out, p_rect, p_color);
	_add_2d(out, p_duration);
}

void DebugDraw::path_2d(const Vector<Vector2> &p_points, const Color &p_color, double p_duration, bool p_closed) {
	if (!enabled) {
		return;
	}
	LocalVector<DebugSegment2D> out;
	DebugDrawGeometry::path_2d(out, p_points, p_color, p_closed);
	_add_2d(out, p_duration);
}

void DebugDraw::clear() {
	buffer_3d.clear();
	buffer_2d.clear();
}

void DebugDraw::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &DebugDraw::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &DebugDraw::is_enabled);
	ClassDB::bind_method(D_METHOD("set_depth_test", "enabled"), &DebugDraw::set_depth_test);
	ClassDB::bind_method(D_METHOD("is_depth_test_enabled"), &DebugDraw::is_depth_test_enabled);

	ClassDB::bind_method(D_METHOD("line", "from", "to", "color", "duration"), &DebugDraw::line, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("ray", "origin", "direction", "color", "duration"), &DebugDraw::ray, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("arrow", "from", "to", "color", "duration", "head_size"), &DebugDraw::arrow, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(0.25));
	ClassDB::bind_method(D_METHOD("point", "position", "color", "duration", "size"), &DebugDraw::point, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(0.2));
	ClassDB::bind_method(D_METHOD("sphere", "center", "radius", "color", "duration", "segments"), &DebugDraw::sphere, DEFVAL(0.5), DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(24));
	ClassDB::bind_method(D_METHOD("circle", "center", "normal", "radius", "color", "duration", "segments"), &DebugDraw::circle, DEFVAL(0.5), DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(32));
	ClassDB::bind_method(D_METHOD("box", "transform", "size", "color", "duration"), &DebugDraw::box, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("aabb", "aabb", "color", "duration"), &DebugDraw::aabb, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("axes", "transform", "size", "duration"), &DebugDraw::axes, DEFVAL(1.0), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("path", "points", "color", "duration", "closed"), &DebugDraw::path, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(false));

	ClassDB::bind_method(D_METHOD("line_2d", "from", "to", "color", "duration"), &DebugDraw::line_2d, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("arrow_2d", "from", "to", "color", "duration", "head_size"), &DebugDraw::arrow_2d, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(12.0));
	ClassDB::bind_method(D_METHOD("point_2d", "position", "color", "duration", "size"), &DebugDraw::point_2d, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(8.0));
	ClassDB::bind_method(D_METHOD("circle_2d", "center", "radius", "color", "duration", "segments"), &DebugDraw::circle_2d, DEFVAL(16.0), DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(32));
	ClassDB::bind_method(D_METHOD("rect_2d", "rect", "color", "duration"), &DebugDraw::rect_2d, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("path_2d", "points", "color", "duration", "closed"), &DebugDraw::path_2d, DEFVAL(Color(1, 1, 1)), DEFVAL(0.0), DEFVAL(false));

	ClassDB::bind_method(D_METHOD("clear"), &DebugDraw::clear);
	ClassDB::bind_method(D_METHOD("get_segment_count_3d"), &DebugDraw::get_segment_count_3d);
	ClassDB::bind_method(D_METHOD("get_segment_count_2d"), &DebugDraw::get_segment_count_2d);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "depth_test"), "set_depth_test", "is_depth_test_enabled");
}

DebugDraw::DebugDraw() {
	singleton = this;
	// Release builds draw nothing unless a project turns it on explicitly.
	enabled = OS::get_singleton()->has_feature("debug");
}

DebugDraw::~DebugDraw() {
	_free_resources();
	if (singleton == this) {
		singleton = nullptr;
	}
}
